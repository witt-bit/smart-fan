# 菜单栏显示与首选项 —— 开发计划

把 SmartFan 的菜单栏从「固定图标 + 峰值温度」改为**用户可自定义**的显示，并新增**首选项主窗口**。
本文是任务清单，按 `MB-x.y` 逐个开发；每个任务列出目标、改动文件与验收标准（DoD）。

- 状态：**计划中**
- 目标版本：**`1.0.0`**（与项目改名一起发布）
- 文档产出：功能完成后**追加 `CHANGELOG.md`**（英文）条目，并新增 `docs/menu-bar-display-validation.md`（沿用现有验证文档格式）
- 相关文档：[menu-bar-label-validation.md](menu-bar-label-validation.md)、[project-architecture.md](project-architecture.md)

---

## 1. 背景与目标

现状：菜单栏只有固定的一段 `NSImage`（状态图标 + CPU/GPU 峰值温度），所有设置散在下拉菜单底部。

目标：

1. 菜单栏内容可自定义：图标+数字、温度曲线、转速曲线、双曲线叠加。
2. 新增温度度量：**均温**（所有传感器平均）与**体感温度**（暂取电池温度）。
3. 曲线可配置采样频率与窗口长度。
4. 新增**首选项主窗口**承载全部配置；菜单栏**右键只切换 Profile**。

## 2. 现状与约束（已核实）

| 事实 | 影响 |
|---|---|
| 电池传感器键被 `SMCSensorFilter` 剔除（`batteryKeys`，来自 IOHID product 含 "battery"） | 「体感温度」需要新增电池读取路径，绕过该过滤 |
| 本机 `Mac16,1` / Apple M4，**1 个风扇**；`TB0T=31.0°C`、`TB1T=30.2`、`TB2T=31.0`（后两个未在 `thermalKeys` 内） | 多风扇规则需要定义；电池键需补读 |
| 当前用 `MenuBarExtra(.window)`，**无法区分左右键** | 「右键切 Profile」必须换成自定义 `NSStatusItem` |
| `AppState` 不保存历史 | 曲线需要新增滚动缓冲 |
| `MenuBarLabelImage` 用单张 `NSImage` 手绘（规避 `MenuBarExtra` 的测量 bug） | 数字/曲线排版继续走手绘 `NSImage` 路线 |
| 本机工具链为 CommandLineTools，**缺少 `libSwiftUIMacros.dylib`** | **`@State` / `@AppStorage` 等 SwiftUI 宏无法编译**；代码需避开 SwiftUI 宏（用 `ObservableObject` + `@StateObject` 替代）。CI 的 Xcode 无此限制。 |

> 注意：换用 `NSStatusItem` 会推翻 `docs/menu-bar-label-validation.md` 中「不引入自定义 NSStatusItem」的旧决定，该文档需在 MB-1.6 更新说明。

## 3. 度量定义

| 度量 | 定义 |
|---|---|
| 均温 `averageTemp` | `ThermalStatus.temperatures` 中**所有值**的算术平均（**包含**电池传感器，见 Q4） |
| 体感温度 `batteryTemp` | 电池温度（先取 `TB0T`；缺失时回退 `TB1T`/`TB2T`） |
| 转速 `fanRPM` | `ThermalStatus.fans[].actualRPM` 的多风扇**平均**（仅统计**读取成功**的风扇；单扇即该扇）——见 Q1 |
| 峰值温度 `safetyPeakTemp` | 现有实现，保留（安全兜底用，不受本次影响） |

## 4. 显示样式规格

`MenuBarStyle` 四选一：

| 样式 | 布局 |
|---|---|
| `numbers` 图标+数字 | 图标在左；温度在图标**右上**、转速在**右下**（两行）；只选一个数字时单独显示在图标**右侧**（垂直居中）；**两个都关则只显示图标**；单位显示可配置 |
| `temperatureCurve` 温度曲线 | 一个小曲线窗，仅温度 |
| `rpmCurve` 转速曲线 | 一个小曲线窗，仅转速 |
| `dualCurve` 双曲线 | **上下分带**：温度占上半、转速占下半，各自独立归一化（不叠加） |

**曲线设置**

- 采样频率：`1 / 2 / 3 / 5 / 10` 秒（默认 **1 秒**）
- 窗口长度：`10 / 30 / 60` 秒、`3` 分钟（默认 **60 秒**）
- 单位显示粒度（`UnitDisplay`）：

| 档位 | 温度 | 转速 |
|---|---|---|
| `none` | `48` | `2318` |
| `compact`（默认） | `48°` | `2318` |
| `full` | `48°C` | `2318 RPM` |

温度数值按**整数**显示（`48.2°C → 48°`）。

**曲线样式不显示图标**，只有一个曲线小窗。

### 渲染视觉规格（定稿）

排版继续用**单张手绘 `NSImage`**；尺寸/字号**按运行环境自动计算，不硬编码**（避免不同机器/辅助功能设置下不兼容）。

**环境来源**
- 菜单栏高度：`NSStatusBar.system.thickness`
- 菜单栏字体：`NSFont.menuBarFont(ofSize: 0)`

#### V1 数字样式

