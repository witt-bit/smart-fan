# Check for updates: development plan

Status: planned, not started upstream (recorded 2026-09-26 against upstream 0.2.3.19). Imported into this fork with its paths and references adapted; see "Where this fork already differs" below.

> **Superseded in part** by [daemon-self-management-plan.md](daemon-self-management-plan.md): phase 2's per-install-method upgrade instructions are replaced by the app syncing the background service itself. Phase 1 remains the prerequisite.

Goal: a user-facing "Check for Updates" feature comparable to clash-verge-rev and Macs Fan Control: a manual check button, visible check results, an automatic-check toggle and in-app release notes. The work extends the existing background check; it does not replace it.

## What already exists

| Location | Behavior |
|---|---|
| [`UpdateChecker.swift`](../Sources/SmartFanCore/UpdateChecker.swift) | Fetches GitHub `/releases/latest` and compares versions. Every failure returns `.failed` and shows nothing. `evaluate(...)` is pure and covered by `UpdateCheckerTests`. |
| [`AppState.swift`](../Sources/SmartFanApp/AppState.swift), `maybeCheckForUpdate()` | Runs off the 5-second heartbeat but reaches the network at most once a day, or about one hour after a failure. It persists `updateNextCheck`, `updateLatestVersion`, `updateLatestURL` and `updateDismissedVersion` in UserDefaults. A stored update shows at launch before any network call. |
| [`Banners.swift`](../Sources/SmartFanApp/Banners.swift), `UpdateAvailableBanner` | Blue "Update available" banner on the **About page** with the upgrade command, a "What's new" link and "Later", which dismisses that version until a newer one ships. The dropdown it used to live in was retired in 1.0.0. |
| Release flow | CI creates a **draft** release; it is published only after local acceptance. `/releases/latest` excludes drafts and prereleases, so an unaccepted build is never offered. The release body is `docs/releases/<version>.md`. |

Missing today:
- A manual "Check for Updates" action.
- Visible check states: checking, up to date or failed.
- A way to turn automatic checks off.
- The time of the last check.
- Release notes inside the app.
- Upgrade instructions that match how the app was installed.

## How the reference apps behave

- **clash-verge-rev** uses the Tauri updater. It checks on launch (a setting can turn this off) and has a manual check button in settings. A dialog shows the new version and its Markdown notes, and the user can update or ignore. Updating downloads the new version, replaces the app and restarts it.
- **Macs Fan Control** has a "Check for updates" menu item and an "Automatically check for updates" preference. A window shows the new version with its notes, and the user downloads and installs it from there.

Both can replace themselves in one click because each ships as a single signed app bundle.

## Why SmartFan should not copy one-click install yet

1. **Three components.** SmartFan consists of the menu bar app, the CLI in `/usr/local/bin` and a root launchd daemon. Replacing only the `.app` immediately causes a version mismatch and the "Update needed" banner. The daemon can only be re-synced with `sudo smart-fan install`.
2. **Homebrew owns the files.** Homebrew builds from source and owns its keg. If the app replaced files itself, `brew` would record the wrong version. `brew` also refuses to run as root, so `brew upgrade` cannot run inside a single administrator prompt.
3. **Signing.** Builds are ad-hoc signed and not notarized. Sparkle-style updaters also need an EdDSA signing key and an appcast.

Recommendation: deliver the work in phases and leave one-click install until last, limited to the release-archive channel.

## Phase 1: manual check, visible status and an auto-check toggle (recommended first)

This phase alone matches the reference apps' everyday behavior.

### Core (`UpdateChecker`)
- Decode `body` (release notes) and `published_at` in `Release`, and carry them on `AvailableUpdate`.
- Split failures into `offline`, `rateLimited` (HTTP 403 or 429; unauthenticated GitHub API requests are limited to 60 per hour per IP) and `other`. The automatic check stays silent on every failure. Only a manual check shows the reason.

### AppState
- Add `@Published var updateCheckState` with the states `idle`, `checking`, `upToDate(Date)` and `failed(reason)`.
- Add `checkForUpdatesNow()`:
  - It skips the daily gate.
  - It shares an in-flight flag with the automatic check, so the two never fetch at the same time.
  - Clicks closer together than about 10 seconds are ignored, to protect the rate limit.
  - A manual check **shows a version even if the user pressed "Later" on it**, because the user asked explicitly. It does not clear `updateDismissedVersion`, so automatic checks keep suppressing that version.
