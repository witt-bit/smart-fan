<p align="center">
  <img src="assets/logo/web/icon-192.png" width="120" alt="SmartFan">
</p>

# SmartFan

[![CI](https://github.com/witt-bit/smart-fan/actions/workflows/ci.yml/badge.svg)](https://github.com/witt-bit/smart-fan/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/witt-bit/smart-fan?sort=date)](https://github.com/witt-bit/smart-fan/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

面向 Apple Silicon Mac 的免费开源风扇控制工具。菜单栏直接显示温度与转速，按温度曲线调节风扇，也可以在菜单里手动指定转速或交给系统自动控制。

项目基于 [ThermalForge](https://github.com/ProducerGuy/ThermalForge) 独立维护，与上游使用各自的版本号、安装名称和更新渠道，并非上游官方发行版。

[功能](#功能) · [系统要求](#系统要求) · [安装](#安装) · [使用](#使用) · [更新](#更新) · [卸载](#卸载) · [常见问题](#常见问题) · [开发与贡献](#开发与贡献)

## 功能

- **菜单栏显示**：图标配温度与转速的数字，或一条折线曲线。样式、度量、单位、采样频率与时间窗口都可以在首选项里改，页面上有实时预览。
- **按温度调节**：均衡、性能、最大转速三条内置曲线，外加「智能」模式——它结合温度的变化趋势判断，有校准数据时一并使用。
- **固定速率**：用滑块把风扇固定在指定转速，范围取自硬件本身。
- **高温防护**：温度持续偏高时分级提高转速（详见 [高温防护](#高温防护)），两个开关分别控制是否启用、以及是否在「默认」模式下也生效。
- **后台服务自管理**：应用自己安装、更新、重启后台服务，只需要一次管理员授权，日常不再需要密码。
- **语言**：简体中文、繁体中文、英语，以及跟随系统。

## 系统要求

- Apple Silicon Mac，macOS 14 或更高版本；不支持 Intel Mac。
- 风扇控制需要带风扇的机型，无风扇机型无法使用该功能。
- 只有从源码构建时才需要 Xcode 16 或更新版本。

## 安装

> 目前**只有从源码构建**这一条路：Homebrew cask 尚在准备中，本仓库也还没有发行包。

```bash
git clone https://github.com/witt-bit/smart-fan.git
cd smart-fan
./scripts/setup.sh install
```

这条命令会编译源码、组装应用、把它安装到 `/Applications`，并在首次运行时**请求一次管理员授权**来安装后台服务。之后应用与后台服务一起工作，日常使用不再需要密码。

安装完成后：

- 应用位于 `/Applications/SmartFan.app`，**只显示菜单栏图标，不占 Dock**。
- 需要登录后自动运行，在应用里勾选「登录时启动」。
- 当前构建使用 ad-hoc 签名、未经过 Apple 公证，首次打开可能出现系统安全提示，见[常见问题](#常见问题)。

## 使用

### 菜单栏与首选项

- **左键**点击图标 → 打开**首选项窗口**：风扇 / 通用 / 菜单栏 / 传感器 / 关于。
- **右键**点击 → 快捷菜单：首选项… / 全部模式 / 退出。

菜单栏显示什么由「首选项 → 菜单栏」决定：

| 样式 | 显示 |
| --- | --- |
| **数值** | 图标，温度在右上、转速在右下；可以只开一个，也可以都关（只留图标） |
| **曲线** | 折线窗，温度占上半、转速占下半，各自按窗口内的上下限归一化 |

「显示温度」与「显示转速」决定显示哪几项数值或哪几条曲线；温度度量（**均温** = 所有传感器平均 / **体感** = 电池温度）、单位、采样频率（1/2/3/5/10 秒）与时间窗口（10/30/60 秒 / 3 分钟）都只在相关项开启时生效。

出现告警时（后台服务失效、版本不一致、终端占用了风扇），图标会**整体变红**。

### 模式

在「首选项 → 风扇」或右键菜单里选择，选择会被记住。

| 模式 | 行为 |
| --- | --- |
| 默认 | 交回 Apple 自动控制。**本应用不接管风扇**，并非强制关闭 |
| 均衡 | 随温度逐步提高转速，响应较缓和 |
| 性能 | 更快响应温度上升，允许更高的目标转速 |
| 最大转速 | 达到温度与持续时间条件后使用最高转速，并非始终全速 |
| 智能 | 按温度与变化趋势调节；有校准数据时结合使用，没校准也能运行 |
| 固定速率 | 把风扇固定在指定转速 |

### 高温防护

温度持续偏高时分两步提高转速，而不是一次拉满：

| 条件 | 动作 |
| --- | --- |
| ≥ 90 °C 持续 10 秒 | 转速升到最大的一半 |
| 半速下 ≥ 95 °C 持续 30 秒 | 转速升到最大 |
| 满速 30 秒后降到 95 °C 以下 | 回到半速 |
| 半速 30 秒后降到 85 °C 以下 | 停止，交回所选模式 / 系统 |

- 每一档至少保持 30 秒才可能降档，短暂的温度抖动不会让风扇反复起停。
- 两个开关：「高温防护」（默认开，关掉后永不启用）、「在『默认』模式也生效」（默认关——默认模式表示风扇归系统管，不该再插手）。
- 判定用的是**真实 CPU 核心与 GPU** 的温度；模式曲线用的是另一套取值（见下一节）。

### 读数与传感器

「风扇」页那几行是显示值：CPU、GPU、RAM、SSD、环境、均温、体感。每行后面的 ⓘ 说明它取自哪些传感器、怎么合并。

想核对某个数字的来源，打开「**传感器**」页：它列出本机所有被读取的传感器键、数值，以及被忽略的键和原因。

由于按温度曲线调节时使用的是另一套取值（芯片上的热点键），风扇**可能在这几行显示的温度还没到阈值时就开始提速**——这是有意的，对照方法见[传感器校准记录](docs/thermal-sensor-calibration-20260924.md)。

## 更新

```bash
cd smart-fan
git pull --ff-only
./scripts/setup.sh reinstall
```

应用、后台服务与 `/Applications` 里的副本会一起更新，用户数据保留。应用内的「检查更新」只提示新版本，不会自动替换程序。

## 卸载

```bash
./scripts/setup.sh uninstall      # 移除应用与后台服务，保留用户数据
./scripts/setup.sh uninstall -f   # 连同模式、校准、日志一起删除
```

只把 App 拖进废纸篓**不会**卸载后台服务，应用下次运行时会提示修复。

## 日志与数据

| 数据 | 位置 | 保留 |
| --- | --- | --- |
| 应用日志 | `~/Library/Logs/SmartFan/` | 最多 7 天，单文件 5 MiB，目录内合计 50 MiB |
| 后台服务日志 | `/var/root/Library/Logs/SmartFan/` | 同上，独立计算 |
| CSV 采样 | `~/Library/Application Support/SmartFan/logs/` | 单次最多 100 MiB，正常结束后保留 24 小时 |
| 模式与校准数据 | `~/Library/Application Support/SmartFan/` | 不自动清理（`uninstall -f` 才删） |

后台服务日志属于 root，查看需要管理员权限：

```bash
sudo tail -n 50 "/var/root/Library/Logs/SmartFan/smart-fan-$(date +%F).log"
```

`scripts/setup.sh logs` 可以看应用日志（`--daemon` 看后台服务日志）。

## 常见问题

### 提示后台服务不可用，或版本不一致

应用与后台服务必须来自同一版本。重新运行一次安装即可，应用会同步它们：

```bash
./scripts/setup.sh reinstall
```

若仍失败，运行 `./scripts/setup.sh doctor` 并把输出（含今天的错误）附在 issue 里。

### 打开时提示无法验证开发者

当前构建未经 Apple 公证。确认文件来自本仓库后，按 [Apple 官方说明](https://support.apple.com/zh-cn/102445) 在“系统设置 → 隐私与安全性”里选择“仍要打开”。

### 温度或风扇读数和其他工具不一样

先看[读数与传感器](#读数与传感器)一节：本应用与其它工具常常只是取了不同的传感器。提交问题时请附上机型、macOS 版本、SmartFan 版本和「传感器」页的截图。

### 风扇一直在转 / 高温防护反复介入

打开「首选项 → 风扇」看**防护阶段**那一行是不是在介入，并在「传感器」页核对 `Tp`/`TC` 这些热点键的读数。也可以在 issue 里附上 `scripts/setup.sh logs | tail -100`（日志里会记录每次介入与解除的温度）。

## 开发与贡献

### 项目结构

| 路径 | 内容 |
| --- | --- |
| [`Sources/SmartFanApp/`](Sources/SmartFanApp/) | 菜单栏应用、首选项界面、界面状态 |
| [`Sources/SmartFanCore/`](Sources/SmartFanCore/) | SMC 访问、风扇控制、后台通信、模式、日志 |
| [`Sources/SmartFanLocalization/`](Sources/SmartFanLocalization/) | 语言选择与翻译资源 |
| [`Sources/SmartFanCLI/`](Sources/SmartFanCLI/) | 命令行与安装/卸载入口（随应用分发，不暴露给用户） |
| [`Tests/SmartFanTests/`](Tests/SmartFanTests/) | 自动化测试 |
| [`scripts/setup.sh`](scripts/setup.sh) | 开发与维护的唯一入口 |
| [`assets/logo/`](assets/logo/) | 图标与品牌资源（macOS/iOS 图标集、网站图标、矢量 logo） |
| [`docs/`](docs/) | 设计计划、验证记录与[待办索引](docs/todo.md) |

### 常用命令

```bash
scripts/setup.sh build            # 编译
scripts/setup.sh run              # 直接运行，不动系统
scripts/setup.sh test             # 单元测试 + 断连回归 + 打包资源校验
scripts/setup.sh check            # build + test（提交前跑这个）
scripts/setup.sh doctor           # 环境与安装状态自检
scripts/setup.sh logs             # 查看日志（--daemon 看后台服务）
scripts/setup.sh install          # 编译、组装、安装、打开
scripts/setup.sh reinstall        # 强制覆盖安装
scripts/setup.sh uninstall [-f]   # 卸载（-f 连数据一起删）
scripts/setup.sh package          # 生成本地发行包到 dist/
scripts/setup.sh cli <参数…>      # 用构建好的命令行工具，例如 cli status
```

`scripts/setup.sh help` 列出全部命令。

### 提交前

```bash
scripts/setup.sh check
```

它会编译并运行全部测试。涉及温控、后台通信或菜单栏行为的改动，请另外说明本机验证结果，并把自动化测试、离屏渲染测试和真机结果分开写。

### 文档

- [待办事项](docs/todo.md)：未完成、待决策、待清理事项的统一索引，开发前先看这个。
- [更新记录](CHANGELOG.md)：各版本的主要变化。
- [相对上游的改动](docs/upstream-divergence.md)：合并上游时需要重新施加的差异。
- [传感器校准记录](docs/thermal-sensor-calibration-20260924.md)：传感器键的语义与实测对照。
- [服务自管理计划](docs/daemon-self-management-plan.md)、[菜单栏显示计划](docs/menu-bar-display-plan.md)、[高温防护计划](docs/high-temp-protection-plan.md)、[传感器列表计划](docs/sensor-list-plan.md)：各项功能的由来与取舍。

## 参与贡献

- **问题反馈**：[Issues](https://github.com/witt-bit/smart-fan/issues)。请附机型、macOS 版本、SmartFan 版本与复现步骤；涉及读数时附「传感器」页截图，涉及风扇行为时附日志片段。
- **代码**：按[开发与贡献](#开发与贡献)构建并验证，再提交 [Pull Request](https://github.com/witt-bit/smart-fan/pulls)。
- **翻译**：改进英文或简体中文文案；繁体中文由脚本从简体生成，流程见 [GUI 本地化](docs/gui-localization.md)。

### 贡献者

<a href="https://github.com/witt-bit/smart-fan/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=witt-bit/smart-fan" alt="SmartFan 贡献者">
</a>

## 来源与许可

SmartFan 基于 [ThermalForge](https://github.com/ProducerGuy/ThermalForge)，经由 [MacFanPro](https://github.com/macfanpro/macfanpro) 重命名与扩展而来，现由 [@witt](https://github.com/witt-bit) 维护，遵循 [MIT License](LICENSE)。

上游的版权与许可完整保留：衍生关系与第三方依赖见 [NOTICE.md](NOTICE.md) 和 [ThirdPartyNotices/](ThirdPartyNotices/)；相对上游的代码差异见[相对上游的改动](docs/upstream-divergence.md)。
