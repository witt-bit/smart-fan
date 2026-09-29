# 守护进程随 App 自管理 —— 开发计划

让**用户只需要关心 `SmartFan.app`**：不管 app 来自 Homebrew（cask）还是手动下载，**守护进程的安装、更新、重启全部由 app 自己完成**，每次只需一次系统管理员授权。

- 状态：**计划中**（未实现）
- 相关：[update-check-plan.md](update-check-plan.md)（检查更新，前置）、[menu-bar-display-plan.md](menu-bar-display-plan.md)（P5 平台化）、[project-architecture.md](project-architecture.md)

---

## 1. 决策

| 编号 | 决策 |
|---|---|
| D1 | 分发渠道：**Homebrew cask**（只交付 `.app`）；也支持手动下载 `.app` |
| D2 | **面向用户不再提供 CLI**。CLI 仍打进 app 包内，仅供**开发/调试**使用，不放到 PATH |
| D3 | 守护进程二进制 **内嵌在 app 包内**，由 app 安装到 root 私有路径（不联网下载） |
| D4 | 安装/更新/重启守护进程：**每次一次管理员授权**（ad-hoc 签名下的固有成本，见 §8） |
| D5 | 用**复制**而非链接（理由见 §5） |
| D6 | 幂等：内容哈希相同则完全跳过（不复制、不重启、不弹窗） |

## 2. 分工与信任边界

| 组件 | 位置 | 谁写它 | 谁能改它 |
|---|---|---|---|
| 菜单栏 App | `/Applications/SmartFan.app` | Homebrew cask / 用户 | **用户**（`/Applications` 是 `root:admin`） |
| CLI（不给用户） | `SmartFan.app/Contents/MacOS/smart-fan` | 随 app 打包 | 用户 |
| **守护进程** | `/Library/PrivilegedHelperTools/org.witt.smartfan.helper` | **app 以 root 复制** | **只有 root** |
| launchd plist | `/Library/LaunchDaemons/org.witt.smartfan.daemon.plist` | app 以 root 写 | 只有 root |
| socket | `/var/run/smart-fan.sock` | 守护进程 | 只有 root |

关键不变量：**launchd 以 root 执行的二进制，必须位于用户不可写的位置**。app 包不满足这条 → 所以必须复制出去（§5）。

## 3. 路径与命名

```
/Library/PrivilegedHelperTools/org.witt.smartfan.helper   ← 守护进程（root:wheel 0755，不在 PATH）
/Library/LaunchDaemons/org.witt.smartfan.daemon.plist     ← launchd 定义（不变）
/var/run/smart-fan.sock                                   ← IPC（不变）
/Applications/SmartFan.app/Contents/MacOS/SmartFanApp     ← 菜单栏 app
/Applications/SmartFan.app/Contents/MacOS/smart-fan       ← 同一个二进制的 CLI 身份（仅调试）
```

- `SmartFanDaemon.installPath` 从 `/usr/local/bin/smart-fan` 改为 `/Library/PrivilegedHelperTools/org.witt.smartfan.helper`
- 名字刻意不像用户命令（`…helper`），避免被当成 CLI
- **不再安装任何东西到 `/usr/local/bin`**

## 4. 状态机与动作

app 已经通过心跳知道守护进程的版本与存活（`daemonVersionMismatch` / `daemonUnreachable`）。把它们从"显示命令"改成"可点按钮"：

| 状态 | 检测 | 动作 | 授权 | 幂等 |
|---|---|---|---|---|
| **未安装** | 读不到守护进程版本 + socket 不存在 | 复制内嵌二进制 → 写 plist → `bootstrap` | 一次 | — |
| **版本落后** | 心跳报告的版本 ≠ `SmartFanVersion.current` | 复制 → `kickstart -k` | 一次 | 哈希相同则跳过 |
| **无响应** | 连续 2 次心跳失败 | 先 `kickstart -k`；仍失败则重装 | 一次 | — |
| **已一致** | 版本相同且心跳正常 | **什么都不做** | 无 | — |

**幂等实现**：比对 app 包内二进制与 `installPath` 的 SHA-256；
- 相同 → 完全跳过（不复制、不重启、不弹密码）—— 这是日常零打扰的关键
- 不同 → 一次授权：写入 `installPath.new` → `rename()` 原子替换 → `kickstart -k`