| 项 | 规则 |
|---|---|
| 图标 | 菜单栏字体大小，regular，**模板图**（自动适配明暗） |
| 单数字字号 | = 菜单栏字体大小 |
| **双数字字号** | **自动计算**：由状态栏可用高度反推每行高度，取能放下的最大字号；上限 = 菜单栏字体，下限 = 可读下限；若总宽超上限再 shrink-to-fit |
| 双数字布局 | 温度在上、转速在下，**左对齐**，行距 0 |
| 图标↔文字间距 | 3pt |

#### V2 曲线画布

| 项 | 规则 |
|---|---|
| 高度 | **占满菜单栏**（= 状态栏高度 − 小内边距） |
| 宽度 | 适当宽度（默认约 40pt，受 V4 上限约束） |
| 线宽 | 1.5pt，圆角连接 |
| 背景/边框 | 无 |
| **纵坐标参考** | 画淡色**四分之一线**（25/50/75%）：22pt 内放不下轴标签，但归一化曲线需要一个可读参考 |
| 数据不足（0/1 点） | 画水平中线占位 |

#### V3 双曲线

| 项 | 规则 |
|---|---|
| 温度 | `systemOrange`，占**上半带** |
| 转速 | `systemTeal`，占**下半带** |
| 归一化 | 各按窗口内 min/max 独立归一化（在各自带内） |
| **为何分带而非叠加** | 两者量纲不同，共用刻度无意义；且实际数据强相关（温度升→转速升），独立归一化后两条线几乎重合，后画的一条会**完全盖住**另一条（已由像素测试证实 `orange pixels: 0`） |
| 明暗 | **彩色非模板**（模板图只能黑白，无法区分两条线） |

#### V4 宽度上限（防止挤动相邻图标）

| 样式 | 上限 | 超出策略 |
|---|---|---|
| 图标+数字 | 72pt | 先压缩间距，再省略单位（`compact`→`none`），不裁字 |
| 曲线 | 44pt | 压缩画布宽度 |

#### V5 明暗适配

| 元素 | 方式 |
|---|---|
| 图标 + 数字 | **模板图**（AppKit 自动黑/白切换） |
| 曲线 | **彩色**（明暗菜单栏下都可见） |
| 异常态图标 | 出现告警时**临时切换为红色风扇图标**（不使用角标圆点） |

## 5. 配置数据模型（**已冻结**）

```swift
public enum MenuBarStyle: String, Codable, CaseIterable {
    case numbers, temperatureCurve, rpmCurve, dualCurve
}
public enum TemperatureMetric: String, Codable, CaseIterable {
    case average    // 均温（所有传感器平均，含电池）
    case feelsLike  // 体感（电池）
}
public enum UnitDisplay: String, Codable, CaseIterable {
    case none, compact, full
}
public struct MenuBarDisplayConfig: Codable, Equatable {
    var style: MenuBarStyle = .numbers
    var showTemperature = true     // numbers 样式下
    var showRPM = false            // numbers 样式下
    var temperatureMetric: TemperatureMetric = .average
    var unitDisplay: UnitDisplay = .compact
    var sampleInterval: TimeInterval = 1
    var window: TimeInterval = 60
}
```

- 持久化：JSON 编码进 `UserDefaults`（键 `menuBarDisplay`），坏数据回退默认。
- 温度度量对**数字与温度曲线共用**（Q3）。

## 6. 架构

```
AppDelegate
 ├─ NSStatusItem（自定义按钮，左/右键分流）
 │   ├─ 左键 → 打开首选项窗口
 │   └─ 右键 → Profile NSMenu（Silent/Balanced/Performance/Max/Smart/Default）
 ├─ PreferencesWindow（NSWindow + NSHostingController<PreferencesView>）
 └─ AppState（@MainActor，ObservableObject）
      ├─ latestStatus: ThermalStatus
      ├─ displayConfig: MenuBarDisplayConfig
      └─ history: 环形缓冲（avgTemp, batteryTemp, rpm, t）
```

标签渲染：`MenuBarLabelImage` 扩展为分段合成（数字两行 / 单数字 / 曲线画布），仍产出单张 `NSImage`。

---

## 7. 数据与存储

### 配置项
- 存储：`UserDefaults.standard`（域 `org.witt.smartfan.app`，文件 `~/Library/Preferences/org.witt.smartfan.app.plist`）
- 新增键：**`menuBarDisplay`**（`MenuBarDisplayConfig` 的 JSON）
- 新增键：**`fixedRPM`**（Int）：固定速率模式的目标 RPM，随 `selectedProfile` 一起持久化，重启后恢复
- 现有键不变：`useFahrenheit`、`guiLanguage`、`selectedProfile`（现有值增加 `"fixed"`）、`update*`
- 开机启动不在 UserDefaults，由 `SMAppService` 系统级注册

### 曲线历史
- **内存滚动缓冲，不落盘**（3 分钟 × 1 样本/秒 ≈ 180 点，几 KB）
- 重启后从零积累；无磁盘 I/O、无隐私残留

