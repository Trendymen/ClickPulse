# ClickPulse 设计规格

- **日期**：2026-06-02
- **状态**：已定稿（待用户复核）
- **目标平台**：macOS 26（Apple Silicon / arm64）
- **技术栈**：原生 Swift / SwiftUI + AppKit
- **交付模式**：AI 全权代写并维护，用户零代码维护（只负责安装/授权/使用）

---

## 1. 概述与目标

ClickPulse 是一个**专注于鼠标点击统计**的 macOS 菜单栏常驻小工具。它在后台全局统计鼠标点击次数，菜单栏只显示一个图标，点开面板展示**时 / 日 / 周 / 月 / 总**五档点击数，并提供历史趋势、分时段热力图与数据导出。强调极轻量、长期稳定、纯本地隐私。

**核心目标**：

1. 全局、持续、低开销地统计系统级鼠标点击。
2. 菜单栏图标 + 面板，清晰展示五档计数与分按键明细。
3. 历史趋势 + 分时段热力图 + CSV/JSON 导出。
4. 开机自启 + 崩溃/被杀自动拉起，最大程度避免统计遗失。
5. 纯本地、开源、无账号、零联网上报。
6. 由 AI 全权实现与维护，用户不需要懂代码。

---

## 2. 需求（固定）

| 编号 | 需求 |
|---|---|
| R1 | 全局监听系统级鼠标点击，统计左 / 右 / 中键，且可**分按键查看**各自次数 |
| R2 | 菜单栏只显示一个图标；点开面板显示 **时（当前小时）/ 日（今日）/ 周（本周）/ 月（本月）/ 总（累计）** 五档点击数 |
| R3 | 历史记录与趋势视图 |
| R4 | 分时段点击热力图（一天里哪个时段最活跃） |
| R5 | 导出数据为 CSV / JSON |
| R6 | 按「小时」粒度本地持久化，五档统计 + 热力图 + 历史全部从这一份数据派生 |
| R7 | 开机自启 + 崩溃 / 被杀后自动拉起 |
| R8 | 极轻量，可 7×24 常驻 |
| R9 | 隐私优先：开源、纯本地、无账号、零联网上报 |
| R10 | 全局监听权限的申请 + 检测 + 引导用户开启 |

**约定**：

- 周起点为**周一**。
- 计数只取 `*MouseDown`（按下即一次），不取 `*MouseUp`，避免双倍计数。
- 不监听 `mouseMoved`（高频，浪费 CPU/电）。
- 时间以**本地时区**对齐到整点存储。

---

## 3. 非目标（YAGNI）

- 不统计键盘按键、不统计鼠标移动距离、不统计带宽（与 WhatPulse 区分，保持专注）。
- 不做云同步、不做账号体系、不做联网上报。
- 不做屏幕位置热力图（仅做「时段」热力图）。
- 首版不做实时 CPM（每分钟点击数）等速率指标（用户未选）。

---

## 4. 技术选型与依据

选定**原生 Swift/SwiftUI + AppKit**，依据来自三方独立方案对比 + 一次深度研究（6 角度、25 源、对抗式验证）：

- **AI 代写成功率最高**：CGEventTap 是 macOS 标准低层 API，且有 KeyCount、Keys vs Clicks、CGEventSupervisor、EventTapper 等真实开源样板可参考。
- **资源最轻、面板体验最好、长期最可靠**：相比 Hammerspoon（40–80MB 宿主税 + 偶发权限错乱 bug #3301）与 Electron（100MB+ 内存与体积），原生最适合 7×24 常驻的单一功能工具。
- **权限模型清晰稳定**：被动 `.listenOnly` 的 CGEventTap 对应「**输入监控**」权限（非「辅助功能」），是 10.15 → 26 一路延续的稳定模型。
- 被排除项：Tauri/Rust 鼠标监听插件极不成熟；Python/pynput 在 macOS 上未经证实。

---

## 5. 总体架构

纯菜单栏 App（`LSUIElement = true`，Dock 无图标，激活策略 **Accessory** —— 绝不用 `LSBackgroundOnly`/Prohibited，后者会引入事件 tap 创建失败路径）。单进程分层：

