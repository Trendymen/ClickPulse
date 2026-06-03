# ClickPulse 设计规格 v2

- **初稿**：2026-06-02　**修订**：2026-06-03（经 workflow 多维对抗式审查，处理 20 条确认发现）
- **目标平台**：macOS 26.5（Apple Silicon / arm64）
- **最低部署目标**：macOS 14.0（满足 @Observable / SMAppService / Swift Charts 的下限）
- **技术栈**：原生 Swift / SwiftUI + AppKit，**Xcode App target** 工程
- **交付模式**：AI 全权代写并维护，用户零代码维护（只负责安装/授权/使用）
- **Bundle ID（定死，三处唯一来源）**：`com.liuzhuo.clickpulse` —— 同时用于 `CFBundleIdentifier`、LaunchAgent Label/文件名、数据目录名，**定稿后不再变更**（变更会导致 TCC 授权失效）
- **安装路径（锁定）**：`/Applications/ClickPulse.app` —— TCC 授权绑定路径，移动会失效

---

## 1. 概述与目标

ClickPulse 是一个**专注于鼠标点击统计**的 macOS 菜单栏常驻小工具。后台全局统计鼠标点击，菜单栏只显示一个图标，点开面板展示**时 / 日 / 周 / 月 / 总**五档点击数，并提供历史趋势、分时段热力图与数据导出。强调极轻量、长期稳定、纯本地隐私。

**核心目标**：

1. 全局、持续、低开销、**计数准确**地统计系统级鼠标点击。
2. 菜单栏图标 + 面板，清晰展示五档计数与分按键明细。
3. 历史趋势 + 分时段热力图 + CSV/JSON 导出。
4. 开机自启 + 崩溃/被杀自动拉起 + **故障对用户可见**，最大程度避免统计遗失。
5. 纯本地、开源、无账号、零联网上报。
6. 由 AI 全权实现与维护，用户不需要懂代码。

---

## 2. 需求（固定）

| 编号 | 需求 |
|---|---|
| R1 | 全局监听系统级鼠标点击，统计左/右/中键，且可**分按键查看**各自次数 |
| R2 | 菜单栏只显示一个图标；点开面板显示 **时/日/周/月/总** 五档点击数 |
| R3 | 历史记录与趋势视图 |
| R4 | 分时段点击热力图（一天里哪个时段最活跃）|
| R5 | 导出数据为 CSV / JSON |
| R6 | 按「小时」粒度本地持久化，五档统计 + 热力图 + 历史全部从这一份数据派生 |
| R7 | 开机自启 + 崩溃/被杀后自动拉起 |
| R8 | 极轻量，可 7×24 常驻 |
| R9 | 隐私优先：开源、纯本地、无账号、零联网上报 |
| R10 | 全局监听权限的申请 + 检测 + 引导用户开启 |

**约定**：

- 周起点为**周一**。
- 计数只取 `*MouseDown`，不取 `*MouseUp`，避免双倍计数。
- 不监听 `mouseMoved`。
- **时间口径统一为「本地时区」**：每次点击按**当前本地墙钟**确定所属小时桶；桶同时记录该桶的本地小时(0–23)与本地星期(1–7)，所有派生视图（时/日/周/月/总、热力图、趋势）都基于同一本地时区基准（见 §7、§8）。

---

## 3. 非目标（YAGNI）

- 不统计键盘按键、鼠标移动距离、带宽。
- 不做云同步、账号体系、联网上报。
- 不做屏幕位置热力图（仅做「时段」热力图）。
- 首版不做实时 CPM 速率指标。
- 不追求向下兼容到旧 macOS（自用、单机；部署目标 14 仅为 API 下限留余地）。

---

## 4. 技术选型与依据

选定**原生 Swift/SwiftUI + AppKit**，依据来自三方方案对比 + 深度研究（对抗式验证）：

- AI 代写成功率最高：CGEventTap 是 macOS 标准 API，有 KeyCount、Keys vs Clicks、CGEventSupervisor、EventTapper 等真实开源样板。
- 资源最轻、面板体验最好、长期最可靠：优于 Hammerspoon（宿主税 + 偶发权限错乱）与 Electron（100MB+）。
- 权限模型清晰稳定：`.listenOnly` 的 CGEventTap 对应「输入监控」权限，10.15→26 一路延续。

**工程形态**：Xcode App target（`.xcodeproj`），原生支持 `LSUIElement`/Info.plist/entitlements/`.app` 打包；GRDB 作为 Swift Package 依赖接入。详见 §20 工程结构与构建。