| 边界 | 处理 |
|---|---|
| 睡眠/唤醒 | 按时间戳存点；唤醒后若空洞 > 当前窗口，**丢弃旧点重新积累**（不补假数据） |
| 改窗口长度 | 立即按新窗口截断；变大时留空等新点填满 |
| App 重启 | 清空，从零开始 |

### 全项目数据位置（现状，供参考）

| 数据 | 位置 | 生命周期 |
|---|---|---|
| 配置 | `~/Library/Preferences/org.witt.smartfan.app.plist` | 永久 |
| 自定义模式 | `~/Library/Application Support/SmartFan/profiles/*.json` | 永久 |
| 校准数据 | `~/Library/Application Support/SmartFan/calibration.json` | 永久 |
| 临时 CSV 采样 | `~/Library/Application Support/SmartFan/logs/<session>/` | 默认完成后 24h 过期 |
| 应用运行日志 | `~/Library/Logs/SmartFan/smart-fan-YYYY-MM-DD.log` | 7 天 / 5MiB 单文件 / 50MiB 目录 |
| 后台服务运行日志 | `/var/root/Library/Logs/SmartFan/` | 同上，独立计算 |
| 后台服务风扇状态 | 守护进程内存（`hold: HoldState`） | 不持久化 |

---

## 8. 首选项窗口布局（定稿）

`NSWindow` + `NSHostingController`。**左侧竖排标签**，右侧内容区。标签顺序：**风扇 → 通用 → 菜单栏 → 关于**。

```
╭─ SmartFan 首选项 ───────────────────────────────────────────────╮
│ ┌──────────┐ ┌────────────────────────────────────────────────┐ │
│ │ 风扇     │ │                                                 │ │
│ │ 通用     │ │   （当前页内容）                                │ │
│ │ 菜单栏   │ │                                                 │ │
│ │ 关于     │ │                                                 │ │
│ └──────────┘ └────────────────────────────────────────────────┘ │
╰─────────────────────────────────────────────────────────────────╯
```

### 风扇页
- **告警条**（**仅本页**，条件显示）：**后台服务不可用**（沿用现有文案 + 横幅）
- 当前模式：`( Smart ▾ )` + `[ Smart ]` `[ Default ]`（可直接切模式）
- **固定速率**（新增，**模式之一**）：与均衡/性能/静音**平级的普通模式**；选中后用**滑块**在 `[minRPM, maxRPM]` 设定并固定风扇转速（原 CLI `set` 的图形化替代）；选择与 RPM **会记住**（`selectedProfile="fixed"` + `fixedRPM`），并出现在右键菜单
- **不提供自定义 Profile**（仅预置模式）
- 实时读数：各风扇 RPM、CPU/GPU/RAM/SSD/环境/均温/体感
- ~~终端占用告警~~：**后期删除**，其能力并入上面的「固定速率」

### 通用页
- 语言、°F/°C、开机启动

### 菜单栏页
- 显示样式：图标+数字 / 温度曲线 / 转速曲线 / 双曲线叠加
- **预览**：实时预览当前设置下的菜单栏外观
- 数字选项（样式=图标+数字 时可用）：显示温度/转速、温度度量、单位
- 曲线选项（样式=曲线 时可用）：曲线内容、采样频率、时间窗口
- **刷新节奏**：曲线样式用**曲线的采样间隔**；其他样式 **1s**

### 关于页
- 版本
- **需要更新**（后台服务版本 ≠ App）：含原因说明与 `sudo smart-fan install`
- **有可用更新**：`brew upgrade smart-fan && sudo smart-fan install` + `[稍后]`
- 检查更新
- 链接（项目主页 · 许可证 · 第三方声明）

**菜单栏右键菜单**：`首选项…` / `Profile`（子菜单）/ `退出`。
首选项窗口**不**再放退出入口。

---

## 9. 任务清单

### 阶段 P0 —— 规格冻结

- [x] **MB-0.1 确认开放问题**（见 §8）
  - 结论：Q1–Q4 已定（§9）；Q5 单位三档、Q6 默认值、Q7 曲线不显图标 已定。
- [x] **MB-0.2 冻结 `MenuBarDisplayConfig` 字段**
  - 结论：见 §5（已冻结）。

### 阶段 P1 —— 状态栏项 + 首选项窗口骨架

- [x] **MB-1.1 自定义 `NSStatusItem` 替换 `MenuBarExtra`**
  - 文件：`Sources/SmartFanApp/SmartFanApp.swift`、新增 `Sources/SmartFanApp/StatusItemController.swift`
  - 要点：**左键 → 打开首选项窗口；右键 → 菜单（`首选项…` / `Profile` 子菜单 / `退出`）**。`button.sendAction(on: [.leftMouseUp, .rightMouseUp])` + 按 `NSApp.currentEvent?.type` 分流；保留 `.accessory` 激活策略、单实例检查、退出时按 owner 复位风扇的现有逻辑。
  - 完成：`@main` 改为 AppKit `AppDelegate`；新增 `StatusItemController`（图像渲染 + 左右键分流 + `showMenu` 临时挂菜单再复原左键）；右键菜单含首选项/Profile（全部模式带勾选）/退出。
  - DoD：✅ 图标正常；左右键分别触发；无 Dock 图标；单实例仍生效。
