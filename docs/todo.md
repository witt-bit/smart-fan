# 待办事项（统一索引）

本文件是**所有未完成、待决策、待清理事项的唯一索引**。详细的背景与设计在各计划文档里，这里只汇总"还剩什么、下一步做什么"。

- 状态：随开发更新（完成一项就勾掉并注明提交）
- 相关计划：[daemon-self-management-plan.md](daemon-self-management-plan.md) · [menu-bar-display-plan.md](menu-bar-display-plan.md) · [update-check-plan.md](update-check-plan.md)
- 优先标记：🔴 阻塞发布 · 🟠 应尽快 · 🟡 有空再做 · ⬜ 待决策

---

## 1. 进行中：P7 守护进程随 App 自管理

详见 [daemon-self-management-plan.md](daemon-self-management-plan.md)。

- [x] **P7.1 路径与打包** — `installPath` 迁到 `/Library/PrivilegedHelperTools/`；`build-app --cli` 内嵌二进制；`install` 识别所在 bundle；自我复制防护
  - [x] 上述三项（`d46d2c9`、`6aeb210`）
  - [ ] 🟡 **清理死代码**：cask 下已无意义的 keg 再同步逻辑与「寻找匹配 app」旧分支（`newerHomebrewKeg`、`/opt/homebrew/opt/...` 候选）
- [x] **P7.2 app 侧状态机** — `syncBackgroundService()` 一个动作覆盖缺失/落后/无响应 + SHA-256 幂等（`f0699c0`）
- [x] **P7.3 横幅改按钮** — 关于页「更新后台服务」、风扇页「修复后台服务」
- [ ] 🟠 **P7.4 分发**
  - [ ] cask 定义（Homebrew cask，只交付 `.app`）
  - [ ] CI 产物流转（发行包 → cask 引用）
  - [ ] README：安装章节以 **cask 为主**；用户流程删掉 `sudo … install`；CLI 归入「开发与贡献」
- [ ] 🟡 **P7.5 测试** — 状态机与哈希幂等的纯逻辑测试补全（已覆盖 shell 引号、AppleScript 转义、内容哈希、enclosingBundle）
- [ ] ⬜ **实机验证（需要交互式授权，无法自动化）**
  - [ ] 真实弹出管理员密码框 → helper 装到 `/Library/PrivilegedHelperTools/`
  - [ ] `scripts/setup.sh reinstall` → `doctor` 全绿
  - [ ] 故意制造版本不一致（替换 helper 为旧二进制）→ 验证「更新后台服务」按钮
  - [ ] `scripts/setup.sh uninstall` / `uninstall -f` 各跑一次

## 2. 上游合并（MacFanPro 0.2.3.24 → 0.2.3.29）

- [x] **批次 1 — Core 修复**（`ca33857`）
  - [x] 热保护挂起期间命令失败会把热风扇掉回自动
  - [x] 更新检查被 GitHub 未认证 API 的 60 次/小时限额打中（改用 `/releases/latest` 重定向）
- [x] **批次 2 — 更新检查结果状态**（`8e4ee16`）：结果行 + 超长换行 + 关闭即清除 + 完成/失败语义
- [ ] ⬜ **批次 3 — 14 种新 GUI 语言**（`6fb6c8f`）
  - 机制很简单：`supportedLanguages = AppLanguage.allCases.filter { $0 != .system }`（加语言 = 加一个 JSON，可合并）
  - **卡在内容**：上游 14 个 JSON 各 **57 键**，我们的 `en.json` 有 **84 键** → 差 **27 键**（菜单栏显示、首选项各页、固定速率、后台服务同步…）
  - 直接并入会让 `LocalizationTests`（要求三语言键集合一致）**失败**，界面也会中英混杂
  - 选项：**(a)** 我补翻 27 键 × 14 语言（≈378 条，机器起草、未人工复核）；**(b)（推荐）** 只合机制、翻译交给社区贡献（"补一种语言的 JSON" 是理想的第一个 issue）；**(c)** 先不动
- [ ] 🟡 **文档类未合**
  - [ ] 上游各版本 release notes（0.2.3.24–29）与 validation 记录
  - [ ] README 双语化（`b456b63`：英文 README + 中文版）
  - [ ] 刷新 README 截图（当前仍是 0.2.3.19 时期的菜单界面，且下拉菜单已下线，截图已不准确）

### 批次 4 — 0.2.3.30 → 0.2.3.35（更新流程与分发）

> **架构分歧（先说清楚）**：这一批是 **「脚本化更新」路线** —— 在线安装器 `curl | bash` + Homebrew formula/bottle + 应用里给命令去终端跑。
> 我们的 **P7 是另一条路线**：app 内嵌守护进程、自己安装/升级、一次管理员授权、cask 分发。
> 两者解决同一个问题，**大部分不可直接合并**；但其中几个独立修复值得取。

