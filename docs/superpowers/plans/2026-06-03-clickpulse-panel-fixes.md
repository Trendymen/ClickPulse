# ClickPulse 面板修复 Implementation Plan

> **For agentic workers:** 本计划由 Workflow 工具编排执行（见 spec C 节）。步骤用 checkbox（`- [ ]`）跟踪。
>
> **测试豁免**：按用户全局规则第 11 节，本计划不含程序化测试步骤。验证方式 = `vscode-mcp-server` diagnostics + `build.command` 构建 + 面板数值人工核对。

**Goal:** 修复 ClickPulse 菜单栏面板的两个问题——大数字溢出/折行、分按键统计加固验证。

**Architecture:** 新增纯函数 `ClickFormat` 做展示格式化（千分位 / 紧凑单位 / locale 感知），`DashboardView.cell` 接入并加缩字兜底；分按键统计的展示层修复已在 `78d149f` 落地，本计划对其做静态核查 + 构建后数值核对，确认导出/热力图/实时更新不受影响。

**Tech Stack:** Swift / SwiftUI，`Foundation` 的 `FormatStyle`（`.number.notation(.compactName)`），GRDB（只读核查）。

关联 spec：`docs/superpowers/specs/2026-06-03-clickpulse-panel-fixes-design.md`

## 文件结构

- **Create**：`ClickPulse/UI/ClickFormat.swift` —— 纯函数数字格式化，单一职责。
- **Modify**：`ClickPulse/UI/DashboardView.swift` —— `cell(_:_:)` 接入 `ClickFormat.display` + `.lineLimit(1).minimumScaleFactor(0.5)`。
- **核查（只读为主）**：`ClickPulse/UI/ExportView.swift`、`ClickPulse/Store/ClickStore.swift`（`allRows()` / `heatmap()`）、`ClickPulse/Stats/StatsProvider.swift`（`bump()` / `refresh()`）。

---

### Task 1: 大数字显示

**Files:**
- Create: `ClickPulse/UI/ClickFormat.swift`
- Modify: `ClickPulse/UI/DashboardView.swift`（`cell(_:_:)` 函数）

- [ ] **Step 1: 新建 ClickFormat.swift**

```swift
import Foundation

/// 面板数字的展示格式化：日常千分位、超大数紧凑单位，跟随系统 locale。
enum ClickFormat {
    /// < 100 万：千分位（locale 感知，如 33,970）；
    /// ≥ 100 万：紧凑单位（中文系统 123万 / 1.2亿；英文系统 1.2M），保留 0–1 位小数。
    static func display(_ n: Int) -> String {
        if n < 1_000_000 {
            return n.formatted()
        }
        return n.formatted(
            .number
                .notation(.compactName)
                .precision(.fractionLength(0...1)))
    }
}
```

- [ ] **Step 2: DashboardView.cell 接入格式化 + 缩字兜底**

把 `cell(_:_:)` 从：

```swift
    private func cell(_ label: String, _ n: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(n)").font(.title3).monospacedDigit().fontWeight(.semibold)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
```

改为：

```swift
    private func cell(_ label: String, _ n: Int) -> some View {
        VStack(spacing: 2) {
            Text(ClickFormat.display(n))
                .font(.title3).monospacedDigit().fontWeight(.semibold)
                .lineLimit(1).minimumScaleFactor(0.5)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
```

- [ ] **Step 3: diagnostics 检查**

用 `mcp__vscode-mcp-server__get_diagnostics_code` 检查 `ClickPulse/UI/ClickFormat.swift` 与 `ClickPulse/UI/DashboardView.swift`。
预期：`No issues found`。若 `.precision(.fractionLength(0...1))` 报类型/重载错误，改用 `.precision(.fractionLength(1))`（固定 1 位）作为退路。

- [ ] **Step 4: Commit**

```bash
git add ClickPulse/UI/ClickFormat.swift ClickPulse/UI/DashboardView.swift
git commit -m "feat(panel): 大数字千分位+紧凑单位显示，缩字防溢出

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: 分按键统计加固核查

展示层修复已在 `78d149f` 落地。本任务做静态核查，确认其余路径不受「比例摊派」历史 bug 影响。**默认只读核查；仅当发现真实问题时才改代码。**

**Files（核查对象）:**
- `ClickPulse/UI/ExportView.swift`、`ClickPulse/Store/ClickStore.swift`、`ClickPulse/Stats/StatsProvider.swift`、`ClickPulse/UI/DashboardView.swift`

- [ ] **Step 1: 核查导出**

读 `ClickPulse/UI/ExportView.swift` 与 `ClickStore.allRows()`。确认：导出取 `store.allRows()`（按 `button` 分列聚合的 `HourRow`），不经过 `DashboardView` 的展示层摊派。
预期结论：导出 CSV/JSON 本就是真实分按键，未受影响。

- [ ] **Step 2: 核查热力图**

读 `ClickStore.heatmap()`。确认：`SELECT ... SUM(count) ... GROUP BY local_weekday, local_hour`，聚合所有按键、与分按键维度无关。
预期结论：热力图不受影响。

- [ ] **Step 3: 核查 bump ↔ refresh 一致性**

读 `StatsProvider.bump()` 与 `refresh()`。确认：
- `bump()` 对 `hourBy/dayBy/weekBy/monthBy/byButton` 各 +1，与合计 `hour/day/week/month/total` 同步；
- `refresh()` 每时段用 `sumByButton(since:)` 真实查询覆盖整个 snapshot；
- 跨小时/跨天时，乐观 `bump` 仍计入旧时段，下次 `refresh`（5s）真实查询校正——与「合计」字段同逻辑，可接受。
预期结论：一致，无双算/漏算。

- [ ] **Step 4: 核查「其它」按键判断**

读 `DashboardView.filters`。确认：用全局 `stats.snapshot.byButton[.other] > 0` 决定是否显示「其它」tab，`byButton` 已是全局真实分按键。
预期结论：正确。

- [ ] **Step 5: 汇总核查报告（仅发现问题才改代码）**

输出 1–4 项的核查结论。若全部符合预期 → 本任务无代码改动，跳过 commit。若发现真实 bug → 给出最小修复 + diagnostics 检查 + commit：

```bash
git add <改动文件>
git commit -m "fix(panel): <核查发现的问题>

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: 构建与数值核对（验收）

**Files:** 无（运行脚本 + 人工核对）

- [ ] **Step 1: 构建安装**

```bash
pkill -f "Applications/ClickPulse.app/Contents/MacOS" 2>/dev/null; bash scripts/build.command
```
预期：`完成: /Applications/ClickPulse.app`，exit 0（CoreSimulator out-of-date 警告无害）。

- [ ] **Step 2: 面板数值人工核对**

打开菜单栏面板，逐项确认 spec 验收标准：
- 数字在万/百万/千万级单行显示，不折行不溢出（紧凑单位生效）；
- 切「中键/左键/右键」，时/日/周/月/总 为真实次数，「时」反映当前小时；
- 「合计」== 左 + 右 + 中（+ 其它）；
- 导出 CSV/JSON 与热力图数值正常。

---

## 验收标准（对应 spec）

- [ ] 面板数字在 1 / 千 / 万 / 百万 / 千万级下均单行显示，不折行不溢出。
- [ ] 切按键，各时段显示真实次数；「时」反映当前小时真实点击。
- [ ] 合计 == 各按键之和。
- [ ] 导出 CSV/JSON 与热力图数值正确。
- [ ] diagnostics 干净；`build.command` 构建 exit 0。
