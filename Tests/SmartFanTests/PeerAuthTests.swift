//
//  PeerAuthTests.swift
//  SmartFan
//
//  Peer authentication for the daemon's socket, ported from upstream 0.2.3.49.
//
//  The socket is chowned to the daemon's owner with mode 0600, which is the first layer. This
//  is the second: the kernel does not check who is on the other end of an accepted fd, so
//  without it any *other* local user could command the fans. Credentials come from
//  `getpeereid()`, which reports the `LOCAL_PEERCRED` copy taken at connect(), so they stay
//  valid after the peer exits.
//

import Darwin
import Foundation
import Testing

@testable import SmartFanCore

@Suite("Daemon socket peer authentication")
struct PeerAuthTests {

    private func setPath(_ addr: inout sockaddr_un, _ path: String) {
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 104) { _ = strlcpy($0, path, 104) }
        }
    }

    private func bindListener(_ path: String) -> Int32 {
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un(); addr.sun_family = sa_family_t(AF_UNIX); setPath(&addr, path)
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) }
        }
        #expect(r == 0)
        #expect(listen(fd, 16) == 0)
        return fd
    }

    private func connectClient(_ path: String) -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un(); addr.sun_family = sa_family_t(AF_UNIX); setPath(&addr, path)
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) }
        }
        #expect(r == 0)
        return fd
    }

    private func uniquePath(_ tag: String) -> String {
        "/tmp/sf-peer-\(tag)-\(UUID().uuidString.prefix(8)).sock"
    }

    // MARK: - Policy

    @Test("The policy allows exactly root and the owner")
    func policy() {
        let owner: uid_t = 501
        #expect(PeerAuthorizer.allows(uid: 0, ownerUID: owner))
        #expect(PeerAuthorizer.allows(uid: owner, ownerUID: owner))
        #expect(!PeerAuthorizer.allows(uid: 502, ownerUID: owner))
        #expect(!PeerAuthorizer.allows(uid: 501, ownerUID: 502))
        // Nobody at all when the owner is root: root is still allowed as root.
        #expect(PeerAuthorizer.allows(uid: 0, ownerUID: 0))
        #expect(!PeerAuthorizer.allows(uid: 501, ownerUID: 0))
    }

    @Test("decide() maps credentials and errors onto allow / reject / unavailable")
    func decideMapping() {
        func authorizer(_ result: Result<PeerCredentials, PeerCredentialError>) -> PeerAuthorizer {
            PeerAuthorizer(ownerUID: 501) { _ in result }
        }
        let owner = PeerCredentials(uid: 501, gid: 20)
        let root = PeerCredentials(uid: 0, gid: 0)
        let other = PeerCredentials(uid: 502, gid: 20)

        #expect(authorizer(.success(owner)).decide(fd: 0) == .allow(owner))
        #expect(authorizer(.success(root)).decide(fd: 0) == .allow(root))
        #expect(authorizer(.success(other)).decide(fd: 0) == .reject(other))
        // A credential read that fails is a rejection, never an accidental allow.
        #expect(authorizer(.failure(PeerCredentialError(errno: EPERM))).decide(fd: 0)
                == .unavailable(errno: EPERM))
    }

    @Test("Reading credentials from a live connection reports this process")
    func kernelCredentialsOnARealSocket() throws {
        let path = uniquePath("creds")
        let listenFD = bindListener(path)
        defer { close(listenFD); unlink(path) }

        let clientFD = connectClient(path)
        defer { close(clientFD) }
        let accepted = accept(listenFD, nil, nil)
        #expect(accepted >= 0)
        defer { close(accepted) }

        let peer = try PeerAuthorizer.kernelCredentials(accepted).get()
        #expect(peer.uid == getuid())
        #expect(peer.gid == getgid())
    }

    // MARK: - Behaviour

    @Test("A rejected peer is closed unread: nothing served, handler never runs, one log line")
    func rejectedPeerIsClosedUnread() throws {
        // The server closes the fd on rejection, and this test writes into it — a SIGPIPE with
        // the default disposition would kill the test process rather than let write() report
        // EPIPE. (The daemon ignores it for the same reason; see the SIGPIPE regression check.)
        signal(SIGPIPE, SIG_IGN)
        let path = uniquePath("reject")
        let listenFD = bindListener(path)
        defer { close(listenFD); unlink(path) }

        let handled = Locked(0)
        let lines = Locked([String]())
        let server = ConnectionServer(listenFD: listenFD,
                                      authorizer: FakePeerAuthorizer.rejectAll,
                                      log: { line in lines.withLock { $0.append(line) } }) { _ in
            handled.withLock { $0 += 1 }
            return .ok()
        }
        server.start()

        let clientFD = connectClient(path)
        defer { close(clientFD) }
        // A well-formed request, so a served response would be a protocol violation rather than
        // a framing accident.
        let frame = try DaemonProtocol.encodeFrame(DaemonRequest(verb: .state),
                                                   max: DaemonProtocol.maxRequestBytes)
        _ = frame.withUnsafeBytes { write(clientFD, $0.baseAddress, frame.count) }

        // Rejected before a byte is read: the peer sees EOF and no response.
        var buffer = [UInt8](repeating: 0, count: 64)
        let n = read(clientFD, &buffer, buffer.count)
        #expect(n == 0)
        #expect(handled.withLock { $0 } == 0)
        let logged = lines.withLock { $0 }
        #expect(logged.count == 1)
        #expect(logged.first?.contains("rejected uid 12345") == true)
    }

    @Test("An allowed peer is served as usual")
    func allowedPeerIsServed() throws {
        let path = uniquePath("allow")
        let listenFD = bindListener(path)
        defer { close(listenFD); unlink(path) }

        let server = ConnectionServer(listenFD: listenFD,
                                      authorizer: FakePeerAuthorizer.allowAll) { _ in
            .versionResponse("served")
        }
        server.start()

        let clientFD = connectClient(path)
        defer { close(clientFD) }
        var tv = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(clientFD, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        let frame = try DaemonProtocol.encodeFrame(DaemonRequest(verb: .version),
                                                   max: DaemonProtocol.maxRequestBytes)
        _ = frame.withUnsafeBytes { write(clientFD, $0.baseAddress, frame.count) }

        let body = try DaemonProtocol.readFrame(clientFD, max: DaemonProtocol.maxResponseBytes)
        let response = try DaemonProtocol.decode(DaemonResponse.self, from: body)
        #expect(response.ok)
        #expect(response.version == "served")
    }

    // MARK: - Rejection log

    @Test("The rejection log is rate limited, and the count rides on the next line")
    func rejectionLogLimiter() {
        var limiter = RejectionLogLimiter(now: Date(timeIntervalSince1970: 1000))
        var now = Date(timeIntervalSince1970: 1000)

        // A burst of five gets through; then suppression, counted rather than logged.
        for _ in 0..<5 {
            #expect(limiter.record("rejected", now: now) == "rejected")
        }
        now.addTimeInterval(0.5)
        #expect(limiter.record("rejected", now: now) == nil)
        #expect(limiter.record("rejected", now: now) == nil)
        #expect(limiter.flush() == "SmartFan daemon: 2 further peer rejections suppressed")
        #expect(limiter.flush() == nil)

        // A minute later a token has refilled, so a line gets through again.
        now.addTimeInterval(61)
        #expect(limiter.record("rejected", now: now) == "rejected")
        // The next ones are suppressed, counted, and the count rides on the line after that.
        #expect(limiter.record("rejected", now: now) == nil)
        #expect(limiter.record("rejected", now: now) == nil)
        now.addTimeInterval(61)
        #expect(limiter.record("rejected", now: now) == "rejected (2 earlier rejections suppressed)")
    }
}

/// A tiny lock so a test can read a value the server's accept queue writes.
private final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T

    init(_ value: T) { self.value = value }

    func withLock<R>(_ body: (inout T) -> R) -> R {
        lock.lock(); defer { lock.unlock() }
        return body(&value)
    }
}