- [x] **MB-1.2 首选项窗口（布局见 §7）**
  - 文件：新增 `Sources/SmartFanApp/PreferencesWindowController.swift`、`Sources/SmartFanApp/PreferencesView.swift`
  - 完成：`NSWindow` + `NSHostingController`；左侧竖排标签（风扇/通用/菜单栏/关于）+ 右侧内容区；关闭即隐藏。
  - 注：风扇/通用/关于页已放基础内容（保活可用），完整迁移见 MB-1.3；菜单栏页待 MB-2.4/3.3。
  - DoD：✅ 标签切换正常；窗口尺寸固定 640×460；可反复开关。
- [x] **MB-1.3 迁移现有功能到首选项**
  - 风扇页：告警条（仅「后台服务不可用」，条件显示）+ 模式切换（全部模式）+ 实时读数（风扇/CPU/GPU/RAM/SSD/环境/均温/体感）
  - 通用页：语言、°F/°C、开机启动
  - 关于页：**需要更新** + **有可用更新** + 版本 + 检查更新 + 链接
  - 文件：新增 `Banners.swift`（三个横幅从 `MenuBarView` 抽出共用）、`PreferencesView.swift`、`AppState.checkForUpdatesNow()`
  - DoD：✅ 原下拉功能在首选项可用；告警仅风扇页（不可用）与关于页（更新）出现。
- [x] **MB-1.4 右键菜单：首选项 / Profile / 退出**
  - 要点：`NSMenu`；`Profile` 子菜单复用 `AppState.selectProfile/resetAuto/setSmart`，勾选态跟随 `activeProfile`，含 `Default`；`退出` 调 `NSApp.terminate`。
  - 完成：随 MB-1.1 一并实现（`AppDelegate.showContextMenu` / `profileMenu`）。
  - DoD：✅ 右键三项均可用；Profile 勾选态与首选项一致。
- [x] **MB-1.5 移除原下拉菜单**
  - 完成：删除 `Sources/SmartFanApp/MenuBarView.swift`（含 `ExternalHoldBanner` / `SectionHeader` / `TemperatureRow`）；四个首选项页改为 internal，`LocalizedPanelTests` 改为渲染**首选项四页**（三语言 × 告警态）。
  - DoD：✅ 源码中仅剩解释性注释提及 `MenuBarExtra`；`swift build` 通过；测试全绿。
- [x] **MB-1.6 更新架构文档**
  - 文件：`docs/menu-bar-label-validation.md`、`docs/project-architecture.md`
  - 完成：`menu-bar-label-validation.md` 顶部加**部分废弃说明**（`MenuBarExtra` → 自定义 `NSStatusItem`，测量的最小宽度/像素方法仍有效）；`project-architecture.md` 更新模块表与分层图，新增「菜单栏应用结构（1.0.0 起）」文件表。
  - DoD：✅ 两文档均说明取代原因与影响。
- [x] **MB-1.7 首选项风扇页：固定速率模式**（新增需求）
  - 完成：新增 `FanProfile.fixed`（`handsOff`，像 Smart 一样**不进 `builtIn`**，以免影响 CLI `watch` 与既有测试）；新增 `FanProfile.uiProfiles` 统一菜单/选择器顺序。
  - 风扇页选中「固定速率」时显示**滑块**（范围 = 风扇上报的 `[minRPM, maxRPM]`，步进 100）；右键菜单也可切换。
  - 持久化：`selectedProfile="fixed"` + `fixedRPM`（重启恢复）；启动时经 `selectProfile` 同一路径重建 hold。
  - **不做自定义 Profile**（均为预置模式）。
  - DoD：✅ 滑块设值后风扇固定；切走/Default 解除；重启后模式与 RPM 恢复（单测覆盖 `selectable("fixed")` / `uiProfiles` 顺序）。

### 阶段 P2 —— 图标+数字样式与度量

- [x] **MB-2.1 核心度量**
  - 文件：`Sources/SmartFanCore/FanControl.swift`
  - 完成：`readTemp` 拆出无电池过滤的 `readRawTemp`；新增 `readBatteryTemp()`（`TB0T/TB1T/TB2T` + IOHID 电池键）；`readFanFloat` 改为 `Float?`，`status()` 单独记录**成功读取**的 `F{i}Ac` 求平均；`ThermalStatus` 新增 `averageTemp` / `batteryTemp` / `fanRPM`（均含 `nil` 语义）。
  - DoD：✅ 本机 `status` 输出 `average_temp`/`battery_temp`/`fan_rpm`；缺失时返回 null 而非 0。
- [x] **MB-2.2 `MenuBarDisplayConfig` + 持久化**
  - 文件：新增 `Sources/SmartFanCore/MenuBarDisplay.swift`、`Tests/SmartFanTests/MenuBarDisplayConfigTests.swift`、`AppState.displayConfig`
  - 完成：模型 + `normalized()`（非法间隔/窗口回退）+ UserDefaults JSON 存取（键 `menuBarDisplay`）+ 5 项单测。
  - DoD：✅ 编解码、缺省/损坏回退、越界钳位均通过。