- [x] **已合**（`46a02dd`）
  - [x] `install` 完成后**校验活守护进程报告的版本**（否则可能“成功”但实际还是旧守护进程在服务）
  - [x] `auto --stop-app` **不再打印版本不一致提示**（它是更新前一步，那条提示像失败）
- [ ] ⬜ **待决策：在线安装器** `Scripts/install.sh`（182 行）+ `Scripts/test-installer.py`（259 行）
  - 优点：`curl -fsSL .../releases/latest/download/install.sh | bash` 一条命令装完，服务**没有 Homebrew 的用户**
  - 它做得相当严谨：拒绝 Rosetta/root shell、代理支持、Homebrew-aware（不悄悄切到手装）、SHA256 + 归档成员路径/类型校验（禁越界/符号链接/硬链接）、App 身份与严格签名校验、拒绝降级、先取得 sudo 再停应用、JSON 校验后清理
  - 与我们冲突：它装的是 tar.gz 里的 CLI/daemon；我们已改为 app 内嵌二进制 + cask
  - 值不值得移植？若不移植，无 Homebrew 的用户只能自己下载 `.app`
- [ ] ⬜ **待决策：“Update in Terminal”**（写一个 `.command` 到用户私有临时目录，用 Terminal 打开执行）
  - 这是他们给**app 自身更新**的答案（app 不会自我更新）；我们目前只显示命令文本
  - 若我们要做「一键更新 app」，这是现成的安全实现（脚本随 app 签名、版本占位符在组装时替换）
- [ ] ⬜ **待决策：安装来源探测 + 按来源给更新步骤**
  - 机制：`installedWithHomebrew`（存在 keg 目录）+ `MacFanProSourceDirectory`（setup.sh 写进 Info.plist）
  - 我们的映射应为：**cask / 源码 / 下载包** 三种
  - 顺带：我们的关于页现在显示的更新命令（`brew upgrade smart-fan && sudo smart-fan install`）在 P7 之后**已经过时**（守护进程不再需要手动同步），需一并修正
- [ ] ⬜ **Arabic + 从右到左（RTL）面板**（`ar.json` + AppLanguage）—— 同样受 §批次 3 的 27 键缺失问题阻塞
- [ ] 🟠 **CI：发版后自动 bump 分发渠道**
  - 上游用 `notify-tap.yml` 通知 Homebrew tap
  - **我们是 cask，等价需求同样存在**：每次发版必须自动更新 cask 的版本与 `sha256`，否则用户 `brew upgrade` 拿不到新版
  - 建议纳入 P7.4

### 批次 5 — 0.2.3.38 → 0.2.3.62（25 个版本，改动最大的一批）

> 上游这段时间在**做和我们同类的事**：把首选项搬进设置窗口、给服务安装/替换写了一套新架构。
> 架构部分**不可合并**（两边各有各的实现），但其中的**安全与正确性修复**值得移植。

- [x] **守护进程启动/停止时释放风扇**（`4fc03b0`，ThermalForge #31）（本次）
  - `StartupFanReconcile`：启动时若风扇处于手动但**无人持有** → 归位 auto（守护进程被杀、崩溃、
    或无守护进程时被 root 直接写入的情形）
  - `DaemonShutdown` + SIGTERM handler：bootout / kill 时释放自己持有的风扇，且**不碰不属于自己的**
  - `FanControl.manualControlEngaged()`（任一风扇 manual 或 Ftst 仍置位）
  - 测试 `DaemonStartStopTests`（6 项）一并移植
  - **为什么我们也有这个问题**：app 的 `syncBackgroundService()` 会重启守护进程，而新进程
    「不持有任何东西」→ 旧 hold 会永远留在 SMC 上（没有 watchdog/floor/wake 再碰它）
- [ ] 🟠 **socket 对端认证**（`43f4a88`，加了又回滚后重新落地）—— **我们同样缺**：
  `/var/run/smart-fan.sock` 目前同机其他用户也能连（socket 虽 chown 给属主 + 0600，
  但内核不校验对端身份）。上游做法：连接时读对端 euid/egid，只放行 root 或属主，
  读不到凭据一律拒绝。相关文件与我们同名（ConnectionServer/DaemonInvariants），可移植
- [ ] 🟡 **`safetyPeakTemp` 把 `Te` 纳入**（上游已改）—— 我们的基仍是 `TC/Tp/TG/Tg`；
  采纳需同步改 `SensorRole.controlPrefixes` 与相关文档
