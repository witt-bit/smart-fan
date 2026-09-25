# SmartFan 项目架构剖析

面向 Apple Silicon Mac 的免费开源风扇与温度控制工具。本文是对代码库结构、分层与关键工程决策的整体剖析，供维护者与新贡献者快速建立心智模型。当前版本 **0.2.3.19**。

## 定位

- 菜单栏查看温度与转速，按温度自动调节风扇，并提供命令行控制与数据记录。
- 基于上游 [ThermalForge](https://github.com/ProducerGuy/ThermalForge) 独立维护：改用自己的版本、安装名称与更新渠道，并非上游官方发行版。
- 仅支持 Apple Silicon，最低 **macOS 14 (Sonoma)**。

## 技术栈

| 方面 | 选型 |
|---|---|
| 语言 / 构建 | Swift 5.9 + SwiftPM（`Package.swift`） |
| 平台 | macOS 14+，Apple Silicon |
| 依赖 | 仅 `apple/swift-argument-parser`；其余全部使用系统框架 |
| 系统接口 | IOKit（AppleSMC、IOHID、pwr_mgt）、Metal（GPU 传感器）、DispatchIO |
| 测试 | Swift Testing，`--no-parallel`（socket 集成测试需串行） |
| CI/CD | GitHub Actions（`macos-15`）+ 打 tag 自动出包 |

## 模块与规模

| 模块 | 行数 | 职责 |
|---|---|---|
| `SmartFanCore` | ~5,089 | 核心：SMC 读写、风扇控制、温控曲线、Daemon、协议、日志 |
| `smart-fan`（CLI） | ~1,449 | 命令行入口（`max`/`auto`/`set`/`status`/`discover`/`watch`/`calibrate`/`log` 等子命令） |
| `SmartFanApp` | ~1,900 | AppKit 菜单栏应用：自定义 `NSStatusItem` + 首选项窗口（SwiftUI 承载） |
| `SmartFanLocalization` | ~147 | 英 / 简中 / 繁中本地化资源 |
| `Tests/SmartFanTests` | — | 20+ 测试文件，另含 socket 断连客户端夹具 |

### 核心文件

| 文件 | 行数 | 作用 |
|---|---|---|
| `Daemon.swift` | 890 | root 后台服务，launchd 加载，Unix socket `/var/run/smart-fan.sock` |
| `Calibration.swift` | 753 | 智能模式的机型热特性标定 |
| `ThermalMonitor.swift` | 539 | 温控循环（100ms 热 tick + 2s 监控 tick） |
| `FanControl.swift` | 432 | SMC 解锁 / 设速 / 复位 / 状态 / discover |
| `ThermalLogger.swift` | 300 | CSV 采样与日志会话 |
| `Profile.swift` | 284 | 各配置的温度→转速曲线（迟滞、爬升速率、曲线形状） |
| `SMCConnection.swift` | 263 | AppleSMC 底层 IOKit 封装 |
| `DaemonProtocol.swift` | 239 | 版本化长度前缀帧协议 |
| `FanCommandRouter.swift` | 197 | 命令路由：优先 Daemon，回退直连 SMC |
| `ConnectionServer.swift` | 174 | 并发、有界的 accept + 每连接一次请求/响应 |

## 分层架构

```
        CLI (smart-fan)              AppKit 菜单栏 App
                 \                    /
                  \                  /
                   v                v
                    FanCommandRouter          ← 唯一命令入口
                   /                  \
        (守护进程在运行)            (无守护进程 / 需 root)
                 v                      v
          Daemon (root)            直连 SMC 写入
          /var/run/smart-fan.sock
                 |
          FanControl → SMCConnection → AppleSMC (IOKit)
```

### 菜单栏应用结构（1.0.0 起）

自 1.0.0 起不再使用 SwiftUI 的 `MenuBarExtra`（它无法区分左/右键），改为 AppKit 生命周期：

| 文件 | 作用 |
|---|---|
| `SmartFanApp.swift` | `@main AppDelegate`：`NSApplication` 生命周期、单实例、退出时按 owner 复位风扇 |
| `StatusItemController.swift` | `NSStatusItem`：渲染标签图、左键→首选项、右键→菜单 |
| `PreferencesWindowController.swift` | `NSWindow` + `NSHostingController` 承载首选项 |
| `PreferencesView.swift` | 左竖排标签四页：风扇 / 通用 / 菜单栏 / 关于 |
| `MenuBarLabel.swift` | 手绘单张 `NSImage`（数字两行 / 曲线画布 / 红色告警态） |
| `MenuBarContent.swift` | 数值格式化（单位/度量）与曲线数据 → 图像 |
| `Banners.swift` | 风扇页/关于页的告警条（服务失效、终端占用、需更新、有更新） |


### 1. 命令路由：`FanCommandRouter`

唯一入口。守护进程在运行时优先走 Daemon（免 sudo、与菜单栏应用协同）；否则回退到直连 SMC（需 root）。这样「无守护进程安装」的行为与旧版完全一致，不会静默改变。路由结果用 `FanRoute` 枚举区分（直连 / 经 Daemon / 旧协议回退 / 旧 Daemon 降级），让 CLI 能给出明确提示而非静默分叉。

### 2. 版本化二进制协议：`DaemonProtocol`

4 字节大端长度前缀 + JSON 帧，替代旧的换行字符串协议与 `error:` 前缀嗅探。要点：

- 请求 / 响应有帧上限（4KB / 64KB），在长度前缀处即拒绝，避免本地恶意进程把 root 守护进程拖入无界分配。
- 携带协议版本；比守护进程新的请求得到 `.unsupportedVersion` 与守护进程 build 号。
- 显式 `FrameError`（`oversized`/`legacyPeer`/`closed`/`timeout`/`read`/`write`），不再把超时、读失败与 EOF 混为一谈。

### 3. 并发与一致性

- `ConnectionServer`：有界并发 accept（默认 8），每连接一次请求/响应；header 约 1s、request-body/response-write 约 5s 的独立截止时间，基于 DispatchIO。与 `DaemonServer` 解耦，可对普通 AF_UNIX socket 测试。
- `FanCommandPump` + `DaemonInvariants`：保证并发命令下的风扇状态一致。
- `smcLock`：SMC 硬件访问串行化。

### 4. 安全设计

- socket 位于 `/var/run`（root 0755），非特权进程结构上无法创建条目，路径抢占不可能；开机清空，`RunAtLoad` 在守护进程加载时重建。
- 紧急复位路径的 connect 带 2s 超时——`sudo smart-fan auto` 是「唯一必须永远可用」的命令，阻塞式 connect 会让它卡死，超时后回退为直接 root SMC 复位正是正确行为。

## 上游分叉策略

刻意把改动塞进**新文件**，让合并上游时尽量少触碰原始代码行：

| 新文件 | 用途 |
|---|---|
| `SMCSensorFilter.swift` | 丢弃 IOHID 标识为电池传感器的键，丢弃低于 10°C 的 die 读数 |
| `ThermalStatus+Display.swift` | CPU 行改用 M4 世代的逐核键；标题取 CPU 与 GPU 行的较热者 |

上游原文件仅改必要的一行（如 `FanControl.readTemp` 中的过滤 guard）。逐行记录见 [upstream-divergence.md](upstream-divergence.md)。

## 工程成熟度信号

- **文档完备**：`docs/` 含版本验收记录（0.2.3.15 → .19）、热传感器标定、菜单栏验证、上游偏离清单、路线图。
- **提交规范**：`feat:`/`fix:`/`docs:`/`release:` 前缀，每次 release 附中文发布说明（`docs/releases/`）。
- **测试意识**：专门覆盖断连客户端、日志保留、本地化打包（CI 单独校验 `check-localization-package.sh`）。
- **状态**：主分支干净，8 个 `codex/*` 特性分支已合并。

## 关注点

1. **无 Intel 支持**：SMC 逻辑是 M 系专精，`intel-phase1` 分支尚未并入。
2. **Fork 维护成本**：与上游的持续分叉需人工重放改动（已有流程文档缓解）。
3. **依赖运维**：仅一个依赖，且由 `Package.resolved` 锁定，风险低。

## 相关文档

- [smart-thermal-algorithm.md](smart-thermal-algorithm.md) — 智能温控算法剖析
- [upstream-divergence.md](upstream-divergence.md) — 相对上游的温度代码改动
- [thermal-sensor-calibration-20260924.md](thermal-sensor-calibration-20260924.md) — 热传感器标定