- [x] **MB-2.3 数字排版渲染**
  - 文件：`Sources/SmartFanApp/MenuBarLabel.swift`（新增两行渲染）、新增 `Sources/SmartFanApp/MenuBarContent.swift`（格式化）、`StatusItemController`
  - 完成：两行（温度上、转速下，左对齐）字体由**状态栏高度自动计算**（非固定 10pt）；单数字仍走原一行布局；`maximumWidth = 72` 先压间距；`readRawTemp` 无关系。单位三档在 `MenuBarContent` 实现。
  - DoD：✅ 四种组合 + 三档单位渲染正确；新增 6 项单测（含宽度上限、字体自适应）。
- [x] **MB-2.4 首选项 UI：样式与度量**
  - 完成：样式分段选择、显示温度/转速开关、温度度量（均温/体感）、单位三档、采样频率、时间窗口；右上实时**预览**（渲染真实状态栏图，不会与菜单栏脱节）。
  - 注：`@Binding` 经 `$appState.displayConfig` 动态成员子路径写入，改动即时保存并重绘。
  - DoD：✅ 改动实时反映到菜单栏。
- [x] **MB-2.5 异常态红色风扇图标**（新增）
  - 完成：任一告警（后台服务版本不一致 / 不可用）时，图标整体染 `systemRed`（非模板，按明暗重绘）；**移除橙色圆点**。用 SF Symbol 染色实现，**无需新增图片资源**（后续可换成专用红色图标）。
  - 文件：`Sources/SmartFanApp/MenuBarLabel.swift`（单行 + 两行路径）、`Tests/SmartFanApp/MenuBarLabelTests.swift`（断言改为红色）
  - DoD：✅ 告警出现/消失时切换；无告警恢复普通图标；像素测试通过。

### 阶段 P3 —— 曲线

- [x] **MB-3.1 历史缓冲**
  - 文件：新增 `Sources/SmartFanCore/MenuBarHistory.swift`、`AppState.menuBarHistory` + `recordMenuBarSample`、`Tests/SmartFanTests/MenuBarHistoryTests.swift`
  - 完成：采样 `(t, 温度度量值, fanRPM)`；强制采样间隔（过密丢弃）；超窗裁剪 + `maxWindow=180s` 上限；**内存滚动缓冲，不落盘**。
  - 边界：睡眠/唤醒空洞 > 窗口则丢弃旧点；窗口变小立即截断，变大保留待填；仅在曲线样式下采样。
  - DoD：✅ 7 项单测覆盖（间隔、裁剪、唤醒空洞、缩小/放大、上限、非法输入、reset）。
- [x] **MB-3.2 曲线渲染**
  - 文件：`Sources/SmartFanApp/MenuBarLabel.swift`（`makeCurve` + `curveWidth`）、`MenuBarContent.curves/image`、`StatusItemController`、`MenuBarPreview`
  - 完成：画布宽 40pt、高**占满菜单栏**；颜色 温度 `systemOrange` / 转速 `systemTeal`；**各自独立 min/max 归一化**（可叠加）；空/单点画中线；告警时整条曲线变红（对应图标变红）。彩色非模板。
  - 注：状态栏与首选项预览共用 `MenuBarContent.image(...)`，不会脱节。
  - DoD：✅ 三种曲线样式 + 空/单点/多点 + 告警态均渲染（单测覆盖）。
- [x] **MB-3.3 曲线设置 UI**
  - 完成：样式分段选择（图标+数字 / 温度曲线 / 转速曲线 / 双曲线叠加）= 曲线选择；采样频率（1/2/3/5/10s）与时间窗口（10/30/60s/3min）**仅曲线样式下显示**（MB-2.4 已随修复落地）；右上实时预览同步。
  - DoD：✅ 改动实时反映；极端组合（10s×3min、1s×10s 等）由 `MenuBarHistoryTests.extremeCombinations` 覆盖。

### 阶段 P4 —— 收尾

- [x] **MB-4.1 本地化**
  - 完成：脚本比对代码中所有 `language.text("…")` 字面量与目录键——**无缺失（无英文泄漏）**；删除下拉菜单下线后遗留的 11 个死键（FANS/PROFILES/TEMPERATURES/外部占用横幅等），新增 `Status`。
  - 现为 **70 键 × 三语言**；繁体由 `scripts/update-traditional.swift` 生成（测试校验等于简→繁转换）。
  - DoD：✅ 三语言键齐全；`LocalizationTests` 全过；打包校验通过。
- [x] **MB-4.2 测试补全**
  - 完成：将 Fixed Rate 的**夹取与滑块范围**抽为 `FanProfile.clampFixedRPM` / `fixedRPMRange`（纯函数），新增 `FixedRateTests`；新增 `MenuBarStyle.usesCurve` 测。
  - 发现并修掉一个**名字遮蔽 bug**：在 `FanProfile` 内裸写 `max(...)` 会解析到 `FanProfile.max`（Max 模式），已改用 `Swift.max/Swift.min`。
  - 覆盖：配置（含归一化/退化）、历史缓冲（含极值组合）、度量消费与缺失降级、数字排版与字体自适应、曲线渲染（空/单点/多点/告警）、固定速率范围。
  - DoD：✅ **142 项测试，Debug 与 Release 均全绿**；断连客户端与打包校验通过。
