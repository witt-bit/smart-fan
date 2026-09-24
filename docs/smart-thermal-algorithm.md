# 智能温控（Smart Profile）算法剖析

Smart 是唯一带**硬件标定 + 速率前馈**的配置，其余配置（Silent / Balanced / Performance / Max）都是静态曲线。它分两层：

- **离线一次性标定**（`Sources/SmartFanCore/Calibration.swift`）——测出这台机器在固定风扇档位下的热平衡点，反向构造机器专属控制曲线。
- **在线控制环**（`ThermalMonitor.tickSmart`，`Sources/SmartFanCore/ThermalMonitor.swift`）——在 100ms 节拍上实时驱动，带安全兜底。

本文剖析两层的逻辑、常量与设计取舍。相关配置定义见 `Profile.swift` 的 `FanProfile.smart`。

## 一、在线控制环

### 1.1 双节拍调度

`ThermalMonitor.tick()` 每 **100ms** 执行一次，`tickCounter` 做分频：

| 分频 | 周期 | 做什么 |
|---|---|---|
| 每 tick | 100ms | 读温度、算目标、写风扇 |
| `% 20` | 2s | 采样 `tempHistory`、进程捕获、异常检测 |
| `% 5` | 500ms | 回调 UI（`onUpdate`） |

关键点：**温度历史只在 2s 边界采样**（`tickSmart` 开头），让速率变化率不被 100ms 高频噪声污染。

### 1.2 关键常量

```swift
smartFloor    = 53°C   // 比其它 profile 的 55°C 早 2°C 介入（"主动"）
smartCeiling  = 85°C   // 到达即满转
smartStopTemp = 50°C   // 与所有 profile 共享的关闭阈值
sustainedTriggerSec = 6s  → 60 ticks
rampUpPerSec   = 0.05/s   // 每 tick 0.005
rampDownPerSec = 0.025/s  // 每 tick 0.0025（非对称，降速更保守）
应用阈值 = 0.002（约 15 RPM，@ 最大 7826 RPM）
```

### 1.3 决策状态机（严格顺序，越靠前越优先）

```
① 关停机：T < 50 且 风扇在转 且 rate ≤ 0  → resetAuto（交还 Apple 自动）
② 保持关：T < 53 且 风扇未转              → return
③ 迟滞带：50 ≤ T < 53 且 风扇未转         → return（保持现状，防振荡）
④ 持续触发门：未转 且 连续 T≥53 不足 60 tick → return（滤瞬时尖峰）
────────── 以上通过后才真正计算目标转速 ──────────
```

① 中的 `rateOfChange() <= 0` 很关键：**即使温度已在 50°C 以下，只要还在升温就不关机**，避免「刚降温就被关、又被下一脚负载顶回去」的循环。

作为对比，其它 profile 走 `tickCurve`，用 `Curve.targetPercent` 的静态曲线（见 `Profile.swift`），没有速率前馈与标定查表。

### 1.4 目标转速计算（两条路径）

**A. 已标定 —— 机器专属查表**

```swift
targetPct = cal.fanPercentForTemp(T)              // 对测量点线性插值
if rate > 0 {
    urgency = clamp((T - 53) / (85 - 53), 0, 1)   // 距上限的紧迫度
    targetPct += rate * 0.15 * (1 + urgency)      // 前馈：越热越急着加力
}
```

- `rate` 单位 °C/s，来自 2s 采样窗口的线性近似（`tempHistory` 最多 4 点 ≈ 6s）。
- 前馈项随 `urgency` 放大：越接近 85°C，同样升温速率加得越猛。

**B. 未标定 —— S 形曲线兜底**

```swift
pos = clamp((T - 53) / (85 - 53), 0, 1)
targetPct = pos²(3 - 2pos)          // smoothstep，两端平滑
if rate > 0 { targetPct += rate * 0.2 }
```

`pos²(3-2pos)` 在低温端斜率小（安静）、中段陡（快速响应）、高温端趋平。

标定数据缺失、损坏或被校验拒绝时，自动回退到 B 路径（`tickSmart` 中 `calibration == nil` 分支）。

**共同后处理**

```swift
if T > 85 { targetPct = 1.0 }                                  // 上限硬顶
targetPct = clamp(targetPct, 0, 1)
if targetPct > 0 && targetPct < minPct { targetPct = minPct }  // 不低于硬件最小转速
```

其中 `minPct = minRPM / maxRPM`。

### 1.5 爬升 / 回落速率限制（Ramp Governor）

```swift
rampUp   = 0.05  * 0.1 = 0.005  /tick
rampDown = 0.025 * 0.1 = 0.0025 /tick
```

- 目标 > 当前：`min(target, last + rampUp)`
- 目标 < 当前：`max(target, last - rampDown)`

结果：0 → 100% 至少需 ≥20s 上升、≥40s 下降。**升快降慢**，避免风扇在临界温度反复起停（起停循环是 Apple 风扇 #1 轴承损耗因素，见 `Profile.swift` 头注释）。

### 1.6 下发节流

```swift
if abs(target - lastApplied) > 0.002 { setRPM(max(maxRPM * pct, minRPM)) }
```

0.002 ≈ 15 RPM，过滤掉无意义的微调，避免 10Hz 反复刷新 daemon。

## 二、安全层（优先级高于 Smart）

在 `tick()` 中，安全判断位于进入 profile 逻辑**之前**：

```swift
if maxTemp >= 95 { setMax(); state = .safetyOverride }         // 任意传感器 >95°C 直接满转
if state == .safetyOverride && maxTemp < 95 - 5 { state = .idle }  // 降到 90°C 以下才解除
```