- [ ] ⬜ **只看不抄：安装器可靠性**（`InstallationReliabilityTests` 315 行、`SafeFileCopy`、
  `AppBundleReplacement`、`make install/daemon/sudo 命令安全可预测`、`recover failed installs and
  stop unsafe removal`）—— 架构不同不合并，但里面的**失败模式清单**值得拿来审查我们的
  `install`/`uninstall` 是否有同类缺陷
- [ ] ⬜ **不合并**：上游的设置窗口/面板 UI 重构、网站（GitHub Pages 18 语言）、DMG 拖拽安装、
  `MacFanPro.swift` CLI 重写、14 种语言的 56 条新文案（都是他们新 UI 的）

## 3. 更新检查功能（Phase 1 剩余）

详见 [update-check-plan.md](update-check-plan.md)。已完成：手动检查按钮、检查中状态、结果行（`8e4ee16`）。

- [ ] 🟡 自动检查开关（`autoCheckUpdates`，默认开）
- [ ] 🟡 上次检查时间（`updateLastCheckedAt`，如"上次检查：今天 14:02"）
- [ ] 🟡 失败细分：`offline` / `rateLimited`（403、429）/ `other`，只有手动检查才显示原因
- [ ] 🟡 发行说明：`Release` 解码 `body`、`published_at` 并在应用内展示
- [ ] 🟡 约 10 秒冷却，防止连点保护限额
- [ ] 🟡 手动检查无视「稍后」但不清除它
- Phase 2（发行说明窗口 / 按安装方式给指引）→ **已被 P7 取代**
- Phase 3（一键更新 app 自身）→ **已被 cask 分发取代，不做**

## 4. 菜单栏显示（低优先级）

详见 [menu-bar-display-plan.md](menu-bar-display-plan.md)。

- [ ] 🟡 **MB-6.1** 菜单栏风扇图标随转速旋转（Core Animation 旋转图层，默认关闭；映射需压缩，满转 ≈1.5 转/秒）
- [ ] 🟡 菜单栏分段**拖动排序**（当前是固定顺序 + 显隐）

## 5. 后续版本：iCloud 配置同步（收费功能）

详见 [menu-bar-display-plan.md](menu-bar-display-plan.md) §13。

- [ ] ⬜ **Q8** 同步哪些配置？（仅菜单栏显示 / 全部偏好 / 含校准与模式）
- [ ] ⬜ **Q9** 分发与付费模式？（App Store IAP / 第三方授权 / 其他）
- [ ] ⬜ **Q10** 未授权用户的降级行为？
- [ ] ⬜ MB-5.1…5.6（决策 → 签名改造 → 同步层 → 付费门槛 → UI → 文档合规）

**三个硬约束**（不解决就无法实现）：
1. iCloud 权限**要求真实签名**，当前 ad-hoc 用不了
2. StoreKit IAP **仅限 App Store 分发**
3. MIT + 源码可构建 → **付费门槛可被绕过**，需先定许可策略

→ 与「2.0 平台化改造」（真签名 + 内嵌 helper + `SMAppService`）**同一前置**，建议合并规划。

## 5.5 高温防护（已实现，遗留一项）

详见 [high-temp-protection-plan.md](high-temp-protection-plan.md)。

- [x] **阶梯取代单阈值** —— 90°C/10s → 50%，95°C/30s → 100%，每级至少保持 30 秒；下阶梯同样分级
- [x] **掉档宽限 3 秒** —— 单次采样掉线不再作废窗口；只累计真正在阈值以上的时间
      （实测回放：100ms 级抖动下满速可达；97–100°C 时 30 秒准时升级）
- [x] **两个开关**（风扇页）—— 「高温防护」（默认开，关 = 永不启用）、「在默认模式也生效」（默认关）
- [x] **守护进程兜底阈值 95 → 105**（`emergencyTempThreshold`）—— 高于阶梯范围与其 30 秒升级窗口，避免抢同一个风扇
- [x] 测试：`HighTempProtectionTests`（16 项纯逻辑）+ `ControlLoopRecoveryTests` 重写 + `DaemonInvariantsTests`
- [ ] 🟠 **安全层的传感器基（已确认，暂缓）** —— `safetyPeakTemp` 取 `TC/Tp/TG/Tg` 全部键的最大值，
      含我们标注为「不是核心温度」的 SoC 热点键（`TCMz`/`TCDX`/`TCMb`、派生 `Tp*`）。
      实测差 **+6.3 ~ +11.7°C（均值 ≈ +9）**：所谓「95°C 保护」实际是「真实核心 84–88°C 就介入」。
      **建议修法**：改用与界面一致的基（`max(最热真实核心, 最热 GPU)`），
      使「面板显示 X°C」与「安全层看到 X°C」一致；无校准键表的芯片保持现有行为。
      阶梯加了时间维度后危害已降级为「提前约 9°C」，不再紧急。详见计划文档 §5