授权沿用已有模式（`restartDaemon()` 已在使用）：
`osascript -e 'do shell script "…" with administrator privileges'`

**失败处理**：用户取消授权 → 保持当前状态、横幅继续显示、可重试；**不降级成"去终端敲命令"**（那是我们要消除的体验），但保留 fallback（§7）。

## 5. 为什么必须复制（不是软链接，也不是硬链接）

| 方案 | 判定 | 原因 |
|---|---|---|
| **软链接**指向 app 包 | ❌ **提权漏洞** | `/Applications` 是 `root:admin`，用户属于 `admin` → 用户可替换包内二进制 → 软链接解析到它 → **root 执行攻击者代码** |
| **硬链接**指向同一 inode | ⚠️ 安全但不可用 | 安全（替换包内文件会产生新 inode，`installPath` 仍指旧 inode）。但 Homebrew **Cellar 是版本化路径**（`Cellar/smart-fan/1.0.0/…` → `1.1.0/…`），每次升级 app 位置都变 → 链接全部失效 |
| **复制** | ✅ | `installPath` 与 app 位置**完全无关**；launchd 永远执行同一个 root 拥有的文件 |

> 代价：磁盘上多一份（实测二进制 **3.4 MB**）。这是**位置无关性 + 安全边界**的价钱，不是冗余。
> 连 Apple 官方的 `SMJobBless` / `SMAppService` 也是把 helper **复制**进 `/Library/PrivilegedHelperTools`，从不链接进 app 包。

## 6. Homebrew cask

- cask 只安装 `/Applications/SmartFan.app`（预编译发行包，用户无需 Xcode）
- 不再提供 CLI、不写 `/usr/local/bin`、不装守护进程
- `brew upgrade smart-fan` 之后，用户只需**打开一次 app** → 检测到守护进程版本落后 → 一次密码 → 同步完成

用户视角：
```
brew upgrade smart-fan     （或手动拖入新的 .app）
打开 SmartFan               （一次密码同步后台服务）
```

## 7. 开发/调试时的 CLI

- 包内路径：`/Applications/SmartFan.app/Contents/MacOS/smart-fan`
- 开发时仍用构建产物：`.build/out/Products/Debug/smart-fan`
- `scripts/setup.sh` 保持可用：它调用构建目录里的 `smart-fan install`（该命令会把自己复制到新的 helper 路径），所以开发者不受影响
- **文档只写在「开发与贡献」**，用户手册不出现 CLI 命令

**fallback**：若 app 不在可写位置、或包内缺少该二进制（例如只构建了 app target），动作降级为显示可复制的命令，而不是静默失败。

## 8. 安全边界与残余风险（必须诚实记录）

- ad-hoc 签名 + 管理员授权 = **本地提权风险固有存在**：用户（=admin）可替换 app 包，而 app 会拿它去要 root。**只有真签名 + 公证能消除**。
- 因此本计划**不引入新的风险类别**，但把它显式化了。
- 唯一能去掉「一次密码」的路径是 §11 的 2.0 专项。

## 9. 要改的代码 / 文档

| 位置 | 改动 |
|---|---|
| `Daemon.swift` | `installPath` → 新 helper 路径 |
| `build-app` | 把 CLI 二进制复制进 `Contents/MacOS/smart-fan`（打包时一并签名） |
| `install` 命令 | 增加「从本 bundle 安装自身」的来源；简化/移除 keg 再同步与「寻找匹配 app」逻辑 |
| `uninstall` | 移除 helper 路径与 plist |
| `AppState` | 守护进程同步状态机 + 三个动作（各一次授权） |
| `Banners.swift` | 「需要更新」「不可用」从给命令改为**可点按钮** |
| `ProductIdentityTests` | 断言 `installPath == /Library/PrivilegedHelperTools/org.witt.smartfan.helper` |
| `README.md` | 用户流程删掉 `sudo … install`；CLI 挪到「开发与贡献」 |
| `scripts/setup.sh` / `package-release.sh` | 适配新的安装路径与包内 CLI |
| 新增 | 状态机与哈希幂等的单元测试（纯逻辑） |

## 10. 与 update-check-plan 的关系

