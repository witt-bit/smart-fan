# 传感器列表与「控制基准」 —— 设计计划

让**原始传感器**和**应用真正用来计算的数值**都可见，从而让"面板显示 X°C，风扇却在 Y°C 动作"这类疑问**可以自己核对**，而不是只能读源码。

- 状态：**三步全部完成**（`1807e98` / `e3337db` / 本次）
- 起因：排查"均温不对""安全模式反复触发"时发现，应用里有**三层温度**，而只有中间一层是可见的
- 相关：[thermal-sensor-calibration-20260924.md](thermal-sensor-calibration-20260924.md)（键的语义来源）· [high-temp-protection-plan.md](high-temp-protection-plan.md) §5（控制侧仍用原始基）· [upstream-divergence.md](upstream-divergence.md)

---

## 1. 问题：三层温度，只有一层看得见

| 层 | 内容 | 消费者 | 原来是否可见 |
|---|---|---|---|
| **1 原始键** | SMC 发布的 `T*` 键（本机探测 57 个，提供 36 个） | —— | ❌（只有 CLI `discover`） |
| **2 派生读数** | `displayedCPUTemp` / `displayedGPUTemp` / `averageTemp` / `batteryTemp` | 面板各行、菜单栏数字 | ✅ |
| **3 控制基准** | `safetyPeakTemp` = `TC`/`Tp`/`TG`/`Tg` 前缀取**最大** | **Smart 与全部曲线模式**、持续窗口、高温防护阶梯 | ❌ **完全不可见** |

**第 3 层不是第 2 层**：控制基准含"同组里不是核心温度"的键与 SoC 级键，在 Mac16,1 上实测比真实核心高 **3.1–9.6°C（平均 +6.8）**，最大值 12/12 次都来自 `Tp0W`。于是「95°C 保护」实际≈真实核心 **88°C** 介入，而面板上没有任何数字与它对应。

> 这不是"算错"：曲线与阈值的 55/65/85/90/95 都是**照第 3 层标定**的（校准文档明确记录了拒绝改用较冷基准的理由）。问题是**它没有名字、没有位置**。

---

## 2. 设计

### 2.1 传感器页（新标签「传感器」）

列出 `FanControl.thermalKeys` 的**每一个**键（本机 57 个），包含读不到的，做到"能交代清楚每一个键"：

```
传感器                     本机提供 36 / 57 个键

CPU 核心      Tp01   74.1°C   用于 CPU 行 · 参与均温 · 参与控制
              Te05   68.2°C   用于 CPU 行 · 参与均温        ← 能效核：控制不监视（上游如此）
CPU 派生      Tp0W   91.5°C   参与均温 · 参与控制          ← 控制基准取的就是它
              TCMb   83.5°C   参与均温 · 参与控制
GPU           Tg0L   66.4°C   用于 GPU 行 · 参与均温 · 参与控制
内存          TRDX   41.1°C   用于 RAM 行 · 参与均温
SSD           TH0x   36.9°C   用于 SSD 行 · 参与均温
环境          TAOL   25.6°C   用于环境行 · 参与均温
电池          TB0T   29.2°C   用于体感 · 参与均温
被丢弃        TA0P  300.0°C   ✗ 超出 0–150°C 合理范围
未提供        TCDX   —        本机不发布此键
```

要点：
- 本机探测 **57** 个键、提供 **36** 个（Mac16,1 实测）；其余标「本机不发布」
- **不新增 SMC 读取**：原始值来自 `status()` 已经做的那次读取（`ThermalStatus.rawTemperatures` / `sensorDrops`）
- **必须显示"被丢弃/未提供"及原因**：否则用户拿它和 `smart-fan discover` 对照会以为在藏数据（我在排查时就被这个坑过一次）
- 逐芯片诚实：本机有校准表就标"CPU 核心"，没有则标"按前缀分组（未校准）"

### 2.2 风扇页：把"真正使用的量"提到主位