- Add an `autoCheckUpdates` preference in UserDefaults, on by default (today's behavior). When it is off, `maybeCheckForUpdate()` returns immediately.
- Persist `updateLastCheckedAt` and show it, for example "Last checked: today 14:02".

### Menu
Extend the existing SmartFan-only language and version section; do not add a window.

```
Language                [System ▾]
Version                   1.0.0
Check automatically            [✓]
[Check for Updates]  Up to date · 14:02
```

- While a check runs, the button shows a spinner and "Checking…".
- The result reads "Up to date", "Version 0.2.3.20 available" or "Check failed (network / rate limit), retry".
- A found update still uses the existing blue banner at the top.
- The panel is 260 points wide. Confirm the English and Chinese strings fit, and keep the section's 6-point spacing.

### Localization
Add the new keys to `en.json` and `zh-Hans.json`, then regenerate `zh-Hant.json` with `swift scripts/update-traditional.swift` (see [gui-localization.md](gui-localization.md)).

### Tests
- Test `check()` with a stubbed `URLProtocol`: 200 newer, 200 same version, 403, 429, 404, malformed JSON and offline.
- Test `applyUpdateCheck` for manual and automatic checks, with and without a dismissed version.
- Test that the in-flight flag and cooldown prevent a second fetch.
- Add checking, up-to-date and failed scenarios to `LocalizedPanelTests` in all three languages.

## Phase 2: update details and install-aware instructions

- Change the banner's "What's new" link to open a small window:
  - It renders `body` with `AttributedString(markdown:)`.
  - Its actions are "Copy update command", "Open release page", "Skip this version" and "Later".
- **Show only the upgrade commands for the user's install method.** Today the banner lists both the Homebrew and source commands.
  - Homebrew (`/opt/homebrew/opt/smart-fan` exists): `brew upgrade smart-fan`, then `sudo "$(brew --prefix smart-fan)/bin/smart-fan" install`.
  - Release archive: a direct link to the new `.tar.gz`, plus the archive install step.
  - Source: `git pull --ff-only && ./setup.sh`.
  - A more reliable alternative to detection: have `sudo smart-fan install` record the install method in `/Library/Application Support/SmartFan/`. **Do not write it into the app's Info.plist**, because that invalidates the code signature.
- Optional: add a `smart-fan check-update` CLI subcommand that reuses `UpdateChecker`.
- Optional: show a small dot on the menu bar label when an update is available. Today the label is marked only for a daemon version mismatch.

## Phase 3 (optional, deferred): one-click update

- **Homebrew:** open Terminal through AppleScript with the full upgrade command filled in, and let the user confirm it. Never run `brew` silently in the background.
- **Release archive:**
  - Download the `.tar.gz` and `SHA256SUMS`, verify the checksum and extract the archive.
  - Run the new archive's own `./bin/smart-fan install` through an administrator prompt, the same way `restartDaemon()` uses `osascript`. Then relaunch the app.
- Before starting this phase, check how an un-notarized, ad-hoc-signed app behaves with quarantine attributes and Gatekeeper after download. Also decide how to guard against a tampered download, since `SHA256SUMS` comes from the same release. This phase carries much more risk and work than phases 1 and 2.

## Where this fork already differs

This plan was written upstream before the fork's 1.0.0 rework, so two things have moved:

| Plan assumes | This fork |
|---|---|
| The notice lives in the menu bar dropdown (`MenuBarView`, 260 pt wide) | The dropdown was retired; banners live on the **About** page of the preferences window |
| No manual check exists | `AppState.checkForUpdatesNow()` and an About-page **Check for Updates** button already exist (with an in-flight flag and a "Checking…" label) |
| The banner lists both the Homebrew and the source command | One command shown; the per-install-method split is superseded by [daemon-self-management-plan.md](daemon-self-management-plan.md) |
| Install is `brew install smart-fan` + `sudo … install` | Moving to a **cask** that delivers the app; the app owns the background service |

So phase 1 is roughly one third done. Still missing: visible `upToDate` / `failed(reason)` results, failure classification, an automatic-check toggle, the last-checked time, the ~10 s cooldown, manual-check-ignores-"Later", and release notes carried on `AvailableUpdate`.

---

## Documents to update when this ships

- README "更新" section. It currently says the in-app notice only checks this repository's releases and never replaces the program.
- `CHANGELOG.md` and the version's `docs/releases/<version>.md`.
- A validation record for the release, like the existing `smart-fan-<version>-validation.md` files.

## Open decisions

1. **Scope:** phase 1 only, with phase 2 later (recommended), or phases 1 and 2 together? Phase 3 (one-click app update) is largely superseded by the cask channel, plus [daemon-self-management-plan.md](daemon-self-management-plan.md) for the background service.
2. **Defaults:** keep automatic checks on by default, and let a manual check show a version the user dismissed with "Later"?
