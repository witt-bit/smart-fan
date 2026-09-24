# 菜单栏显示与首选项 —— 开发计划

把 SmartFan 的菜单栏从「固定图标 + 峰值温度」改为**用户可自定义**的显示，并新增**首选项主窗口**。
本文是任务清单，按 `MB-x.y` 逐个开发；每个任务列出目标、改动文件与验收标准（DoD）。

- 状态：**计划中**
- 目标版本：`1.1.0`（暂定，待功能完成后定）
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

> 注意：换用 `NSStatusItem` 会推翻 `docs/menu-bar-label-validation.md` 中「不引入自定义 NSStatusItem」的旧决定，该文档需在 MB-1.6 更新说明。

## 3. 度量定义

| 度量 | 定义 |
|---|---|
| 均温 `averageTemp` | `ThermalStatus.temperatures` 中**所有值**的算术平均 |
| 体感温度 `batteryTemp` | 电池温度（先取 `TB0T`；缺失时回退 `TB1T`/`TB2T`） |
| 转速 `fanRPM` | `ThermalStatus.fans[].actualRPM` 的取值（多风扇规则见 Q1，默认**平均**） |
| 峰值温度 `safetyPeakTemp` | 现有实现，保留（安全兜底用，不受本次影响） |

## 4. 显示样式规格

`MenuBarStyle` 四选一：

| 样式 | 布局 |
|---|---|
| `numbers` 图标+数字 | 图标在左；温度在图标**右上**、转速在**右下**（两行）；只选一个数字时单独显示在图标**右侧**（垂直居中）；单位显示可配置 |
| `temperatureCurve` 温度曲线 | 一个小曲线窗，仅温度 |
| `rpmCurve` 转速曲线 | 一个小曲线窗，仅转速 |
| `dualCurve` 双曲线叠加 | 两条曲线叠加在同一小窗，各自独立归一化 |

**曲线设置**

- 采样频率：`1 / 2 / 3 / 5 / 10` 秒（默认 **1 秒**）
- 窗口长度：`10 / 30 / 60` 秒、`3` 分钟（默认 **60 秒**）
- 单位显示粒度（`UnitDisplay`）：`none`（`52` / `3210`）、`compact`（`52°` / `3210`）、`full`（`52°C` / `3210 RPM`）

## 5. 配置数据模型（草案）

