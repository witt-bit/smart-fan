//
//  Banners.swift
//  SmartFan
//
//  Status banners shared by the preferences window. Extracted from the retired
//  menu bar dropdown (see docs/menu-bar-display-plan.md §8):
//    - DaemonDownBanner     → Fans page (fan control is impossible without it)
//    - DaemonUpdateBanner   → About page
//    - UpdateAvailableBanner → About page
//

import SwiftUI
import SmartFanCore
import SmartFanLocalization

/// A hold set from the terminal (`sudo smart-fan max` / `set`). The app reflects it
/// rather than fighting it, so this explains what is pinned and how to take over.
/// The plan retires this alert once GUI Fixed Rate fully covers the case; until then
/// dropping it would leave the app silently not controlling the fans.
struct ExternalHoldBanner: View {
    @EnvironmentObject var language: AppLanguageStore
    let hold: DaemonHoldState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(language.text("Fans held from Terminal"), systemImage: "terminal.fill")
                .font(.caption.bold())
                .foregroundStyle(.orange)

            Text(describe(hold.command))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(language.text("Press Default below (or pick a profile) to release."))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
    }

    private func describe(_ command: String?) -> String {
        let parts = (command ?? "").split(separator: " ").map(String.init)
        switch parts.first {
        // Approximate language on purpose: the held value is the fan's TARGET, but the
        // RPM shown in the fan rows is the actual tach, which hovers ~1% around it. Exact
        // wording ("pinned to 3500") next to a row reading 3488/3512 looks like a bug.
        case "max":
            return language.text("Fans are held at maximum. The app won't adjust them until you take over.")
        case "set" where parts.count > 1:
            return language.text("Fans are held at about {rpm} RPM. The app won't adjust them until you take over.", ["rpm": parts[1]])
        case "setfan" where parts.count > 2:
            return language.text("Fan {fan} is held at about {rpm} RPM. The app won't adjust fans until you take over.", ["fan": parts[1], "rpm": parts[2]])
        default:
            return language.text("Fans are held manually. The app won't adjust them until you take over.")
        }
    }
}

/// Shown when the daemon has stopped answering — fan control is impossible until
/// it's back. Offers a one-click restart (launchd kickstart via a macOS admin
/// prompt). The daemon's KeepAlive usually restarts it on its own, so this is the
/// manual nudge for the rare stuck case; it never asks the user to reinstall.
struct DaemonDownBanner: View {
    @EnvironmentObject var language: AppLanguageStore
    let onRestart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(language.text("Fan control unavailable"), systemImage: "exclamationmark.octagon.fill")
                .font(.caption.bold())
                .foregroundStyle(.red)

            Text(language.text("The background service isn't responding, so profiles and Default can't change the fans right now."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onRestart) {
                Label(language.text("Restart daemon"), systemImage: "arrow.clockwise")
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .padding(.top, 2)

            Text(language.text("Asks for your password once. If it doesn't come back right away, it will keep retrying on its own."))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.12))
    }
}

/// The background daemon is running a different build than the app. Persistent
/// (no dismiss): a stale daemon should keep nagging until it is re-synced. Shown
/// on the About page.
struct DaemonUpdateBanner: View {
    @EnvironmentObject var language: AppLanguageStore
    let daemonVersion: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(language.text("Update needed"), systemImage: "exclamationmark.triangle.fill")
                .font(.caption.bold())
                .foregroundStyle(.orange)

            Text(language.text("The background service is running {daemonVersion}, but the app is {appVersion}. Fan control may not match what you set until they're re-synced.", ["daemonVersion": daemonVersion, "appVersion": SmartFanVersion.current]))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(language.text("The background service keeps running the old build after an upgrade; re-syncing restarts it on the new one."))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text(language.text("Run this in Terminal:"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
                .fixedSize(horizontal: false, vertical: true)

            CommandChip(command: "sudo smart-fan install")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
    }
}

/// A newer release than the installed build. Informational: tells the user an
/// update shipped and how to get it — the app can't run `brew upgrade` for them.
/// Dismissible per-version via "Later". Shown on the About page.
struct UpdateAvailableBanner: View {
    @EnvironmentObject var language: AppLanguageStore
    let update: AvailableUpdate
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(language.text("Update available"), systemImage: "arrow.down.circle.fill")
                .font(.caption.bold())
                .foregroundStyle(.blue)

            Text(language.text("SmartFan {version} is available. You have {appVersion}.", ["version": update.version, "appVersion": SmartFanVersion.current]))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(language.text("Update with:"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
                .fixedSize(horizontal: false, vertical: true)

            CommandChip(command: "brew upgrade smart-fan && sudo smart-fan install")

            Text(language.text("Built from source? Run  git pull && ./scripts/setup.sh"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                if let url = URL(string: update.url) {
                    Link(language.text("What's new"), destination: url)
                        .font(.caption2)
                }
                Spacer()
                Button(language.text("Later"), action: onDismiss)
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.12))
    }
}

/// A selectable command string on a subtle background.
struct CommandChip: View {
    let command: String

    var body: some View {
        Text(command)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15)))
    }
}