---

## 5. 总体架构

纯菜单栏 App（`LSUIElement = true`，激活策略 **Accessory** —— 绝不用 `LSBackgroundOnly`/Prohibited，后者会引入事件 tap 创建失败路径）。单进程分层：

```
捕获层  EventTapController   ── 维护 CGEventTap(.listenOnly)，回调只做加锁内存自增 + 健康自愈
聚合层  ClickCounter         ── os_unfair_lock 保护 {left,right,middle,other} 当前小时计数；提供 swap 取出
持久层  ClickStore           ── GRDB/SQLite，按小时×按键事实表，增量 upsert + 聚合查询 + 迁移
派生层  StatsProvider        ── @Observable，把查询结果转 ViewModel 供 UI 订阅
UI 层   StatusItemManager + IconStateController + SwiftUI 视图
系统层  PermissionManager / LaunchAgentService / ExportService
```

**关键并发约束**：CGEventTap 回调运行在其 run loop 线程，flush/查询在另一线程——`count += 1` 在 Swift 里**不是原子操作**，必须加锁（见 §14.1）。

---

## 6. 全局点击监听与权限模型

### 监听

- API：`CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask, callback:, userInfo:)`。
- 掩码：`leftMouseDown | rightMouseDown | otherMouseDown`。
- 分按键：`otherMouseDown` 读 `mouseEventButtonNumber`，2=中键；其它（侧键 3/4…）归 `other`。
- 回调：**加锁**对对应按键计数器 +1，`return Unmanaged.passUnretained(event)`（原样放行）。

### 权限（「输入监控」）

- `.listenOnly` 对应 Input Monitoring（`kTCCServiceListenEvent`）。
- 启动 `CGPreflightListenEventAccess()` 静默检测；未授权 `CGRequestListenEventAccess()` 弹窗，并用 `x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent` 直达面板。
- 授权变更后重建 tap 才生效。
- 诚实标注：纯鼠标监听是否「一定」需要授权官方未写死，按「需要」兜底设计：真不需要则零摩擦。

---

## 7. 数据存储设计

### Schema（按小时 × 按键，统一本地时区口径）

```sql
CREATE TABLE click_hourly (
    hour_ts       INTEGER NOT NULL,  -- 本地墙钟整点对应的 Unix 秒(绝对时刻，由 Calendar.current 求 startOfHour)
    local_hour    INTEGER NOT NULL,  -- 0–23：该桶在本地时区的小时(写入时由本地日历分解，避免派生层对 epoch 裸取模)
    local_weekday INTEGER NOT NULL,  -- 1–7：周一=1 … 周日=7
    button        INTEGER NOT NULL,  -- 0=left 1=right 2=middle 3=other
    count         INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (hour_ts, button)
);
CREATE INDEX idx_click_hour ON click_hourly(hour_ts);
CREATE INDEX idx_click_local ON click_hourly(local_weekday, local_hour);

CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);  -- schema_version、timezone、tz_changed_at 等
```

> 为什么存 `local_hour`/`local_weekday`：`hour_ts` 是绝对 UTC 纪元秒，对它 `(hour_ts/3600)%24` 取模得到的是 **UTC 小时**，在东八区会让热力图整体平移 8 格（违反 R4）。写入时一次性按本地日历分解出 `local_hour`/`local_weekday`，派生层直接 GROUP BY，口径恒为本地、且对半小时偏移时区也正确。

### 落盘位置（明确）

- 数据库：`~/Library/Application Support/com.liuzhuo.clickpulse/clickpulse.sqlite`（含 `-wal`/`-shm`）。
- 用 `FileManager.url(for: .applicationSupportDirectory)` 取得，目录不存在则创建。
- **不开启 App Sandbox**（需任意路径写盘 + 全局事件 tap + 写 LaunchAgent；沙箱会把路径重定向进 Container，破坏「路径透明」并阻断写 LaunchAgent）。entitlements 据此配置。

### 写入

- 点击只改内存（加锁）；按 ~30 秒 / 整点翻篇 / 退出 / 休眠前增量 upsert：
  `INSERT INTO click_hourly(hour_ts,local_hour,local_weekday,button,count) VALUES(...) ON CONFLICT(hour_ts,button) DO UPDATE SET count = count + excluded.count;`
- WAL 模式 + 事务写入。体量：一天 ≤96 行，一年约 3.5 万行，毫秒级查询，磁盘每年数 MB。