- [x] **MB-4.3 文档**
  - 完成：README 重写「功能与界面」与「使用」——新增「菜单栏与首选项」（左右键、四种样式、可配置项）、模式表加入固定速率；CHANGELOG 的 1.0.0 条目补齐菜单栏特性；新增 `docs/menu-bar-display-validation.md`（含**未验证项与残余风险**）并从 README 链接。
  - DoD：✅ 使用说明与验收记录齐全。
- [x] **MB-4.4 多机型/电池健壮性**
  - 完成：度量缺失一律返回 `nil`（**不为 0**）——无电池传感器机型体感温度为 `nil`；无风扇读数时转速为 `nil`；无传感器时均温为 `nil`。首选项读数显示 `—`，菜单栏数字直接省去（仅存图标）。
  - 固定速率：硬件未上报 `maxRPM` 时不再钳到 0（会变成停转），改为原值透传（由守护进程纠底），滑块回退到 `1000...7000`。
  - DoD：✅ 单测覆盖（空度量、nil 状态、无电池、仅平均可用）。

### 阶段 P5 —— 配置项 iCloud 自动同步（收费，**后续版本**）

见 §13。本阶段**不在本次范围**。

### 阶段 P6 —— 低优先级增强（末尾）

- [ ] **MB-6.1 菜单栏风扇图标随转速旋转**（低优先级）
  - 要点：在 `NSStatusItem.button` 上挂一个 `CALayer`，用 `CABasicAnimation(transform.rotation.z)` 无限旋转；动画在 render server（GPU）执行，**App 自身 CPU ≈ 0**。
  - **不要**用定时器换 `button.image`（每帧走 AppKit 绘制，与「极其轻量」冲突）。
  - RPM→速度**必须压缩**：真实 6000 RPM = 100 转/秒（肉眼只是频闪）；建议 `rps = 0.2 + 1.3 × (rpm / maxRPM)`（满转 ≈1.5 转/秒）或对数映射。
  - `rpm == 0`（或 < minRPM）时**不加动画**，保持静止。
  - 失去模板染色：`CALayer.contents` 不随菜单栏明暗反色 → 预渲染黑/白（警告时红）两份，复用现有 `effectiveAppearance` KVO 替换 `contents`。
  - 需要把 icon 从「icon + 文字合成图」中**拆出**：按钮上放自定义 `NSView`（`hitTest` 返回 nil 让点击穿透），自绘「旋转图层 + 文字图层」，不再用 `button.image`。
  - **默认关闭**（首选项开关）；开启时菜单栏持续重组，需连同发布前性能专项（§11）一起测。
  - 依赖：MB-2.1（`fanRPM`）、MB-2.3（渲染拆分）。
  - DoD：转速变化时旋转速度跟随；0 转速静止；明暗/警告态颜色正确；关闭时无额外开销。

---

## 10. 已决问题汇总（Q1–Q11，均已定）

| 编号 | 问题 | 结论 |
|---|---|---|
| ~~Q1~~ | 多风扇转速取值 | **已定**：所有风扇**平均**，仅统计读取成功的风扇（详见 §3、MB-2.1）。首选项可切 最大 / fan0。 |
| ~~Q2~~ | 首选项打开方式 / 下拉菜单去留 | **已定**：左键 → 首选项窗口；右键 → 菜单（`首选项…` / `Profile` 子菜单 / `退出`）；原下拉菜单**下线**，内容迁入首选项（布局见 §7）。 |
| ~~Q3~~ | 数字样式中「温度」用哪个度量 | **已定**：一个「温度度量」选择器（均温 / 体感温度），默认**均温**，**数字与温度曲线共用**。 |
| ~~Q4~~ | 均温是否包含电池传感器 | **已定**：**包含**（按「所有传感器」字面）。 |
| ~~Q5~~ | 单位显示粒度 | **已定**：三档 `none/compact/full`，默认 `compact`；温度取整。 |
| ~~Q6~~ | 默认值与默认样式 | **已定**：图标+数字 / 温度开 / 转速关 / 均温 / compact / 双曲线叠加 / 1s / 60s。 |
| ~~Q7~~ | 曲线样式是否显示图标 | **已定**：不显示，只有曲线小窗。 |
| ~~Q11~~ | 风扇页「固定速率」如何设计？ | **已定**：作为**普通模式之一**（与均衡/性能/静音平级），选中后用**滑块**在 `[minRPM, maxRPM]` 设定；**不做自定义 Profile**（均预置）。 |
| ~~Q11.5~~ | 固定速率的归属与退出行为 | **已定**：与其它模式相同（App 的 hold + 心跳维持），**选择会被记住**，不是特殊语义。 |
| ~~Q11.6~~ | 是否出现在右键菜单 | **已定**：**所有**模式（含固定速率）都在右键菜单可切换。 |
| ~~Q11.7~~ | 是否记住上次 RPM | **已定**：**存进配置**（`fixedRPM`）。 |

## 11. 性能：实测基线与发布前专项（**本期不实现**）