```
捕获层  EventTapController   ── 创建/维护 CGEventTap(.listenOnly)，回调只做内存自增 + 健康自愈
聚合层  ClickCounter         ── 内存累加 {left,right,middle,other} 当前小时计数，低频 flush
持久层  ClickStore           ── SQLite，按小时×按键存事实表，增量 upsert + 聚合查询
派生层  StatsProvider        ── @Observable，把查询结果转 ViewModel 供 UI 订阅
UI 层   StatusItemManager + SwiftUI 视图（Dashboard/Trend/Heatmap/Export/Permission）
系统层  PermissionManager / LaunchAgentInstaller / ExportService
```

**关键性能原则**：事件回调路径极短（一次原子自增），落库/查询/绘图全部异步、低频，保证常驻 CPU 近零。

---

## 6. 全局点击监听与权限模型

### 监听

- API：`CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask, callback:, userInfo:)`。
- 事件掩码：`leftMouseDown | rightMouseDown | otherMouseDown`。
- 分按键：`otherMouseDown` 读 `mouseEventButtonNumber`，值为 2 记为中键，其它（侧键 3/4…）归为 `other`。
- 回调：仅对对应按键内存计数器 +1，`return Unmanaged.passUnretained(event)`（监听模式原样放行）。

### 权限（「输入监控」）

- `.listenOnly` 对应 **Input Monitoring**（TCC 服务 `kTCCServiceListenEvent`）。
- 启动时 `CGPreflightListenEventAccess()` 静默检测（不弹窗）。
- 未授权：显示引导卡片 + 按钮，调 `CGRequestListenEventAccess()` 触发系统弹窗，并用 `x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent` 直达系统设置面板。
- 授权变更后通常需重建 tap 才生效，授权成功后重启 tap。

### 诚实标注

纯鼠标监听是否「一定」需要授权，官方未写死。按「需要权限」设计兜底：真不需要则零摩擦，需要则引导已就绪。

---

## 7. 数据存储设计

唯一事实表，按「小时 × 按键」存储，所有视图派生，不冗余：

```sql
CREATE TABLE click_hourly (
    hour_ts INTEGER NOT NULL,   -- 本地时区对齐到整点的 Unix 秒
    button  INTEGER NOT NULL,   -- 0=left 1=right 2=middle 3=other
    count   INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (hour_ts, button)
);
CREATE INDEX idx_click_hour ON click_hourly(hour_ts);

CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);  -- schema 版本、时区等
```

- 写入低频：点击只改内存，按 ~30 秒 / 整点翻篇 / 退出 / 休眠前增量 upsert：
  `INSERT INTO click_hourly(...) VALUES(...) ON CONFLICT(hour_ts,button) DO UPDATE SET count = count + excluded.count;`
- 体量：一天最多 24×4=96 行，一年约 3.5 万行，毫秒级查询，磁盘每年数 MB。
- 引擎：**GRDB（SQLite 封装）** 为首选；若要求零第三方依赖，退化为系统 `sqlite3` C API 薄封装（约 +150 行）。两者均纯本地。
- 安全：WAL 模式 + 事务写入；退出/休眠前强制 flush。

---

## 8. 派生统计

全部从 `click_hourly` 用一句 SQL 聚合：

| 视图 | 取数 |
|---|---|
| 时 | `hour_ts = 本小时起点` |
| 日 | `hour_ts >= 今日 0 点` |
| 周 | `hour_ts >= 本周一 0 点`（`Calendar.firstWeekday = 2`） |
| 月 | `hour_ts >= 本月 1 号 0 点` |
| 总 | 全表 `SUM(count)` |
| 分按键 | 上述任意区间加 `GROUP BY button` |
| 趋势 | `GROUP BY` 截断到天/周/月的时间序列 |
| 热力图 | `GROUP BY (hour_ts/3600)%24`（可扩展为 星期×小时 矩阵） |

---

## 9. 菜单栏与面板 UI

- **菜单栏**：仅一个图标（SF Symbol `cursorarrow.click`，模板图标自适配深浅色），不显示数字。
- **面板**：点击图标弹出 `NSPopover`（内嵌 SwiftUI），点外部/再点图标收起。选 NSStatusItem + NSPopover 而非 `MenuBarExtra`，换取对定位/收起/刷新的最佳可控性。
- **布局**：