- [ ] ⬜ **待决定**：是否让守护进程的应急兜底也受「高温防护」开关控制
      —— 目前它**不受开关控制**（它是最后一道防线）。要做到「不勾选就完全没有保护」需改守护进程协议
- [ ] ⬜ **待决定**：「最大转速的一半」是否应是「风扇区间的一半」（当前按字面取 max×50%）
- [ ] 🟠 **真机验证**：默认模式下不再反复触发；打开「在默认模式也生效」后应看到 50% → 100% 的阶梯

## 5.6 面板读数口径（部分待定）

- [x] **每行加 ⓘ 说明来源**（点击弹出：取自哪些 SMC 键、如何合并）
- [x] **CPU/GPU 行接回校准定义** —— 与菜单栏数字一致（此前差 0.3–10.7 °C，删下拉菜单时丢的修正）
- [ ] ⬜ **均温口径待你决定** —— 现状 = 33 键算术平均 = 65.6°C；只算芯片键 ≈ 73.8°C；按值去重 ≈ 72.7°C
      （见 high-temp-protection-plan 之外的实测记录；选定后要同步改 ⓘ 文案、计划文档与 CHANGELOG）
- [x] **阶梯的传感器基** —— 已改用校准读数 + 释放回差 5°C（现场问题见 §7）
- [ ] ⬜ **模式曲线的传感器基** —— 上游曲线仍照 `safetyPeakTemp` 标定（含非核心键、比核心高约 7°C）；
      若也要统一，需**重新标定 55/65/85 这几条线**。详见 high-temp-protection-plan.md §5

## 6. 发布前专项

- [ ] 🟠 **性能：自适应轮询**（详见 menu-bar-display-plan §11）
  - 实测：完整 App 空转 **3.42%** 单核；`watch` @10Hz **2.17%** vs @1Hz **0.23%**
  - 上游 Experiment 2 佐证：传感器扫描 ≈ **2.7pp**（占空闲 CPU ~64%），他们选择不改（保"每次读取都校验 + 每个传感器都覆盖"）
  - 我们的方案减的是**轮询频率**（不控制时 10Hz→1Hz），不减 key、不跳校验 → 不冲突
  - 目标：空转 **≤0.5% 单核**
- [ ] 🔴 **创建 `docs/releases/1.0.0.md`** —— `release.yml` 在打 `v*` tag 时会校验该文件存在，否则**发布流程直接失败**
- [ ] 🔴 **仓库转公开** —— 当前为私有（匿名访问 404），README 徽章与应用内「检查更新」对外都不可用
- [ ] 🟠 决定是否推送 **17 个上游 tag**（`v0.2.3.x`，目前只在本地）
- [ ] 🟡 版本号仍为 `1.0.0`（未发布）；发布时同步 `docs/releases/`、CHANGELOG

## 7. 已知小尾巴 / 清理项

- [ ] 🟡 README 仍含 `0.2.3.19` 时期的示例：`git checkout v0.2.3.19`、`SmartFan-0.2.3.19-macos-arm64`、截图说明
- [ ] 🟡 README 的「日志与数据」「常见问题」章节仍按**旧版下拉菜单**描述，与实际（首选项窗口）不符
- [ ] 🟡 `scripts/setup.sh` 无参数现在是显示帮助（原为直接安装）；如需回退为一键安装请说明
- [ ] 🟡 上游 `codex/*` 等 10 个分支未推送（上游分支，非我们的）
- [x] 本地提交已全部推送（`5aa6996`，含菜单栏左键打开首选项的修复）

---

## 已完成（简表）

| 区域 | 状态 |
|---|---|
| 项目改名 MacFanPro → SmartFan | ✅ 1.0.0 |
| 菜单栏可自定义（4 样式 / 度量 / 曲线 / 固定速率 / 首选项窗口） | ✅ P1–P4 共 21 项 |
| 守护进程自管理（app 内嵌 + 一次授权 + 哈希幂等） | ✅ P7.1–7.3（P7.4/7.5 见上） |
| 高温防护阶梯（两个开关 + 守护进程兜底 105°C） | ✅ 遗留 1 项（见 5.5） |
| 上游 0.2.3.20–23 合并 | ✅ |
| 上游 0.2.3.24–29 合并（Core + 更新检查 UI） | ✅ 批次 1、2 |
| `scripts/setup.sh` 统一入口（20 个命令） | ✅ |
| 仓库引用指向 `witt-bit/smart-fan` | ✅ |