### Schema 迁移（必备，不是「以后随便迁」）

- 权威版本号：`PRAGMA user_version`（或 meta 行），首版 = 1。
- 启动时读版本 → 按版本号顺序执行**幂等**迁移（首选 GRDB `DatabaseMigrator`）。
- 迁移在**事务内**进行；失败回滚并先备份 `clickpulse.sqlite.bak`。
- 处理「库版本 > App 期望版本」（用户装了更老 App）：提示并只读/拒绝写，避免老 App 破坏新结构。
- 退化为裸 `sqlite3` 时保留同一套迁移机制。

---

## 8. 派生统计（全部从 click_hourly 聚合，统一本地口径）

| 视图 | 取数 |
|---|---|
| 时 | `hour_ts = 本小时起点`（`Calendar.startOfHour`）|
| 日 | `hour_ts >= 今日 0 点`（`Calendar.startOfDay`）|
| 周 | `hour_ts >= 本周一 0 点`（`Calendar.firstWeekday = 2`）|
| 月 | `hour_ts >= 本月 1 号 0 点`（`Calendar` 月首）|
| 总 | 全表 `SUM(count)` |
| 分按键 | 任意区间加 `GROUP BY button` |
| 趋势 | `GROUP BY` 截断到天/周/月 |
| 热力图 | `SELECT local_weekday, local_hour, SUM(count) GROUP BY local_weekday, local_hour`（**用本地字段，不对 epoch 取模**）|

- **「合计」口径定义**：面板「合计」= 全表 `SUM(count)`，**含 other**。因此「合计」≥ 左+右+中，差额即 other（见 §9 分按键档处理）。
- 日/周/月边界均用时区感知的 `Calendar` 求得对应 epoch 秒，与热力图的本地口径一致，不再有两套基准。

---

## 9. 菜单栏与面板 UI

- **菜单栏**：一个图标（SF Symbol `cursorarrow.click`，模板图标自适配深浅色）。图标有**状态**（见 §14.2）：正常 / 异常（变灰 + 感叹号 badge）。默认不显示数字。
- **面板**：点击图标弹 `NSPopover`（内嵌 SwiftUI），点外部/再点图标收起。选 NSStatusItem + NSPopover 而非 `MenuBarExtra`，换取定位/收起/刷新的最佳可控性。
- **布局**：

```
┌────────────────────────────────────────┐
│  [ 合计 | 左键 | 右键 | 中键 (| 其它) ]   │ ← 分按键切换；“其它”档仅当存在 other>0 时出现
├────────────────────────────────────────┤
│   时      日     周     月     总          │ ← 5 个等宽数字，随上方切换联动
├────────────────────────────────────────┤
│  [ 趋势 | 热力图 | 导出 | 设置 ]           │
│  … 对应内容 …                            │
└────────────────────────────────────────┘
```

- 5 个数字用 `.monospacedDigit()`。
- 分按键档：`合计/左/右/中`，**当 other>0 时追加「其它」档**，保证侧键点击在 UI 可见、且「合计 = 各档之和」自洽。
- **空状态**：无数据时五档显示 `0`（语义明确）；趋势/热力图显示占位文案「开始点击后这里会出现统计」。

---

## 10. 图表：趋势与热力图

- **趋势**（Tab：趋势）：Swift Charts 折线/柱状，粒度「近 24 小时 / 7 天 / 30 天 / 12 个月」，可叠加左/右/中三条线。
- **热力图**（Tab：热力图）：**7×24「星期 × 小时」网格**（GitHub 贡献图风格），数据源为 §8 的 `local_weekday × local_hour` 聚合。
  - **区分两种空格**：「真实 0 点击」用最浅色块；「该格尚无采集数据/App 当时未运行」用留白/灰格 + 图例说明，并标注采集起始日期。避免把「从没点过」与「没在统计」混淆（关系到 R4 的正确解读）。

---

## 11. 数据导出

- **ExportService** 读全表或选定区间，经 `NSSavePanel` 选保存位置。
- **CSV**：表头 `hour_iso8601,local_hour,local_weekday,button,count`；另可出「按天汇总」CSV。
- **JSON**：`{ exported_at, timezone, schema_version, records:[{hour, local_hour, local_weekday, left, right, middle, other}] }`。
- 用户主动触发，绝不自动外传。

---

## 12. 开机自启与崩溃自动拉起