空转资源占用**不在本期实现范围**，作为 **1.0 首次发布前的专项验证与改进**。先记录本机实测基线，避免丢失。

### 实测基线（本机 Mac16,1 / Apple M4）

| 场景 | CPU（单核 %） | user / sys |
|---|---|---|
| 完整 App 空转（首选项关闭、仅图标） | **3.42%** | 1.37% / 2.05% |
| `smart-fan watch` 监控循环 @ 0.1s（10Hz） | **2.17%** | 0.30% / 1.88% |
| `smart-fan watch` 监控循环 @ 1.0s（1Hz） | **0.23%** | 0.03% / 0.20% |

- 成本 ≈ **正比于轮询频率**；~87% 为**系统时间**（SMC 的 IOKit 调用）。
- 主因：`ThermalMonitor` 固定 **10Hz** 读全部传感器（~44 键 × 2 ioctl），与当前模式无关。
- 其余：进程捕获 `sysctl KERN_PROC_ALL`（0.5Hz）、后台 socket 轮询（0.2Hz）、日志与 UI 重绘。

### 发布前改进方向（待做）

- **自适应轮询**：显示 1Hz / 控制 10Hz；稳态（`target == current`）降到 1Hz。
  - 爬坡量 = `rampUpPerSec × tickInterval`，放慢 tick **不影响每秒爬坡量**，只变粗粒度。
- 进程捕获按需触发（仅在检测到尖峰时）。
- 后台 socket 轮询降频（保留心跳）。
- 目标：空转 **≤ 0.5% of one core**。

> 安全兜底不受影响：95°C 覆盖在 1Hz 下最多迟 1 秒触发，且守护进程另有独立安全扇扫描。

### 上游 Experiment 2 的结论（已并入，见 [idle-cpu-experiments.md](idle-cpu-experiments.md)）

上游把空闲 CPU 拆到了 syscall 级别（macOS 27.0、M4 Max）：

| 模式 | CPU | 说明 |
|---|---|---|
| live（50 key，info+read） | 4.26% | 现行路径 |
| cached（零 SMC 读） | 1.53% | 两者差值 = 传感器扫描成本 |
| floor（仅 36 个安全 key + 缓存 size） | 3.08% | **被否决**的优化 |

- **传感器扫描 ≈ 2.7pp**（占空闲 CPU 的 ~64%），其中 ~77% 为系统时间。
- 每 tick 读 **61 个 key**，每个 key 是 **2 次内核调用**（`readKeyInfo` + `readBytes`）→ **1000+ 次/秒**。
- 上游结论：**不改**——要保两个设计保证：**每次读取都校验**、**每个传感器都覆盖**。

**与我们的方案不冲突**：我们主张的是**降低轮询频率**（不控制时 10Hz → 1Hz），既不减少 key，也不跳过校验；上游否决的「floor」是**减少 key + 放弃校验**。本机实测：`watch` @10Hz = **2.17%**，@1Hz = **0.23%**。

---

## 12. 不在本次范围

- 体感温度的真实算法（当前仅取电池温度）。
- 菜单栏分段**拖动排序**（先做固定顺序 + 显隐）。
- 独立 Settings Scene（用 `NSWindow` + `NSHostingController` 实现）。
- 曲线导出/历史持久化。
- **性能优化（自适应轮询等）**：推迟到 1.0 发布前专项（见 §11）。
- **配置项 iCloud 同步与收费**：后续版本（见 §13）。
- **部分 CLI 能力弃用、改为图形化**（如 `smart-fan set` → 风扇页固定速率滑块）：后续方向。
- **守护进程随 App 自管理**（app 内嵌后端、cask 分发、不再向普通用户提供 CLI）：见 [daemon-self-management-plan.md](daemon-self-management-plan.md)。

---

## 13. 后续版本：配置项 iCloud 自动同步（收费功能）

**目的**：把跨设备同步做成**付费能力**，为长期维护提供收入来源（功能可维护性）。

**范围（待定，见 Q8）**：跨设备同步配置项（`menuBarDisplay`、`useFahrenheit`、`guiLanguage`、`selectedProfile` 等）。

### 前置条件（**当前架构不满足，需先解决**）

| 项 | 现状 | 需要 |
|---|---|---|
| 代码签名 | 临时签名 `codesign -s -`（ad-hoc） | 真实 Team 签名 + provisioning profile |
| 分发渠道 | Homebrew / 源码构建（本地 ad-hoc 签名） | 确定 App Store / Developer ID 公证 / 第三方授权 |
| iCloud 能力 | 无 | iCloud 容器 + `com.apple.developer.ubiquity-kvstore-identifier` 权限 |
| 付费 | 无 | StoreKit 2（仅 App Store）或第三方 license（Lemon Squeezy 等） |

> 关键约束：**iCloud 权限要求真实签名**，当前的 ad-hoc 签名与 Homebrew 源码构建用不了；且 **StoreKit IAP 仅限 App Store 分发**。

### 技术方案（待定）

- **同步**：`NSUbiquitousKeyValueStore`（键值，≤1MB，适合小配置）或 CloudKit（结构化）。
  - 冲突：后写覆盖 + `NSUbiquitousKeyValueStoreDidChangeExternallyNotification`。
  - 隐私：需用户明确开启；当前 App「不向任何地方发送用户信息」的立场要相应更新。