```swift
public enum MenuBarStyle: String, Codable, CaseIterable {
    case numbers, temperatureCurve, rpmCurve, dualCurve
}
public enum TemperatureMetric: String, Codable, CaseIterable {
    case average    // 均温
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

持久化：JSON 编码进 `UserDefaults`（键 `menuBarDisplay`），坏数据回退默认。

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

## 7. 任务清单

### 阶段 P0 —— 规格冻结

- [ ] **MB-0.1 确认开放问题**（见 §8）
  - DoD：Q1–Q4 全部有结论，回填本文档。
- [ ] **MB-0.2 冻结 `MenuBarDisplayConfig` 字段**
  - DoD：字段名/默认值/持久化键确定。

### 阶段 P1 —— 状态栏项 + 首选项窗口骨架

- [ ] **MB-1.1 自定义 `NSStatusItem` 替换 `MenuBarExtra`**
  - 文件：`Sources/SmartFanApp/SmartFanApp.swift`、新增 `Sources/SmartFanApp/StatusItemController.swift`
  - 要点：`NSStatusBar.system.statusItem`；`button.sendAction(on: [.leftMouseUp, .rightMouseUp])`；按 `NSApp.currentEvent?.type` 分流；保持 `.accessory` 激活策略、单实例检查、退出时按 owner 复位风扇的现有逻辑。
  - DoD：图标正常显示；左右键分别触发不同行为；无 Dock 图标；单实例仍生效。
- [ ] **MB-1.2 首选项窗口**
  - 文件：新增 `Sources/SmartFanApp/PreferencesWindowController.swift`、`Sources/SmartFanApp/PreferencesView.swift`
  - 要点：`NSWindow` + `NSHostingController<PreferencesView>`；`NSApp.activate`；关闭即隐藏（不退出）；可重复打开。
  - DoD：左键打开且可反复开关；窗口尺寸随内容自适应；不产生第二个实例。
- [ ] **MB-1.3 迁移现有设置到首选项**
  - 迁移项：语言、°F/°C、开机启动、版本信息、更新提示、Quit。
  - 文件：`MenuBarView.swift`（拆分/精简）、`PreferencesView.swift`
  - DoD：原下拉菜单中的功能在首选项里全部可用；行为不变。
- [ ] **MB-1.4 右键 Profile 菜单**
  - 要点：复用 `AppState.selectProfile/resetAuto/setSmart`；勾选态跟随 `activeProfile`；含 Default。
  - DoD：右键菜单可切换全部 Profile，状态与首选项/菜单栏图标一致。
- [ ] **MB-1.5 下拉菜单瘦身**
  - 决策：`MenuBarView` 是否保留（如保留则只做 Profile + 打开首选项入口）或整体下线。
  - DoD：与 Q2 结论一致。
- [ ] **MB-1.6 更新架构文档**
  - 文件：`docs/menu-bar-label-validation.md`、`docs/project-architecture.md`
  - DoD：说明 `NSStatusItem` 取代 `MenuBarExtra` 的原因与影响。

### 阶段 P2 —— 图标+数字样式与度量

- [ ] **MB-2.1 核心度量**
  - 文件：`Sources/SmartFanCore/FanControl.swift`、`Sources/SmartFanCore/ThermalStatus+Display.swift`
  - 要点：`ThermalStatus.averageTemp`（所有传感器平均）；`batteryTemp`（新增电池键读取，绕过 `SMCSensorFilter.batteryKeys` 剔除；补读 `TB1T`/`TB2T`）；`fanRPM`（多风扇规则）。
  - DoD：本机 `status` 可解析出均温/体感温度/转速；电池键缺失时安全返回 `nil`。
- [ ] **MB-2.2 `MenuBarDisplayConfig` + 持久化**
  - 文件：新增 `Sources/SmartFanCore/MenuBarDisplay.swift`（模型）+ `AppState` 读写
  - DoD：配置可存取；损坏数据回退默认；单元测试覆盖编解码。
- [ ] **MB-2.3 数字排版渲染**
  - 文件：`Sources/SmartFanApp/MenuBarLabel.swift`
  - 要点：两行（温度右上、转速右下）、单数字（居右居中）、单位粒度。
  - DoD：四种组合（仅温度 / 仅转速 / 两者）+ 三种单位粒度渲染正确；像素测试通过。
- [ ] **MB-2.4 首选项 UI：样式与度量**
  - 要点：样式选择、显示温度/转速开关、温度度量（均温/体感）、单位粒度。
  - DoD：改动实时反映到菜单栏。

### 阶段 P3 —— 曲线

- [ ] **MB-3.1 历史缓冲**
  - 文件：`Sources/SmartFanApp/AppState.swift`
  - 要点：按 `sampleInterval` 采样 `(t, averageTemp, batteryTemp, fanRPM)`；容量 = `window / sampleInterval` 上限保护。
  - DoD：切换频率/窗口后曲线点数正确且无内存增长。
- [ ] **MB-3.2 曲线渲染**
  - 文件：`Sources/SmartFanApp/MenuBarLabel.swift`（曲线画布）/ 新增 `Sparkline.swift`
  - 要点：单曲线按自身 min/max 归一化；双曲线各自归一化叠加（不同色）；空/单点数据安全。
  - DoD：三种曲线样式渲染正确；像素测试通过。
- [ ] **MB-3.3 曲线设置 UI**
  - 要点：采样频率（1/2/3/5/10s）、窗口（10/30/60s/3min）、曲线选择（温度/转速/叠加）。
  - DoD：改动实时反映；极端组合（10s×3min、1s×10s）不崩溃。

### 阶段 P4 —— 收尾

- [ ] **MB-4.1 本地化**
  - 文件：`Sources/SmartFanLocalization/Resources/{en,zh-Hans,zh-Hant}.json`（+ `scripts/update-traditional.swift` 生成繁体）
  - DoD：三语言键齐全；现有本地化测试通过。
- [ ] **MB-4.2 测试补全**
  - 文件：`Tests/SmartFanTests/MenuBarLabelTests.swift` 等
  - DoD：度量、配置、数字排版、曲线渲染均有覆盖；Debug/Release 全绿。
- [ ] **MB-4.3 文档**
  - 文件：`README.md`、`CHANGELOG.md`、新增 `docs/menu-bar-display-validation.md`
  - DoD：使用说明与验收记录齐全。
- [ ] **MB-4.4 多机型/电池健壮性**
  - 要点：无电池机型、无 `TB*` 键、多风扇机型的回退。
  - DoD：缺失度量不显示为 `0`，而是隐藏或显示占位。

---

## 8. 开放问题（默认值待确认）

| 编号 | 问题 | 建议默认 |
|---|---|---|
| Q1 | 多风扇转速取值 | **所有风扇平均**（可切 最大 / fan0） |
| Q2 | 首选项打开方式 / 下拉菜单去留 | **左键 → 首选项**，**右键 → Profile 菜单**；下拉菜单下线 |
| Q3 | 数字样式中「温度」用哪个度量 | 默认**均温**，首选项可切**体感温度**（单选） |
| Q4 | 均温是否包含电池传感器 | 包含（按「所有传感器」字面）；如需排除另议 |

## 9. 不在本次范围

- 体感温度的真实算法（当前仅取电池温度）。
- 菜单栏分段**拖动排序**（先做固定顺序 + 显隐）。
- 独立 Settings Scene（用 `NSWindow` + `NSHostingController` 实现）。
- 曲线导出/历史持久化。