**默认走现代 API `SMAppService.agent(plistName:)`**（macOS 13+），它注册的 agent「与 launchd plist 注册的行为一致，可设 RunAtLoad / KeepAlive」——**能同时做自启与崩溃守护**。

- plist 随 App bundle 分发，放 `Contents/Library/LaunchAgents/com.liuzhuo.clickpulse.plist`，系统托管（不落 `~/Library/LaunchAgents`）：

```xml
<key>Label</key>          <string>com.liuzhuo.clickpulse</string>
<key>RunAtLoad</key>      <true/>
<key>KeepAlive</key>
<dict><key>SuccessfulExit</key><false/></dict>   <!-- 崩溃/被 kill 才拉起；主动退出(exit 0)不拉起 -->
<key>ThrottleInterval</key> <integer>10</integer>
```

- 注册：`SMAppService.agent(plistName: "com.liuzhuo.clickpulse.plist").register()`；关闭守护用 `.unregister()`。
- **回退路径**：若 SMAppService 不可用，再手写 `~/Library/LaunchAgents/...plist` + `launchctl bootstrap gui/<uid>` / `bootout`。**注明 macOS 26 已知回归**：`bootout` 后 `bootstrap` 可能无法重新注册，workaround 为 `launchctl kickstart -k`。

### 单实例仲裁（避免与 KeepAlive 打架）

- **launchd/SMAppService 托管的实例 = 权威实例，永不主动自杀。**
- 用户手动双击产生的多余实例：检测到已有实例 → 把已有实例面板带到前台 → 自身 **`exit(0)` 干净退出**（不触发 KeepAlive）。
- 绝不让权威实例用非 0 退出或被信号杀来「让位」（会被 KeepAlive 反复拉起，形成被 ThrottleInterval 节流的循环）。

---

## 13. 代码签名策略与身份生命周期

**零维护的关键是「签名身份固定不变」**（TCC 授权绑定 designated requirement，由签名身份决定）。

### 签名

- 用**一次性创建、长期复用的自签名 Code Signing 证书**（0 元），**有效期设很长（如 100 年，避免到期换身份）**，构建脚本自动创建并复用。
- 不需要 $99/年 Apple 开发者账号（其价值在公证 + 对外分发，本工具纯本地自用不涉及）。

### 会触发「重新授权」的条件（诚实列明）

TCC 同时绑定**签名身份 + bundle id + on-disk 路径**，任一改变都视为新 App、授权丢失：

1. 签名身份变（换证书/私钥丢失/换机重建）；
2. bundle id 变 —— 已锁死 `com.liuzhuo.clickpulse`，不变；
3. `.app` 路径变 —— 已锁定 `/Applications/ClickPulse.app`，不移动；
4. 证书过期 —— 已设超长有效期规避。

命中时**统计会中断到用户重新授权为止**（与「避免遗失」存在张力，§14.2 用图标状态 + 通知让用户尽快察觉）。

### 身份存续（保证「换机/重装」也能恢复）

- 证书 + 私钥导出 `.p12` 妥善备份（构建脚本提供导出命令）。
- 构建脚本内置 **`resign.command`「恢复/重签」**：从 `.p12` 导入证书 → 重新签名 → 重装到 `/Applications`。换机/系统重装后由 AI 在会话内代跑（或用户双击）。
- 诚实标注：若身份**彻底丢失**，代价不是「偶尔点一次授权」，而是需重新签名 + 重新授权——这超出纯「零维护」，属一次性恢复成本。

### Gatekeeper

- **本机编译产物默认不带 `com.apple.quarantine`，双击直接运行，不触发 Gatekeeper 首次拦截**（这是本地编译方案的优势）。
- 反例边界：一旦 `.app` 经下载/压缩/AirDrop 传输会被打 quarantine，首次打开被拦（「身份不明的开发者/已损坏」）。处理：`xattr -dr com.apple.quarantine /Applications/ClickPulse.app` 或右键打开/系统设置「仍要打开」。

---

## 14. 健壮性、并发与故障可见

### 14.1 并发同步（防丢计数）

- `ClickCounter` 用一把 `os_unfair_lock`（或 `OSAllocatedUnfairLock`）保护 `{left,right,middle,other}` 四个计数器；回调里加锁自增。
- **整点翻篇 / flush**：用「读取并清零(swap 到 0)」原子地取出旧值再 upsert，确保翻篇瞬间到达的点击归属正确小时、不丢失。

### 14.2 故障对用户可见（闭环 R7「避免遗失」）

