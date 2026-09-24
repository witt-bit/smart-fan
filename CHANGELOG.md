# SmartFan changelog

## 1.0.0

- Rename the project to SmartFan. The repository and package are `smart-fan`, the CLI command is `smart-fan`, the app bundle is `SmartFan.app`, the modules are `SmartFanCore` / `SmartFanApp` / `SmartFanLocalization`, and the bundle identity is `org.witt.smartfan.*`. Paths follow: socket `/var/run/smart-fan.sock`, install path `/usr/local/bin/smart-fan`, user data and logs under `~/Library/.../SmartFan/`.
- Remove the ThermalForge / MacFanPro migration path. This is an independent package with its own identity; there is nothing to migrate.
- Consolidate the shell scripts under `scripts/`, including `scripts/setup.sh` and `scripts/uninstall.sh`, and unify their shebang to `#!/usr/bin/env bash`.
- Reissue the LICENSE as MIT, keeping the upstream ThermalForge and MacFanPro copyright notices alongside the SmartFan copyright. Git history and all upstream attribution (NOTICE.md, ThirdPartyNotices/) are retained.

## 0.2.3.19
