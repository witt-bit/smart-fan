import Foundation
@testable import SmartFanCore

/// A peer check that always decides the same way, for tests that are not about authentication.
/// `ConnectionServer` requires an authorizer rather than defaulting to allow-all, so that no
/// caller — production or test — can build an unauthenticated server by omission; tests say
/// which policy they want instead.
struct FakePeerAuthorizer: PeerAuthorizing {
    private let verdict: (Int32) -> PeerDecision

    init(_ verdict: @escaping (Int32) -> PeerDecision) { self.verdict = verdict }

    func decide(fd: Int32) -> PeerDecision { verdict(fd) }

    static let allowAll = FakePeerAuthorizer { _ in
        .allow(PeerCredentials(uid: getuid(), gid: getgid()))
    }

    static let rejectAll = FakePeerAuthorizer { _ in
        .reject(PeerCredentials(uid: 12345, gid: 12345))
    }

    var allowedDescription: String { "test policy" }
}
