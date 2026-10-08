<p align="center">
  <img src="assets/logo/web/icon-192.png" width="120" alt="SmartFan">
</p>

# SmartFan

[![CI](https://github.com/witt-bit/smart-fan/actions/workflows/ci.yml/badge.svg)](https://github.com/witt-bit/smart-fan/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/witt-bit/smart-fan?sort=date)](https://github.com/witt-bit/smart-fan/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

面向 Apple Silicon Mac 的免费开源风扇控制工具，在菜单栏查看温度和转速，按温度自动调节风扇，也可通过命令行控制和记录数据。

SmartFan 基于 [ThermalForge](https://github.com/ProducerGuy/ThermalForge) 独立维护，使用自己的版本、安装名称和更新渠道，并非上游官方发行版。

[安装](#安装) · [使用](#使用) · [更新](#更新) · [卸载](#卸载) · [日志与数据](#日志与数据) · [常见问题](#常见问题) · [开发与贡献](#开发与贡献) · [参与贡献](#参与贡献)

## 功能与界面

- **温度与转速监测**：查看 CPU、GPU、内存、SSD、环境温度及各风扇实际转速，具体读数取决于机型提供的传感器。
- **自动风扇控制**：提供智能、静音、均衡、性能和最大转速模式，也可恢复 Apple 自动控制。
- **可自定义菜单栏**：四种样式——数值（温度在上、转速在下，可各自开关）、温度曲线、转速曲线、双曲线叠加；可配置温度度量（均温/体感）、单位、采样频率与时间窗口。
- **菜单栏交互**：**左键**打开首选项窗口，**右键**弹出菜单（首选项… / 全部模式 / 退出）；不显示 Dock 图标。
- **固定速率**：除温度曲线模式外，还可直接把风扇固定在指定转速（滑块，范围取自硬件）；模式选择会被记住。
- **语言与显示设置**：支持英语、简体中文、繁体中文、跟随系统、摄氏/华氏切换及登录时启动。
- **命令行与后台服务**：支持指定转速、读取状态和 CSV 数据采样；正常安装后，应用和普通控制命令通过后台服务操作风扇。

下面是本机运行 SmartFan 0.2.3.19 的真实截图，依次为英文和简体中文界面：

<img src="docs/images/menu-bar-en.png" alt="SmartFan menu in English: fan speeds, temperatures, profiles, language setting and Quit" width="320"> <img src="docs/images/menu-bar-zh-CN.png" alt="SmartFan 菜单（简体中文）：风扇转速、温度、控制模式、语言设置与退出按钮" width="320">

## 系统要求

- Apple Silicon Mac，macOS 14 或更高版本；不支持 Intel Mac。
- 风扇控制需要带风扇的机型，无风扇机型无法使用该功能。
- 首次安装或更新后台服务需要管理员权限；Homebrew 和源码安装还需要 Xcode 16 或更高版本。

当前实机验证以 M4 Max MacBook Pro 为主。其他机型、macOS 版本和显示环境不应视为已验证，具体范围见 [0.2.3.19 验证记录](docs/smart-fan-0.2.3.19-validation.md)。

## 安装

以下三种方式**选择一种即可，不需要依次执行**。如果 SmartFan 已在运行，请先在菜单中点击“退出”。

| 安装方式 | 适合场景 | 是否需要本机编译 |
| --- | --- | --- |
| Homebrew | 使用 Homebrew 安装和管理版本 | 是，需要 Xcode |
| 下载发行包 | 直接使用已编译的应用和 CLI | 否，无需 Xcode |
| 源码构建 | 修改代码、调试或自行构建 | 是，需要 Xcode |

### 方式一：通过 Homebrew 安装

前提：已安装 [Homebrew](https://brew.sh/zh-cn/) 和 Xcode 16 或更高版本。目前配方在本机从源码构建。

在终端中依次执行：

```bash
brew tap witt-bit/smart-fan
brew trust witt-bit/smart-fan
brew install smart-fan
sudo "$(brew --prefix smart-fan)/bin/smart-fan" install
open /Applications/SmartFan.app
```

Homebrew 7 起默认不加载第三方 tap 的配方，需要先用 `brew trust` 明确信任本 tap（只需一次）。Homebrew 负责下载、编译和管理版本；`sudo` 那条命令将对应版本的应用和后台服务安装到系统中。配方维护在 [witt-bit/homebrew-smart-fan](https://github.com/witt-bit/homebrew-smart-fan)。

### 方式二：下载发行包安装

此方式无需安装 Homebrew 或 Xcode。

1. 前往 [Releases](https://github.com/witt-bit/smart-fan/releases/latest)，下载 `SmartFan-版本号-macos-arm64.tar.gz`。请选择这个发行包，而非 GitHub 自动生成的 `Source code` 源码包。
2. 双击解压，保留文件夹内的 `SmartFan.app` 和 `bin` 目录。
3. 在终端中进入解压后的文件夹，执行安装并打开应用。

例如，`0.2.3.19` 解压在“下载”目录时：

```bash
cd ~/Downloads/SmartFan-0.2.3.19-macos-arm64
sudo ./bin/smart-fan install
open /Applications/SmartFan.app
```

其他版本或下载位置，请相应替换文件夹路径。安装成功后，可以删除压缩包和解压文件夹。

仅将 `SmartFan.app` 拖入“应用程序”目录，无法完成后台服务安装。当前发行包使用 ad-hoc 签名，尚未经过 Apple 公证，首次运行可能出现 macOS 安全提示，见[常见问题](#常见问题)。

### 方式三：从源码构建安装

前提：已安装 Xcode 16 或更高版本。

```bash
git clone https://github.com/witt-bit/smart-fan.git
cd smart-fan
./scripts/setup.sh install
```

`scripts/setup.sh` 会编译源码、组装应用、请求管理员权限完成安装，并打开 SmartFan，无需再执行其他安装命令。

此方式默认构建仓库的 `main` 分支，可能包含尚未发行的修改。如需构建指定发行版，可在运行 `./scripts/setup.sh install` 前执行 `git checkout v0.2.3.19`，版本号按需替换。

### 安装完成后

应用安装在 `/Applications/SmartFan.app`，打开后显示在菜单栏中，不显示 Dock 图标。需要登录后自动运行时，在应用中勾选“登录时启动”。

终端输入管理员密码时不会显示字符，输入完成后按回车即可。应用与已安装后台服务配合工作，日常使用无需重复输入密码。

## 使用

### 菜单栏与首选项

- **左键**点击菜单栏图标 → 打开**首选项窗口**（风扇 / 通用 / 菜单栏 / 关于四个页）。
- **右键**点击 → 快捷菜单：**首选项…** / **模式**（全部模式，带勾选）/ **退出**。

菜单栏显示什么由「首选项 → 菜单栏」决定：

| 样式 | 显示 |
| --- | --- |
| 数值 | 温度在图标右上、转速在右下；可只选其一，也可都关（只留图标） |
| 温度曲线 / 转速曲线 | 一个小折线窗，分别显示均温或转速 |
| 双曲线叠加 | 两条曲线叠加，各自按窗口内上下限归一化 |

可配置项：温度度量（**均温** = 所有传感器平均 / **体感** = 电池温度）、单位（无 / `48°` / `48°C`）、采样频率（1/2/3/5/10 秒）、时间窗口（10/30/60 秒 / 3 分钟）。页面右上角有**实时预览**。

出现告警时（后台服务失效 / 版本不一致 / 终端占用），菜单栏图标会**整体变红**。

### 模式

在「首选项 → 风扇」或右键菜单里选择，切换会被记住（重启后恢复）。

| 模式或按钮 | 行为 |
| --- | --- |
| 静音（Apple 默认） | 常规温度下交由 Apple 自动控制，并非强制关闭风扇 |
| 均衡 | 根据温度逐步提高转速，采用较缓和的响应曲线 |
| 性能 | 更快响应温度上升，允许更高的目标转速 |
| 最大转速 | 达到温度及持续时间触发条件后使用最高转速，并非始终全速 |
| 智能 | 根据温度及变化趋势调节转速；有有效校准数据时结合使用，无需先校准也能运行 |
| 固定速率 | 把风扇固定在指定转速（滑块，范围取自硬件） |
| 默认 | 取消当前接管并恢复 Apple 自动控制 |

高温保护逻辑可能覆盖当前模式。

风扇页还显示当前模式、运行状态、各风扇转速与传感器温度；可切换温度单位、登录时启动和语言，并查看当前版本号。繁体中文使用与简体中文相同的表述，仅转换字形。

### 常用命令

以下命令按需要单独执行。正常安装且后台服务运行时，表中的命令无需 `sudo`。

| 命令 | 用途 |
| --- | --- |
| `smart-fan --version` | 查看当前 CLI 版本 |
| `smart-fan status` | 以 JSON 输出风扇转速和温度 |
| `smart-fan max` | 立即将所有风扇设为最大转速 |
| `smart-fan set 3000` | 请求将所有风扇设为 3000 RPM，实际值受硬件范围限制 |
| `smart-fan set 3000 --fan 0` | 仅设置索引为 0 的风扇 |
| `smart-fan auto` | 恢复 Apple 自动控制，保留菜单栏应用运行 |
| `smart-fan auto --stop-app` | 退出菜单栏应用并恢复 Apple 自动控制 |
| `smart-fan log --duration 60s` | 采集 60 秒传感器数据并保存为 CSV |
| `smart-fan --help` | 查看全部命令；单个命令可追加 `--help` |

`max` 和 `set` 会建立终端持有的转速设置，应用会显示相应提示并暂停自己的调节。点击“默认”、重新选择模式或运行 `smart-fan auto` 可以取消该设置。仅退出菜单栏应用不会取消终端持有的转速。

`smart-fan auto` 不关闭应用；应用中的自动模式仍可能再次接管。需要完全交回 macOS 时，使用 `smart-fan auto --stop-app`。

高级命令 `watch` 会按模式持续控制风扇，并非只读监测；`calibrate` 会运行负载并改变风扇转速。这两项操作需要管理员权限，使用前请阅读各自的 `--help`，它们不是日常使用的必需步骤。

## 更新

应用内的更新提示仅检查本仓库的发行版，不会自动替换程序。请沿用原安装方式更新，并在替换后台服务前退出应用。

### Homebrew 更新

```bash
brew update
brew upgrade smart-fan
smart-fan auto --stop-app
sudo "$(brew --prefix smart-fan)/bin/smart-fan" install
open /Applications/SmartFan.app
```

`brew upgrade` 更新 Homebrew 中的文件，随后仍需同步后台服务和 `/Applications` 中的应用。如果 Homebrew 提示 `untrusted tap`，先执行一次 `brew trust witt-bit/smart-fan`。使用 `brew --prefix` 指向刚升级的版本，避免误用旧的系统副本。

### 发行包更新

下载并解压新版本，退出正在运行的应用，然后进入**新版本的解压目录**，重新执行发行包安装步骤。安装器会替换应用和后台服务，不需要先卸载，用户数据会保留。

### 源码更新

若按前文克隆了 `main` 分支，先保存自己的代码修改、退出应用，再在源码目录执行：

```bash
git pull --ff-only
./scripts/setup.sh install
```

若之前检出了指定版本标签，请先 `git fetch origin --tags`，再检出需要的新标签并运行 `./scripts/setup.sh install`。

## 卸载

移除应用、命令行工具和后台服务，同时保留用户数据：

```bash
sudo smart-fan uninstall
```

如需同时删除当前用户的模式文件、校准数据、采样记录和运行日志，以及后台服务的运行日志，请**改用**：

```bash
sudo smart-fan uninstall --purge-data
```

如果通过 Homebrew 安装，完成上述卸载后，还需执行：

```bash
brew uninstall smart-fan
```

`--purge-data` 清理当前用户的 `~/Library/Application Support/SmartFan/`、`~/Library/Logs/SmartFan/`，以及后台服务的 `/var/root/Library/Logs/SmartFan/`；不会删除自定义导出目录或单独保存的界面偏好。仅拖走 App 或仅运行 `brew uninstall` 不会完成后台服务卸载。

## 日志与数据

运行日志和手动采样数据使用不同的保留策略：

| 数据 | 默认位置 | 保留策略 |
| --- | --- | --- |
| 应用运行日志 | `~/Library/Logs/SmartFan/` | 最多 7 个自然日（含当天），单文件最多 5 MiB，目录内受管理日志合计最多 50 MiB |
| 后台服务运行日志 | `/var/root/Library/Logs/SmartFan/` | 与应用运行日志相同，独立计算容量与保留时间 |
| 临时 CSV 采样 | `~/Library/Application Support/SmartFan/logs/` | 每次采样的 CSV 最多 100 MiB，正常结束后保留 24 小时 |
| 模式与校准数据 | `~/Library/Application Support/SmartFan/` | 不会按日志策略自动清理 |

运行日志在启动、开始写入新文件（达到单文件上限或跨日）及运行期间每小时清理；两处受管理的运行日志默认容量合计最多 100 MiB。磁盘写入失败时会暂停文件日志并稍后重试，待写队列有容量限制。

后台服务日志属于 root 用户，查看时需要管理员权限，例如查看当天最后 50 行：

```bash
sudo tail -n 50 "/var/root/Library/Logs/SmartFan/smart-fan-$(date +%F).log"
```

临时采样达到容量上限时停止并保留已有数据。正常结束、Ctrl-C 或 SIGTERM 后更新到期时间；异常退出也会留下可清理标记。应用启动、运行期间每小时及下一次采样启动时，会清理已到期且不再写入的采样目录。应用未运行时，用户的采样文件会保留到下一次清理。旧版本留下的、没有到期标记的采样目录无法与手动导出区分，因此不会自动删除，不需要时可以手动删除。

**采样的 100 MiB 限制针对每次记录，不是整个采样目录的总容量。** 使用 `--output <目录>` 或 `--no-expire` 的采样会永久保留且没有该容量限制，需自行管理。未标记到期时间的旧采样和其他文件不会自动删除。

## 常见问题

### 提示后台服务不可用或版本不一致

应用、CLI 和后台服务需要来自同一版本。先退出应用，再按原安装方式重新执行安装或同步步骤：Homebrew 用户使用配方中的 CLI，发行包用户使用解压目录内的 `./bin/smart-fan`。完成后重新打开应用；若仍失败，请保留终端错误和对应时段日志以便排查。

### 下载后提示无法验证开发者

当前发行包尚未经过 Apple 公证。如果确认文件来自本仓库且未遭篡改，可按照 [Apple 官方说明](https://support.apple.com/zh-cn/102445)，在尝试打开后前往“系统设置 → 隐私与安全性”查看“仍要打开”选项。

发行页提供 `SHA256SUMS`。将它与压缩包放在同一目录，可运行 `shasum -a 256 -c SHA256SUMS` 核对下载完整性；校验和不等同于 Apple 公证。

### 温度或风扇读数与其他机器不同

不同机型提供的传感器、风扇数量及转速范围可能不同。提交问题时，请附上机型、macOS 版本、SmartFan 版本、安装方式、复现步骤，以及相关状态输出或日志片段。问题反馈入口：[Issues](https://github.com/witt-bit/smart-fan/issues)。

### 温度与 Stats 等工具不一致

SmartFan 的 CPU、GPU 行显示对应传感器中的**最高值**，可与 Stats 的“Hottest CPU / Hottest GPU”对照，不要与“Average”对照。在 M4 系列上，CPU 行使用与 Stats 相同的核心传感器；其他芯片按传感器前缀分组，可能与其他工具的选择不同。风扇控制和 95°C 安全阈值跟随芯片最热点（包括不在 CPU 行显示的热点传感器），因此风扇可能在 CPU、GPU 行都未到阈值时开始提速。对照方法与实测数据见 [传感器校准记录](docs/thermal-sensor-calibration-20260924.md)。

## 开发与贡献

### 项目结构

| 路径 | 内容 |
| --- | --- |
| [`Sources/SmartFanApp/`](Sources/SmartFanApp/) | SwiftUI 菜单栏应用、界面状态和交互 |
| [`Sources/SmartFanCore/`](Sources/SmartFanCore/) | SMC 访问、风扇控制、后台通信、模式与日志 |
| [`Sources/SmartFanLocalization/`](Sources/SmartFanLocalization/) | 语言选择和翻译资源 |
| [`Sources/SmartFanCLI/`](Sources/SmartFanCLI/) | CLI、应用组装、安装与卸载入口 |
| [`Tests/SmartFanTests/`](Tests/SmartFanTests/) | 自动化测试 |
| [`scripts/setup.sh`](scripts/setup.sh) | 开发与维护入口：编译、运行、测试、安装、卸载、打包、自检 |
| [`assets/logo/`](assets/logo/) | 图标与品牌资源：macOS/iOS 图标集、网站图标、矢量 logo。见 [说明](assets/logo/README.md) |

### 构建与验证

在仓库根目录执行：

```bash
scripts/setup.sh build           # 编译
scripts/setup.sh test            # 单元测试 + 断连回归 + 打包资源校验
scripts/setup.sh test --release  # 同上，Release 构建
scripts/setup.sh check           # build + test（提交前跑这个）
```

`scripts/setup.sh help` 列出全部命令（编译、运行、测试、安装、卸载、打包、自检）。

这些命令构建和测试项目，不执行安装流程。`scripts/setup.sh test` 按顺序运行 Swift 单元测试、断连客户端回归与打包资源校验；CI 覆盖 Debug 与 Release。

本地生成发行包：

```bash
scripts/setup.sh package
```

产物输出到 `dist/`，包括完整应用与 CLI 的 `.tar.gz` 和 `SHA256SUMS`。打包不会替换本机已安装的应用；需要安装开发版本时再运行 `./scripts/setup.sh install`。

提交 [Pull Request](https://github.com/witt-bit/smart-fan/pulls) 时，请说明具体问题、改动范围和验证结果。涉及温控、后台通信或原生菜单行为的修改，应补充对应的本机验证，并区分自动化测试、隔离显示测试和真实硬件结果。

### 文档与维护约定

- [待办事项](docs/todo.md)：所有未完成、待决策、待清理事项的统一索引（开发前先看这个）。
- [更新记录](CHANGELOG.md)：已发行版本的主要变化。
- [发布说明规范与模板](docs/releases/README.md)：按版本维护发布说明、下载入口、升级提示和验证依据。
- [0.2.3.15 验证记录](docs/smart-fan-0.2.3.15-validation.md)：发行产物、本机运行和未覆盖环境。
- [0.2.3.16 验证记录](docs/smart-fan-0.2.3.16-validation.md)：温度传感器修正、与 Stats 的对照、发行产物与 Homebrew 升级。
- [0.2.3.17 验证记录](docs/smart-fan-0.2.3.17-validation.md)：日志写入性能、卸载清理后台服务日志。
- [0.2.3.18 验证记录](docs/smart-fan-0.2.3.18-validation.md)：菜单中的语言与版本区块。
- [0.2.3.19 验证记录](docs/smart-fan-0.2.3.19-validation.md)：语言下拉框宽度。
- [相对上游的温度改动](docs/upstream-divergence.md)：合并上游时需要重新施加的改动。
- [GUI 本地化](docs/gui-localization.md)：英语键名、简体翻译、繁体字形转换及资源校验流程。
- [菜单栏标签验证](docs/menu-bar-label-validation.md)：最小宽度、位数变化和隔离显示测试。
- [菜单栏显示与首选项验证](docs/menu-bar-display-validation.md)：1.0.0 的状态栏项、四种样式、新度量与固定速率；含未验证项与残余风险。
- [守护进程随 App 自管理计划](docs/daemon-self-management-plan.md)：cask 分发、app 内嵌后端、不再向用户提供 CLI。
- [检查更新功能计划](docs/update-check-plan.md)：手动检查、可见状态、自动检查开关。
- [M4 风扇接管修复](docs/m4-handoff-repair.md)：相关硬件行为与修复依据。

`docs/upstream/` 和早期验收文档用于保存历史背景，不代表当前发行版或所有机型的测试结论。

版本号采用 **上游版本号 + 第四段修订号**，由 [`Version.swift`](Sources/SmartFanCore/Version.swift) 定义。例如 `0.2.3.15` 基于上游 `0.2.3`；只有实际合入新的上游版本后才更新前三段。应用和 CLI 按各段数字比较版本，缺省段视为 0，不为特定旧版添加比较例外。

## 参与贡献

欢迎任何形式的贡献：

- **问题反馈**：在 [Issues](https://github.com/witt-bit/smart-fan/issues) 报告问题或提交兼容性报告，请附上机型、macOS 版本、SmartFan 版本和 `smart-fan status` 输出。
- **代码**：按 [开发与贡献](#开发与贡献) 中的步骤构建和验证，再通过 [Pull Request](https://github.com/witt-bit/smart-fan/pulls) 提交。
- **翻译**：改进英文或简体中文界面文案，繁体中文由脚本生成，流程见 [GUI 本地化](docs/gui-localization.md)。

### 贡献者

<a href="https://github.com/witt-bit/smart-fan/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=witt-bit/smart-fan" alt="SmartFan 贡献者">
</a>

## 来源与许可

SmartFan 由 [@hongyukeji](https://github.com/hongyukeji) 维护，遵循 [MIT License](LICENSE)。项目完整保留 ThermalForge 上游版权与许可，衍生关系及第三方依赖说明见 [NOTICE.md](NOTICE.md) 和 [ThirdPartyNotices/](ThirdPartyNotices/)。
