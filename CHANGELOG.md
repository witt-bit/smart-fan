# SmartFan changelog

## 1.0.0

- **Customisable menu bar.** Four styles: icon + numbers (temperature above, RPM below, each independently on/off), temperature curve, RPM curve, and both curves overlaid. Each curve is normalised to its own range, so a temperature and an RPM curve share one canvas.
- **New metrics.** Average temperature (mean of every sensor, battery included), and a feels-like temperature (the battery sensor). The menu bar RPM is the average of the fans that actually read.
- **Preferences window replaces the dropdown.** The app now uses a custom status item: **left click** opens the preferences window (Fans / General / Menu Bar / About), **right click** shows Preferences… / every mode / Quit. `MenuBarExtra` could not tell the two clicks apart.
- **Fixed Rate mode.** Hold the fans at a chosen RPM with a slider over the fan's own range, on a par with the temperature modes; the choice and the RPM are remembered across launches.
- **Alerts.** A stale or unreachable background service, or a terminal hold, is reported in the window, and the menu bar icon turns red while one is active. Update-needed and update-available moved to the About page.
- Rename the project to SmartFan. The repository and package are `smart-fan`, the CLI command is `smart-fan`, the app bundle is `SmartFan.app`, the modules are `SmartFanCore` / `SmartFanApp` / `SmartFanLocalization`, and the bundle identity is `org.witt.smartfan.*`. Paths follow: socket `/var/run/smart-fan.sock`, install path `/usr/local/bin/smart-fan`, user data and logs under `~/Library/.../SmartFan/`.
- Remove the ThermalForge / MacFanPro migration path. This is an independent package with its own identity; there is nothing to migrate.
- Consolidate the shell scripts under `scripts/`, including `scripts/setup.sh` and `scripts/uninstall.sh`, and unify their shebang to `#!/usr/bin/env bash`.
- Reissue the LICENSE as MIT, keeping the upstream ThermalForge and MacFanPro copyright notices alongside the SmartFan copyright. Git history and all upstream attribution (NOTICE.md, ThirdPartyNotices/) are retained.

## 0.2.3.19
