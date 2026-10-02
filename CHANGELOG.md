# SmartFan changelog

## 1.0.0

First release under the SmartFan name. Built on ThermalForge 0.2.3 plus the MacFanPro
0.2.3.20-0.2.3.29 fixes.

### Menu bar

- **Two display styles, one pair of switches.** **Numbers** prints the readings and
  **Curve** draws them, and **Show Temperature** / **Show RPM** choose which — either
  alone, or both off for the icon alone. (The temperature curve, RPM curve and both-curves
  styles used to be three separate choices; they were the same decision the switches
  already make.) Each curve is normalised to its own range: the two metrics have different
  units, so one shared scale would be meaningless, and correlated readings would otherwise
  hide one curve behind the other. Each setting is live only while the reading it belongs
  to is on: the temperature metric needs a temperature, units need a number, and the
  sampling interval and window need a curve.
- **New metrics.** Average temperature (the mean of every sensor, battery included) and a
  feels-like temperature (the battery sensor). The menu bar RPM is the average of the fans
  that actually read.
- **Configurable** temperature metric, unit granularity, sampling interval (1-10 s) and
  window (10 s - 3 min), with a live preview of the real menu bar item. The curve canvas
  keeps blank space either side so it does not crowd the neighbouring icons.

### Preferences window

- **The dropdown is gone.** Left click opens the preferences window (Fans / General / Menu
  Bar / About); right click shows Preferences… / every mode / Quit. `MenuBarExtra` cannot
  tell a left click from a right click.
- **One place to choose a mode.** The hands-off profile is labelled **Default** — it hands
  the fans back to Apple — and the separate Smart and Default buttons are gone.
- **Fixed Rate**: hold the fans at a chosen RPM with a slider over the fan's own range, on a
  par with the temperature modes. The choice and the RPM survive a relaunch.
- **Check for Updates** on the About page, reporting inline whether the build is up to date,
  a version is available, or GitHub could not be reached.
- **Status says who controls the fans** — the profile name, SAFETY, Fixed Rate, or Apple
  auto — instead of the monitor's own idle state, which read as "the fan is idle" beside a
  spinning fan.
- The temperature unit is a checkbox that says what it does: **Use °F**.
- **Every reading explains itself.** Each row on the Fans page carries an ⓘ naming the
  sensors behind the number and how they are combined — which is how "CPU" can be traced to
  the calibrated core keys rather than the SoC hotspot keys, and the average to every
  readable sensor rather than anything else.
- Switching modes **acts at once** rather than waiting out the sustained window (4-8 s), the
  ramp **continues from the fans' current speed** instead of dropping to minimum first, and
  a **10 s cooldown** stops modes being flipped back and forth. Default is exempt: it is the
  escape hatch when the fans are loud.

### High-temperature protection

- **A graduated ladder replaces the single threshold.** The fans step up to half speed
  after ten seconds at 90 °C and to full after thirty seconds at 95 °C, and step back
  down the same way once each step has been held for thirty seconds. The old behaviour
  maxed the fans on one reading and released them on one reading, and a die sensor that
  swings several degrees per second crossed both lines repeatedly — the fans spun for a
  few seconds and stopped again, over and over. Each step also tolerates dips of up to
  three seconds: one 100 ms sample below the line no longer discards a nearly-complete
  window.
- **Two switches**, on the Fans page: **High-temperature protection** (on by default;
  off means it never runs) and **Also in Default mode** (off by default, because Default
  means the fans belong to the system, not to a second controller fighting it).
- The background service's own emergency floor moved above the ladder's range (105 °C),
  so the two can no longer pre-empt each other on the same fan.

### Background service

- **The app manages it.** A missing, outdated or unresponsive service is installed, updated
  or restarted from the app with a single administrator prompt, with no terminal commands.
  The installed helper is compared by SHA-256, so nothing is copied, restarted or asked for
  when it is already current.
- The service binary moved out of `/usr/local/bin` to
  **`/Library/PrivilegedHelperTools/org.witt.smartfan.helper`** — root-owned and off `PATH` —
  and the `smart-fan` CLI now ships **inside the app bundle**, for development only.
- Alerts for a stale or unreachable service, or a terminal hold, appear in the window, and
  the menu bar icon turns red while one is active.

### Fan control

- Ported from MacFanPro 0.2.3.20-0.2.3.29: calibration written as the invoking user
  (`sudo calibrate` used to write to root's home, so Smart never loaded it) and reading the
  CPU+GPU safety peak; per-fan range clamping; the profile-switch ordering gate; write-failure
  recovery; watchdog and thermal-floor lock ordering; the 95 °C-until-90 °C hysteresis; and
  the `auto-if-app` conditional release.
- The update check follows the public `/releases/latest` redirect instead of the REST API,
  which allows only 60 requests an hour per IP and is often exhausted behind shared proxies.

### Project

- Renamed from MacFanPro. The repository and package are `smart-fan`, the CLI command is
  `smart-fan`, the app bundle is `SmartFan.app`, the modules are `SmartFanCore` /
  `SmartFanApp` / `SmartFanLocalization`, and the bundle identity is
  `org.witt.smartfan.*`. User data and logs live under `~/Library/.../SmartFan/`.
- `scripts/setup.sh` is the single entry point: build, run, test, install, uninstall,
  open/quit/restart, package, icon, translations, CLI passthrough, logs, diagnosis and
  cleanup. Every script it absorbed was removed rather than duplicated.
- Removed the ThermalForge / MacFanPro migration path: this is an independent package.
- Reissued the LICENSE as MIT, keeping the upstream ThermalForge and MacFanPro copyright
  notices alongside the SmartFan copyright. Git history and all upstream attribution
  (NOTICE.md, ThirdPartyNotices/) are retained.

## 0.2.3.19