- **菜单栏图标状态**：tap 失效 / 授权丢失 / 重建连续失败时，图标变灰 + 感叹号 badge，让不懂代码的用户一眼看出「没在统计了」。
- 授权被撤销时，除停止外**主动弹一次系统通知（`UNUserNotification`）**引导重新授权，而不是默默退回「面板里才看得到」的引导态。
- tap 连续重建失败 N 次 → 降级提示文案 + 图标异常态。

### 14.3 EventTap 自愈

- 回调捕获 `tapDisabledByTimeout/ByUserInput` 立即 `CGEvent.tapEnable(enable:true)`。
- 每 30–60 秒 `CGEventTapIsEnabled` 检查，失效则重建。「非 nil 的 tap 不等于健康的 tap」。

### 14.4 休眠/唤醒

- 订阅 `NSWorkspace.willSleepNotification`/`didWakeNotification`：睡前 flush；**唤醒后立即**（不等 Timer）健康检查/重建 tap，并按当前本地墙钟重算 `hour_ts`/`local_hour`/`local_weekday`。

### 14.5 时钟回拨 / 时区变更（caveat，影响有界）

- 点击始终按**当前**墙钟入桶，纯加法 upsert，故「总」恒正确；时钟回拨/NTP 校正仅可能让趋势/热力图在罕见窗口分布略偏。可用 `ContinuousClock` 辅助检测墙钟非预期回退并记日志。
- 时区变更（跨时区移动）：旧数据按旧本地基准、新数据按新基准，`meta` 记 `timezone`/`tz_changed_at`；仅影响切换点附近少数桶，不丢数据。中国不实行 DST，春跳/秋回不适用。

### 14.6 数据安全

- 退出/休眠前强制 flush；WAL + 事务；迁移见 §7。

---

## 15. 隐私

- 纯本地 SQLite；**不链接任何网络库、不发任何请求**；无账号、无遥测。
- 只记录「点击次数 + 小时时间 + 按键类别 + 本地小时/星期」，不记录坐标、窗口、内容。
- 开源；面板内提供「打开数据目录 / 导出 / 清空」，数据目录即 `~/Library/Application Support/com.liuzhuo.clickpulse/`。

---

## 16. 资源占用预期

- 内存：纯菜单栏 SwiftUI 进程基线约 **10–80MB**（远低于 Electron 的 100MB+）。
- CPU（空闲、面板未开）：近 **0%**（人类点击频率；不监听 mouseMoved）。
- 磁盘：每年数 MB。

---

## 17. 交付物与用户操作路径（零代码维护）

**交付物**：源码（Xcode 工程）+ 可双击的构建脚本 + 安装说明。

**用户操作路径**（加粗为用户亲自做）：

1. **安装一次 Xcode**（App Store 免费，约 15GB）。说明：本项目是 SwiftUI App，构建确需完整 Xcode（独立 Command Line Tools 的 SDK 不足以可靠编译 SwiftUI GUI）。
2. AI 提供全部源码 + `scripts/build.command`（建/复用自签名证书 → `xcodebuild` 编译 → 签名 → 装到 `/Applications`）。
3. **双击 `build.command`** 运行（或由 AI 在会话内代跑），得到 `/Applications/ClickPulse.app`。
4. **双击运行**；首次弹授权时**到系统设置「输入监控」打开开关**。
5. 之后开机自启 + 崩溃自动拉起，日常零维护。

> 诚实标注：首次「构建 + 签名 + 装 LaunchAgent」对非程序员是**一次性门槛**；「零维护」覆盖装好后的日常运行，**不覆盖**需要重新构建/重签的场景（系统大升级需重编、换机需从 `.p12` 恢复）——这些由 AI 介入或双击 `resign.command` 完成。

---

## 18. 工作量估算

AI 辅助下约 **35–50 人时**（含本次新增的并发同步、迁移、自愈可见、签名存续）。对用户即「等做完」。最易踩坑：EventTap 自愈、并发同步、LaunchAgent + 单实例 + 退出语义、签名身份存续。

---

## 19. 风险、缓解与不确定点

