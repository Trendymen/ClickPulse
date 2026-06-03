# ClickPulse 面板修复设计

- 日期：2026-06-03
- 状态：已批准（brainstorming）
- 关联代码：`ClickPulse/UI/DashboardView.swift`、`ClickPulse/Stats/StatsProvider.swift`、新增 `ClickPulse/UI/ClickFormat.swift`

## 背景

ClickPulse 菜单栏面板的数字区（`DashboardView`）有两个问题：

1. **大数字 UI 不自适应**：面板固定宽 360pt，「时/日/周/月/总」5 格均分（每格约 66pt），数字字号固定 `.title3` 且无缩放。数字超过约 6 字符（百万级）就会折行/溢出，整排参差不齐。
2. **分按键统计不准**：`DashboardView` 用「全局比例摊派」估算分按键值 —— `该时段总数 × 该按键全局占比`。导致中键这类低频按键：「时」几乎恒为 0（占比极小，四舍五入归零）、「日/周/月/总」是摊派近似而非真实次数。底层 `click_hourly` 表本就按 `button` 分列存储，有能力查真值。

> 注：问题②的展示层已先行修复（改为每时段真实 `sumByButton(since:)` 查询），本设计将其纳入并加固验证，而非推倒重来。

## 目标 / 非目标

**目标**
- 大数字在任何量级下都不折行、不溢出，可读性好。
- 分按键统计在所有时段（时/日/周/月/总）显示真实次数，并验证导出 / 热力图 / 实时更新一致。

**非目标**
- 不做面板宽度自适应（保持固定 360pt 布局，A 的阈值 + 缩字策略已足够）。
- 不改数据采集层（`CGEventTap`、`ClickStore` schema 不动）。
- 不做与本目标无关的重构。

## A. 大数字显示

新增纯函数格式化 `ClickPulse/UI/ClickFormat.swift`：

```swift
enum ClickFormat {
    static func display(_ n: Int) -> String {
        if n < 1_000_000 { return n.formatted() }            // 千分位，跟随 locale：33,970
        return n.formatted(
            .number.notation(.compactName)                   // 紧凑：123万 / 1.2亿 / 1.2M
                .precision(.fractionLength(0...1)))
    }
}
```

| 量级 | 规则 | 例子 |
|---|---|---|
| `n < 1_000_000` | 千分位完整 `n.formatted()` | `33,970` |
| `n ≥ 1_000_000` | 紧凑单位 `.notation(.compactName)`，保留 0–1 位小数 | `123万` / `1.2亿` |
| 任何情况（兜底） | 数字 Text 加 `.lineLimit(1).minimumScaleFactor(0.5)` | 放不下自动缩字，绝不折行 |

- 阈值 `1_000_000`：`999,999`（7 字符）配缩字仍清晰；破百万切紧凑后永远 ≤5 字符。
- **默认紧凑单位跟随系统语言**（`.compactName` 是 locale 感知：中文系统→万/亿，英文系统→K/M）。
- 接入点：`DashboardView.cell(_:_:)` 内 `Text("\(n)")` → `Text(ClickFormat.display(n))`，并补 `.lineLimit(1).minimumScaleFactor(0.5)`。

## B. 分按键统计加固 + 验证

**现状（已实现）**
- `StatsSnapshot` 新增 `hourBy/dayBy/weekBy/monthBy` 各时段真实分按键计数；`byButton` 保留为全局（= 总）分按键，沿用旧字段以不破坏现有引用与测试。
- `StatsProvider.refresh()` 每时段调 `sumByButton(since:)`，合计 = 各按键之和。
- `StatsProvider.bump()` 对每时段的 `byButton` 同步 +1（实时乐观更新）。
- `DashboardView` 删除 `scaled()` 摊派逻辑，改读真实 by 字典。

**加固核查清单（workflow 阶段执行）**
1. **导出**：`ClickStore.allRows()` 本就按 `button` 分列 → 确认 CSV/JSON 不受摊派影响（展示层 bug 不波及导出）。
2. **热力图**：`heatmap()` 是全按键 `SUM(count)` → 确认与分按键无关、不受影响。
3. **bump ↔ refresh 一致性**：核查跨小时/跨天时 `bump()` 不双算/漏算（与合计同逻辑，下次 `refresh()` 真实查询校正）。
4. **「其它」按键**：`DashboardView.filters` 用全局 `byButton[.other] > 0` 判断是否显示「其它」tab → 确认正确。
5. **构建后数值核对**：合计 == 左 + 右 + 中 + 其它；各按键 时/日/周/月/总 与历史分布一致。

**测试**：默认暂不加程序化测试（按用户测试豁免）。现有 `StatsProviderTests` 引用的字段（`hour`/`day`/`total`/`byButton`）均保留，不受本次改动影响。

## C. workflow 编排（多 agent 修复）

改动集中、规模小，串行 pipeline，无并行文件写冲突：

1. **实现 agent**：写 A（新增 `ClickFormat` + 接入 `DashboardView` + 缩字兜底），做 diagnostics 检查。
2. **核查 agent**：跑 B 的 1–4 项静态核查（以只读核查为主），输出确认报告 + 必要小修。
3. **审查 agent**（code-reviewer）：审 A 改动的正确性与回归。
4. **主线程**：跑 `scripts/build.command` 构建 + 数值核对（B-5）。

文件归属：A 写 `ClickFormat.swift` / `DashboardView.swift`；B 以核查 `ClickStore.swift`、`ExportView`、`heatmap` 为主。

## 验收标准

- [ ] 面板数字在 1 / 千 / 万 / 百万 / 千万级下均单行显示，不折行不溢出。
- [ ] 切「中键 / 左键 / 右键」，时/日/周/月/总 显示真实次数；「时」反映当前小时真实点击。
- [ ] 合计 == 各按键之和。
- [ ] 导出 CSV/JSON 与热力图数值正确（不受本次改动影响）。
- [ ] diagnostics 干净；`build.command` 构建 exit 0。