- **付费门槛**：App Store IAP vs 第三方授权 key。
  - 注意：MIT 协议 + 源码可构建 → 付费门槛理论上可被绕过；需决定许可策略（open-core / 换协议）。

### 任务（后续版本）

- [ ] **MB-5.1 决策：分发与付费模式**（App Store IAP / 第三方授权 / 其他）
- [ ] **MB-5.2 签名与权限改造**（Developer 账号、证书、entitlements、公证流程）
- [ ] **MB-5.3 同步层**（`NSUbiquitousKeyValueStore` + 合并策略 + 开关）
- [ ] **MB-5.4 付费门槛**（license/StoreKit 校验 + 未授权时的降级行为）
- [ ] **MB-5.5 首选项 UI**（同步开关、授权状态、隐私说明）
- [ ] **MB-5.6 文档与合规**（隐私政策、许可策略、分发说明）

### 待确认

| 编号 | 问题 |
|---|---|
| Q8 | 同步哪些配置？（仅菜单栏显示相关 / 全部偏好 / 含校准与模式） |
| Q9 | 分发与付费模式？（App Store IAP / 第三方授权 / 其他） |
| Q10 | 未授权用户的降级行为？（本地配置可用、只是不同步） |

---

## 14. 本地化清单（新增字符串）

- key = 英文源文本（`LocalizationCatalog` 约定）；缺翻译时回退英文。
- 繁体由 `scripts/update-traditional.swift` 从简体生成（**不手写**）。
- 实现时需检查与现有键的**碰撞**（如 `None`/`Full`/`Average` 等通用词）。
- 现有键复用不改（FANS / Fan {index} / {rpm} RPM / TEMPERATURES / Ambient / PROFILE / Silent (Apple Default) / Balanced / Performance / Max / Smart / Default / Launch at Login / Quit / Language / Version / °F / °C / CPU / GPU / RAM / SSD / Profile / 各告警文案）。

| key（英文） | 简体中文 |
|---|---|
| Preferences… | 首选项… |
| Fans | 风扇 |
| General | 通用 |
| Menu Bar | 菜单栏 |
| About | 关于 |
| Current Mode | 当前模式 |
| Fixed Rate | 固定速率 |
| Fan speed | 风扇转速 |
| Check for Updates | 检查更新 |
| Menu Bar Style | 菜单栏样式 |
| Icon + Numbers | 图标 + 数字 |
| Temperature Curve | 温度曲线 |
| RPM Curve | 转速曲线 |
| Dual Curve | 双曲线 |
| Preview | 预览 |
| Show Temperature | 显示温度 |
| Show RPM | 显示转速 |
| Temperature Metric | 温度度量 |
| Average | 均温 |
| Feels-like | 体感温度 |
| Units | 单位 |
| None | 无 |
| Compact | 简洁 |
| Full | 完整 |
| Sample Interval | 采样频率 |
| Time Window | 时间窗口 |
| 1 second | 1 秒 |
| 2 seconds | 2 秒 |
| 3 seconds | 3 秒 |
| 5 seconds | 5 秒 |
| 10 seconds | 10 秒 |
| 30 seconds | 30 秒 |
| 60 seconds | 60 秒 |
| 3 minutes | 3 分钟 |
| Homepage | 项目主页 |
| License | 许可证 |
| Third-party notices | 第三方声明 |
| The background service is running an older build than the app. Run "sudo smart-fan install" to re-sync it. | 后台服务运行的版本比 App 旧。运行 “sudo smart-fan install” 重新同步。 |

---

## 15. 测试与验收策略

### 测试分层

| 层 | 内容 | 依赖 |
|---|---|---|
| **纯逻辑** | `MenuBarDisplayConfig` 编解码/默认/坏数据回退；均温（含电池）、体感（电池）、转速（**仅成功读取的扇参与平均**）；曲线缓冲（采样/窗口截断/唤醒空洞丢弃）；数字文本格式化（三档单位、°F/°C、取整） | 无 |
| **像素测试** | 沿用 `MenuBarLabelTests` 的 bitmap 渲染 + 像素检查；数字样式（两行/单数字/三档单位）、曲线（单/双/空数据占位）、异常态红色图标 | 无（不需 SMC） |
| **隔离面板** | `PreferencesView` 各页在 `AppState(startServices: false)` 下渲染 | 无 |
| **手动（不进自动化）** | 真机 SMC/风扇行为、菜单栏外观、右键切换 | 真机 |

### `LocalizedPanelTests` 迁移

现在渲染 `MenuBarView`（下拉菜单）。下拉下线后 → 迁移到 `PreferencesView`（四页各渲染一次）。

### 每任务 DoD 验收步骤（统一模板）

```bash
swift build && swift test
scripts/setup.sh test
bash scripts/setup.sh      # 安装后手动验：菜单栏各样式 / 右键切模式 / 首选项各页
```

结果记入 `docs/`。

> 本机只有 CommandLineTools，`swift test` 需加
> `-Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`（CI 的 macos-15 不需要）。