| 风险 | 缓解 |
|---|---|
| 新系统收紧权限模型 | 按「需要权限」兜底，最坏多一次授权引导 |
| TCC 绑定签名身份/bundle id/路径 → 授权失效 | 固定自签名身份（超长有效期）+ 锁死 bundle id + 锁定 `/Applications` 路径 + 运行期健康检查 + 重建 |
| **签名身份彻底丢失（证书/私钥丢、换机、重装）** | `.p12` 备份 + `resign.command` 恢复重签；标注此为一次性恢复成本而非零维护 |
| CGEventTap 被静默禁用 | 回调自愈 + 定时检查重建 + 唤醒立即重建 |
| 故障静默（纯菜单栏看不到） | 图标异常态 + 系统通知（§14.2）|
| LaunchAgent 与手动启动双实例 | 单实例仲裁：托管实例权威、手动实例 `exit(0)` 让位 |
| macOS 26 `bootstrap/bootout` 回归 | 默认走 SMAppService.agent；回退路径用 `launchctl kickstart -k` |
| 计数并发丢失 | `os_unfair_lock` + swap 翻篇 |
| `.app` 经传输被打 quarantine | `xattr -dr com.apple.quarantine` 或右键打开 |
| Gatekeeper 首次拦截 | 本地编译产物默认无 quarantine，主路径不触发 |

**不确定点（深度研究 caveats）**：

1. 未在 macOS 26 真机实测，结论为「API 延续性 + 最佳实践」推断。
2. 免费自签名是否完全消除 TCC 抖动、KeepAlive/SMAppService.agent 在自签名下重启可靠性，存在残留不确定（最坏：命中 §13 触发条件时统计中断到重新授权）。
3. 参考开源项目只证明「能做」，均不含完整功能集（时段热力图/CSV 导出/五档/小时粒度/并发同步），需从零实现。

---

## 20. 工程结构与构建

### 文件树

```
ClickPulse/
├─ ClickPulse.xcodeproj
├─ ClickPulse/
│  ├─ App/         ClickPulseApp.swift, AppDelegate.swift
│  ├─ Capture/     EventTapController.swift
│  ├─ Aggregate/   ClickCounter.swift            (os_unfair_lock + swap)
│  ├─ Store/       ClickStore.swift, Migrations.swift
│  ├─ Stats/       StatsProvider.swift           (@Observable)
│  ├─ UI/          StatusItemManager.swift, IconStateController.swift,
│  │               DashboardView.swift, TrendView.swift, HeatmapView.swift,
│  │               ExportView.swift, PermissionView.swift
│  ├─ System/      PermissionManager.swift, LaunchAgentService.swift, ExportService.swift
│  ├─ Resources/   Assets.xcassets
│  ├─ Info.plist                                  (LSUIElement = true)
│  ├─ ClickPulse.entitlements                     (App Sandbox 关闭)
│  └─ LaunchAgents/com.liuzhuo.clickpulse.plist   (打包进 Contents/Library/LaunchAgents)
├─ scripts/
│  ├─ build.command   建/复用自签名证书 → xcodebuild → codesign → 装到 /Applications（可双击）
│  └─ resign.command  从 .p12 恢复证书并重签（换机/重装用）
└─ docs/
```

### 依赖与构建

- 依赖：GRDB.swift（SPM 依赖；若要求零第三方，退化为系统 `sqlite3` 薄封装）。Swift Charts、AppKit、ServiceManagement 为系统框架。
- 部署目标：`MACOSX_DEPLOYMENT_TARGET = 14.0`。
- 构建：`xcodebuild -project ClickPulse.xcodeproj -scheme ClickPulse -configuration Release -derivedDataPath build`，产物 `.app` 用固定自签名证书 `codesign`，拷到 `/Applications`。
- `build.command` 封装上述全流程，幂等、可双击。

---

## 21. 参考实现与来源

- KeyCount：https://github.com/MarcusDelvecchio/KeyCount
- Keys vs Clicks：https://github.com/GeekyAnts/keysvsclicks
- CGEventSupervisor：https://github.com/stephancasas/CGEventSupervisor
- EventTapper：https://github.com/usagimaru/EventTapper
- Apple — CGEvent.tapCreate：https://developer.apple.com/documentation/coregraphics/cgevent/1454426-tapcreate
- Apple — CGRequestListenEventAccess：https://developer.apple.com/documentation/coregraphics/cgrequestlisteneventaccess
- Apple — SMAppService（含 `agent(plistName:)`）：https://developer.apple.com/documentation/servicemanagement/smappservice
- Apple 论坛 — TCC 与稳定签名（thread 730043）：https://developer.apple.com/forums/thread/730043
- Apple 论坛 — Accessory vs Prohibited 与 tap 失败（thread 758554）：https://developer.apple.com/forums/thread/758554
- Hammerspoon 权限错乱 bug #3301：https://github.com/Hammerspoon/hammerspoon/issues/3301