| update-check 阶段 | 与本计划的关系 |
|---|---|
| Phase 1（手动检查 / 状态 / 自动检查开关） | **前置**：本计划需要"发现新版本"这个入口 |
| Phase 2 的「按安装方式给不同升级命令」 | **被本计划取代**：守护进程由 app 同步，用户只需知道"怎么拿到新 app" |
| Phase 3（一键更新 app 自身） | 仍然延后；cask 方案下由 brew 负责更新 app |

## 11. 2.0 专项（唯一能去掉「一次密码」的路径）

真实 Developer ID 签名 + 公证，并把守护进程改为 bundle 内 helper + **`SMAppService.daemon`**（macOS 13+，我们最低 14）：

- 二进制 `Contents/MacOS/`，plist `Contents/Library/LaunchDaemons/`
- 用户在「系统设置 → 登录项」批准**一次**
- **app 更新后 helper 自动跟着更新** → 用户真的只需关心 app
- 同一前置顺带解锁 **P5 iCloud 配置同步（收费功能）**

→ 建议作为 **2.0「平台化改造」** 单独规划，一次解决三件事：自更新、隐藏后端、P5。

---

## 12. 任务拆分

- [ ] **P7.1 路径与打包**
  - [x] `installPath` → `/Library/PrivilegedHelperTools/org.witt.smartfan.helper`（含 `scripts/uninstall.sh`、`ProductIdentityTests`）
  - [x] `build-app --cli`：把 `smart-fan` 内嵌到 `Contents/MacOS/smart-fan`；`scripts/setup.sh` 与 `scripts/package-release.sh` 已传入
  - [x] `install` 识别「运行于哪个 bundle」（`SmartFanDaemon.enclosingBundle(of:)`，已单测）；源 bundle 已在 `/Applications` 时**不再自我复制**，但仍计入「本次装入了新 bundle」以走升级重启发路径
  - [ ] 移除 keg 再同步与「寻找匹配 app」旧逻辑（cask 下已是死代码；保留不影响，单独清理）
- [x] **P7.2 app 侧状态机**：缺失 / 落后 / 无响应 + 三个动作（各一次授权）+ 哈希幂等
  - 完成：`app` 侧统一为一个动作 `syncBackgroundService()`，它自己判断该装/该换/该重启：
    - Core：`SmartFanDaemon.isInstalled`、`embeddedCLIPath`（包内二进制；无包时返回 nil）、`installedHelper(isIdenticalTo:)`（SHA-256 幂等）、`installShellCommand(cli:ownerUID:)`（shell 引号）、`appleScript(shellCommand:)`（AppleScript 转义）
    - `install --owner-uid`：app 经管理员授权调用时**没有 SUDO_UID**，改为显式传入（仍拒绝 0）
    - `AppState.syncBackgroundService()`：**哈希相同且版本一致时完全跳过**（不复制/不重启/不弹窗）；否则一次 `osascript … with administrator privileges`
    - `AppState.DaemonSyncState`（idle/working/succeeded/failed/unavailable）+ `backgroundServiceNeedsSync`
    - 无包内二进制时置 `.unavailable`，UI 回退为显示命令（文档化的 fallback）
- [x] **P7.3 横幅改按钮**
  - 完成：`DaemonUpdateBanner`（关于页）从「去终端敲命令」改为 **「更新后台服务」按钮** + 状态行；`DaemonDownBanner`（风扇页）按钮改为 **「修复后台服务」**，也走同一个动作（install 会 bootout+bootstrap，所以“重启”被涵盖）。命令仅在 `.unavailable` 时显示。
- [ ] **P7.4 分发**：cask 定义、CI 产物、README（用户流程去掉 `sudo … install`；CLI 挪到「开发与贡献」）
- [ ] **P7.5 测试**：状态机与哈希幂等（纯逻辑）；身份测试已随 P7.1 更新

---

## 13. 开工状态

P7.1、P7.2、P7.3 已完成。实测：`swift build` 无警告；**180 项测试**（+4）、断连客户端、本地化打包均通过。

**尚未实机验证**（需要交互式授权，无法自动化）：真实弹出管理员密码框并把 helper 装到 `/Library/PrivilegedHelperTools/`、以及升级后的重新同步。建议在 `bash scripts/setup.sh` 装好之后手测一次。

剩余：P7.4（cask + CI + README）、P7.5（状态机测试）、以及清理 cask 下已成死代码的 keg 再同步逻辑。