- 用的是 `status.safetyPeakTemp`（全 die 最热点，含 GPU / SoC hotspot 键），不是 UI 显示值——安全永远跟随最热点。
- 5°C 迟滞防止在 95°C 附近抖动。
- 安全层触发时 `return`，Smart 不再参与本次决策，因此 Smart 无论算出什么都不可能突破 95°C 硬顶。

## 三、离线标定算法

标定是 Smart 「智能」的来源：测出**这台机器在固定风扇档位下的热平衡点**，再反推控制曲线。

### 3.1 流程

```
Phase 0    冷却到 <45°C
Phase 1    找压力强度 → 目标升温约 1°C/s
Phase 1.5  再次冷却到 <45°C
Phase 2    风扇档位扫描 [100%, 80%, 60%, 45%, minPct]（高 → 低）
Phase 3    由平衡数据反向构造控制曲线
```

### 3.2 Phase 1：自适应找强度

- 从 1% 起，跑 10s 测温升速率，按 `intensity *= 1.0 / rate` 比例调整，收敛到 0.8–1.2°C/s。
- 目标是对齐真实工作负载升温率（~1°C/s），而非合成满载（~5–8°C/s）。
- 压力源：CPU 线程数（`intensity × 核数`）+ Metal compute shader（`fma`/`sqrt`/`sin` 密集 FP32，网格规模随 intensity 缩放），模拟 CPU+GPU 同 die 发热。

### 3.3 Phase 2：稳定判定

```swift
windowSize = quick 30 (60s) / standard 45 (90s) / optimized 60 (120s)   // 2s/读
stable = stdev < 0.5°C && |slope| < 0.05°C/s
```

- 用**标准差 + 最小二乘斜率**双条件判定稳定，而非单纯时间窗。
- 超时则用尾部窗口均值兜底。
- 到 84°C 记录上限并跳过更低档；到 90°C 触发安全满转。

标定模式与其精度（见 `CalibrationMode`）：

| 模式 | 稳定窗口 | 每档最长等待 | 最长总时长 | 精度 |
|---|---|---|---|---|
| quick | 60s | 150s | ~17 min | ~80% |
| standard | 90s | 240s | ~25 min | ~90% |
| optimized | 120s | 360s | ~35 min | ~95% |

### 3.4 Phase 3：曲线反转（最巧妙的一步）

原始数据是 `(fanPct, equilTemp)`——**高风扇 → 低平衡温度**。对固定温度锚点 `[60, 65, 70, 75, 80, 85]°C`：

```swift
fEquil(T) = 在原始数据里插值：平衡温度 = T 时对应的风扇档位
controlFan(T) = (1.0 + minPct) - fEquil(T)
```

因为 `fEquil` 随 T 单调**递减**（温度越高越省风扇），取补后 `controlFan` 随 T **递增**——正好得到「温度越高、风扇越猛」的控制曲线，且值域落在 `[minPct, 1]`。

### 3.5 数据健壮性

- `validationError` 校验：目标温度在 40–100°C、占比在 0–1，且**高阶温度的风扇不得低于低阶 0.05**（单调性）。
- 加载即校验；坏数据 / 损坏 JSON 直接删除，回退到未标定的 S 曲线。
- 模式有 rank（quick 1 < standard 2 < optimized 3），`wouldDowngrade` 阻止低质量标定覆盖高质量结果。

## 四、整体数据流

```
标定（一次性）                              运行时（100ms）
────────────────────                       ────────────────────
stress + 风扇档位扫描                        读 safetyPeakTemp
   ↓                                            ↓
(档位, 平衡温度) 点集                        安全 >95°C? → 满转
   ↓ 反转 (1+minPct) - fEquil                 ↓
calibration.json ──加载+校验──→ 命中 → 查表插值 ─┐
                                未命中 → S 曲线 ─┤
                                                ↓
                                       + rate 前馈（rate > 0 时）
                                                ↓
                                       clamp[0,1] → ≥ minPct
                                                ↓
                                       Ramp Governor（升快降慢）
                                                ↓
                                       阈值 0.002 → setRPM
```

## 五、设计取舍与值得注意的点

1. **前馈不对称**：只有 `rate > 0`（升温）才加推力；降温不额外减力，仅靠 rampDown 慢回落。这是刻意设计——防止降噪抖动，代价是降温后风扇退得偏慢。

2. **速率窗口很短**：`tempHistory` 最多 4 点、2s 间隔，即 ~6s。对缓慢累积的热（长编译）够用，但对 >6s 的持续趋势不敏感，主要由 `sustainedAboveCount`（6s 门）与温度绝对值补足。

3. **反转公式是启发式**：`(1+minPct) - fEquil` 并非严格物理推导，而是把「平衡关系」映射成「控制关系」的构造。物理上合理（单调性与值域都对），但非理论最优；固定锚点插值意味着锚点外的外推是平坦的。

4. **标定成本高**：optimized 最长 35 分钟，是 5 档 × 最长 6 分钟的暴力扫描。quick 模式降到 ~80% 精度。属「一次性换长期收益」的设计。

5. **安全与智能解耦干净**：安全在 `tick()` 外层、Smart 在内层；Smart 无论算出什么都被 95°C 硬阈值与 minPct 双重兜底。

6. **标定数据与运行时分离**：`calibration.json` 独立文件 + 校验 + 损坏自愈，daemon / CLI / App 共用同一份数据。

## 相关文档

- [project-architecture.md](project-architecture.md) — 项目整体架构剖析
- [thermal-sensor-calibration-20260924.md](thermal-sensor-calibration-20260924.md) — 热传感器标定