```
状态                Apple 自动
控制基准            91.3°C   ⓘ 曲线与高温防护比较的就是它
                             （比 CPU 行高约 7°C：含派生热点键）
防护阶段            未介入 / 半速 / 满速
─────────────
当前模式  [默认 ▾]
风扇 0              目标 3913 / 实测 2496 RPM
─────────────
参考读数  CPU 84.0 · GPU 60.8 · RAM 41.1 · SSD 36.9 · 环境 25.6 · 均温 65.6 · 体感 29.2
```

---

## 3. 第 1 步（已完成）

`Sources/SmartFanCore/SensorCatalogue.swift` —— 纯逻辑，无 UI，可离线单测：

| 类型 | 作用 |
|---|---|
| `SensorRole.Kind` | `cpuCore` / `cpuPrefix`（无校准表时的前缀分组）/ `cpuDerived` / `gpu` / `memory` / `ssd` / `ambient` / `battery` / `power` / `other` |
| `SensorRole.Use` | `cpu` / `gpu` / `ram` / `ssd` / `ambient` / `feelsLike` / `average` / **`control`** |
| `SensorRole.kind/role(of:coreKeys:)` | 注入校准键表 → 可单测；**不再散落在注释与前缀规则里** |
| `SensorDrop` | `.absent` / `.outOfRange(值)` / `.batteryKey` / `.belowDieFloor` |
| `SensorReading` + `ThermalStatus.sensorReadings()` | 每个被探测的键一行：原始值、是否采用、丢弃原因、角色 |

**顺带的收敛**：
- `FanControl.safetyTempKeys` 现在**由目录派生**（`thermalKeys.filter(SensorRole.isControlBasis)`），并有测试守卫它与"标了 `.control` 的键"完全一致 —— 两个键表再也不会各自漂移
- `SMCSensorFilter` 增加 `rejection(...)` 报告**原因**（`accepts` 变成它的包装），于是"被丢弃"在 UI 里可以解释
- `readRawSensor` 区分 **无此键 / 超范围 / 有值**（`readRawTemp` 保持不变）
- `ThermalStatus` 新增 `rawTemperatures` / `sensorDrops`，并**排除在 JSON 线格式之外**（守护进程状态与 CLI `status` 输出不变）

测试：`SensorCatalogueTests`（12 项）+ `ThermalStatusWireTests`（1 项）。

---

## 4. 第 2、3 步（已完成）

- [x] **第 2 步 传感器页**（`e3337db`）：`PreferencesTab.sensors` + `SensorPreferences` 视图 + 15 条文案。
      `LazyVStack` 渲染，数据取自已有的 `latestStatus`，**不新增轮询**；页首标明"使用校准表 / 按前缀分组"，
      并提供「本机提供 N / 57 个键」的覆盖度。离屏三语言渲染测试已覆盖本页
- [x] **第 3 步 风扇页**（本次）：
  - 新增「**控制基准**」行（右栏位与状态行并列在页首），ⓘ 说明它就是曲线/持续窗口/防护阶梯比较的那个值，
    且**与 CPU 行不是同一个量**
  - 新增「**防护阶段**」行（仅在介入时显示，标出半速/满速）
  - 风扇行改为「**实测 N · 目标 M RPM**」，ⓘ 说明 `F{i}Ac` 与 `F{i}Tg` 的区别（不一致＝写入在途或失败重试）
  - 原读数归到「**参考读数**」标题下，并明说"菜单栏数字属于显示侧，这些都不改变风扇行为"
- [ ] 可选：传感器页「复制全部」按钮（便于报 bug）

## 5. 要守住的六件事

1. **两处文案都要说明**哪个数驱动行为、哪个只是显示，否则同类困惑会以新形式复发
2. **被丢弃/未提供的键必须列出原因**（`discover` 对照陷阱）
3. **逐芯片诚实**：标注"使用校准表"或"按前缀分组（未校准）"
4. **不新增 SMC 轮询**；66 行用惰性渲染
5. **别让风扇页变成调试台**：主位只放状态/控制基准/目标转速/实测转速
6. **本地化**：键名不翻译；分组名、原因、用途等需新增文案

## 6. 副产品

做完第 1 步后，[high-temp-protection-plan.md](high-temp-protection-plan.md) §5 的 **B 方案**（控制侧改用按芯片校准的基）从"大工程"变成"换一个取值函数 + 重新标定阈值" —— 因为**键表已经有了**。