```
┌───────────────────────────────────┐
│  [ 合计 | 左键 | 右键 | 中键 ]      │  ← 分按键切换（满足 R1“分开看”）
├───────────────────────────────────┤
│   时      日     周     月     总    │  ← 5 个等宽数字，随上方切换联动
├───────────────────────────────────┤
│  [ 趋势 | 热力图 | 导出 | 设置 ]     │  ← 分段切换
│  … 对应内容 …                       │
└───────────────────────────────────┘
```

- 5 个数字用 `.monospacedDigit()`，避免数字跳动。
- 「合计/左键/右键/中键」分段控件一切换，下方五档随之显示该按键数据。

---

## 10. 图表：趋势与热力图

- **趋势**（Tab：趋势）：Swift Charts 折线/柱状，粒度切换「近 24 小时 / 7 天 / 30 天 / 12 个月」，可叠加左/右/中三条线对比。
- **热力图**（Tab：热力图）：**7×24 的「星期 × 小时」网格**（GitHub 贡献图风格），颜色深浅映射点击强度，一眼看出「周几的几点」最活跃。用 Swift Charts `RectangleMark` 或 SwiftUI `Grid` 手绘色块实现。

---

## 11. 数据导出

- **ExportService** 读全表或选定区间，经 `NSSavePanel` 让用户选保存位置。
- **CSV**：表头 `hour_iso8601,button,count`，每行一条小时记录；另可出「按天汇总」CSV。
- **JSON**：`{ exported_at, timezone, schema:"hourly_v1", records:[{hour, left, right, middle, other}] }`。
- 导出由用户主动触发，绝不自动外传。

---

## 12. 开机自启与崩溃自动拉起

用一个 LaunchAgent 同时管「自启」与「崩溃守护」：`~/Library/LaunchAgents/com.liuzhuo.clickpulse.plist`（bundle id 占位可改）。

```xml
<key>RunAtLoad</key>      <true/>
<key>KeepAlive</key>
<dict>
    <key>SuccessfulExit</key> <false/>   <!-- 崩溃/被 kill 才拉起；用户主动退出(exit 0)不拉起 -->
</dict>
<key>ThrottleInterval</key> <integer>10</integer>   <!-- 防崩溃风暴 -->
```

- `RunAtLoad` → 开机/登录自启；`KeepAlive{SuccessfulExit=false}` → 崩溃/被杀自动拉起，同时保证用户能正常退出。
- App 首次开启「守护」时自动写 plist 并 `launchctl bootstrap gui/<uid>`；菜单提供一键关闭（`bootout` + 删 plist）。
- 现代登录项也可用 `SMAppService.mainApp.register()`，但「崩溃自动拉起」仍需 LaunchAgent 的 KeepAlive，故以 LaunchAgent 为准。
- **单实例检测**：守护进程与手动双击可能并存，启动时用 `NSRunningApplication` 检测重复实例，多余实例自杀。

---

## 13. 代码签名策略

**零维护的关键是「签名身份固定不变」**，而非花钱：

- TCC 权限绑定到 App 的 designated requirement（由签名身份决定）。ad-hoc/免签名每次重编译换身份 → 系统遗忘授权 → 权限反复失效。
- 方案：**一次性创建、长期复用的自签名 Code Signing 证书**（0 元），构建脚本自动创建并复用；以后每次重编译都用同一证书签名 → 身份稳定 → 「输入监控」授权不反复失效。
- 不需要 $99/年 Apple 开发者账号（其价值在公证 + 对外分发，本工具纯本地自用不涉及）。
- 诚实标注：此结论基于 TCC 机制推断 + Apple 工程师「稳定签名能 radically 减少 TCC 抖动」的指引，未在 macOS 26 真机 100% 实测；最坏情况只是偶尔需重新点一次授权。

---

## 14. 健壮性与错误处理

- **CGEventTap 静默禁用自愈**：回调捕获 `tapDisabledByTimeout/ByUserInput` 立即 `CGEvent.tapEnable(enable:true)`；并用每 30–60 秒的低频 Timer 调 `CGEventTapIsEnabled` 检查，失效则重建整个 tap。「非 nil 的 tap 不等于健康的 tap」。
- **数据安全**：退出/休眠前强制 flush 内存计数；SQLite WAL + 事务；schema 带版本字段便于迁移。
- **权限丢失**：运行期轮询 preflight 状态，授权被撤销时优雅停止并回到引导态。

---

## 15. 隐私

- 纯本地 SQLite；**不链接任何网络库、不发任何请求**；无账号、无遥测。
- 只记录「点击次数 + 时间（小时粒度）+ 按键类别」，不记录坐标、窗口、内容。
- 开源；数据文件路径透明，面板内提供「打开数据目录 / 导出 / 清空」。

---

## 16. 资源占用预期

- 内存：纯菜单栏 SwiftUI 进程基线约 **10–80MB**（远低于 Electron 的 100MB+）。
- CPU（空闲、面板未开）：近 **0%**（点击是人类频率；不监听 mouseMoved）。
- 磁盘：每年数 MB，可忽略。

---

## 17. 交付物与用户操作路径（零代码维护）

**交付物**：源码 + 一键构建脚本（建/复用自签名证书 → 编译 → 打包 `.app` → 签名）+ 安装说明。

**用户操作路径**（加粗为用户亲自做的步骤）：

1. **安装一次 Xcode**（App Store 免费，约 15GB）——编译 Swift 的唯一门槛。
2. AI 提供全部源码 + 构建脚本。
3. 跑一次构建脚本（可由 AI 在会话内代跑），产出 `ClickPulse.app`。
4. **双击运行**；首次弹授权时**到系统设置「输入监控」打开开关**。
5. 之后开机自启 + 崩溃自动拉起，长期零维护。

---

## 18. 工作量估算

AI 辅助下约 **31–46 人时**（对用户而言是「等做完」）。最耗时/易踩坑三块：EventTap 静默禁用自愈、LaunchAgent + 单实例 + 退出语义、权限变更后 tap 重生效。

---

## 19. 风险、缓解与不确定点

| 风险 | 缓解 |
|---|---|
| 新系统收紧权限模型 | 已按「需要权限」兜底，最坏多一次授权引导 |
| TCC 与签名身份绑定导致授权失效 | 固定自签名身份 + 运行期健康检查 + 重建 |
| CGEventTap 被系统静默禁用 | 回调自愈 + 定时检查重建 |
| LaunchAgent 与手动启动双实例 | 启动时单实例自检 |
| 「打开输入监控面板」URL scheme 漂移 | 目标系统实测一次，跳不准给文字指引 |

**不确定点（来自深度研究 caveats）**：

1. 未在 macOS 26 真机实测，结论为「API 延续性 + 最佳实践」推断。
2. 免费自签名是否完全避免 TCC 抖动、KeepAlive 在自签名下重启可靠性，存在残留不确定（最坏：偶尔重新授权）。
3. 参考开源项目只证明「能做」，均不含完整功能集（时段热力图 / CSV 导出 / 五档统计 / 小时粒度），这些需从零实现。

---

## 20. 参考实现与来源

- KeyCount（Swift 输入统计菜单栏）：https://github.com/MarcusDelvecchio/KeyCount
- Keys vs Clicks（SwiftUI 本地点击/按键统计）：https://github.com/GeekyAnts/keysvsclicks
- CGEventSupervisor：https://github.com/stephancasas/CGEventSupervisor
- EventTapper：https://github.com/usagimaru/EventTapper
- Apple — CGEvent.tapCreate：https://developer.apple.com/documentation/coregraphics/cgevent/1454426-tapcreate
- Apple — CGRequestListenEventAccess：https://developer.apple.com/documentation/coregraphics/cgrequestlisteneventaccess
- Apple — SMAppService：https://developer.apple.com/documentation/servicemanagement/smappservice
- Apple 论坛 — TCC 与稳定签名（Quinn, thread 730043）：https://developer.apple.com/forums/thread/730043
- Apple 论坛 — Accessory vs Prohibited 与 tap 失败（thread 758554）：https://developer.apple.com/forums/thread/758554
- Hammerspoon 权限错乱 bug #3301：https://github.com/Hammerspoon/hammerspoon/issues/3301
