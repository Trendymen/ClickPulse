# ClickPulse 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现一个专注鼠标点击统计的 macOS 菜单栏 App（时/日/周/月/总五档 + 分按键 + 趋势 + 7×24 热力图 + CSV/JSON 导出 + 开机自启 + 崩溃自动拉起 + 纯本地隐私）。

**Architecture:** 纯菜单栏 App（LSUIElement/Accessory）。CGEventTap(.listenOnly) 全局监听点击 → 加锁内存计数(ClickCounter) → 定时增量 upsert 到 GRDB/SQLite 按小时事实表(ClickStore) → 派生层(StatsProvider, @Observable) → SwiftUI 面板(NSStatusItem+NSPopover)。SMAppService.agent 注册 LaunchAgent(KeepAlive) 实现自启+崩溃守护。固定自签名证书保证 TCC 授权稳定。

**Tech Stack:** Swift 5.10+ / SwiftUI + AppKit / GRDB.swift(SPM) / Swift Charts / ServiceManagement / XCTest。Xcode App target，部署目标 macOS 14.0，bundle id `com.liuzhuo.clickpulse`，安装路径 `/Applications/ClickPulse.app`。

**Spec:** `docs/superpowers/specs/2026-06-02-mouse-click-tracker-design.md`

---

## 约定（所有 Task 共享）

- **测试框架**：XCTest。纯逻辑测试用临时数据库/固定 `Calendar`（注入），不依赖真机权限/GUI。
- **TDD 循环**：写失败测试 → 跑确认失败 → 最小实现 → 跑确认通过 → commit。
- **系统/GUI 组件**（EventTap、菜单栏、SwiftUI、LaunchAgent）无法 unit test → 给完整实现 + **手动验证步骤**。
- **运行测试**：`xcodebuild test -project ClickPulse.xcodeproj -scheme ClickPulse -destination 'platform=macOS'`（下文简写 `RUN_TESTS`）。
- **MouseButton 编码**（贯穿全程）：`left=0, right=1, middle=2, other=3`。
- **本地星期编码**：周一=1 … 周日=7。

---

## Task 1: Xcode 工程脚手架

**Files:**
- Create: `ClickPulse.xcodeproj`（Xcode 新建 macOS App，SwiftUI 生命周期）
- Create: `ClickPulse/App/ClickPulseApp.swift`
- Create: `ClickPulse/App/AppDelegate.swift`
- Create: `ClickPulse/Info.plist`（`LSUIElement = true`）
- Create: `ClickPulse/ClickPulse.entitlements`（App Sandbox = NO）
- Create: `ClickPulseTests/`（XCTest target）
- Modify: 工程加 GRDB.swift 的 SPM 依赖（`https://github.com/groue/GRDB.swift`，"Up to Next Major" from 6.0.0）

- [ ] **Step 1: 用 Xcode 创建 App target**

在 `/Users/liuzhuo/webstorm_project/ClickPulse` 下用 Xcode 新建项目：macOS → App，Product Name `ClickPulse`，Team 暂留 None，Interface SwiftUI，Language Swift，Include Tests 勾选。把生成的 `ClickPulse.xcodeproj` 与 `ClickPulse/`、`ClickPulseTests/` 放在仓库根（与现有 `docs/` 同级）。

- [ ] **Step 2: 设为纯菜单栏 App + 关沙箱**

`ClickPulse/Info.plist` 增加：
```xml
<key>LSUIElement</key>
<true/>
```
`ClickPulse/ClickPulse.entitlements` 设为（不开沙箱）：
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
```
Build Settings：`MACOSX_DEPLOYMENT_TARGET = 14.0`，`PRODUCT_BUNDLE_IDENTIFIER = com.liuzhuo.clickpulse`，`INFOPLIST_KEY_LSUIElement = YES`。

- [ ] **Step 3: 替换 App 入口为 AppKit 驱动的菜单栏壳**

`ClickPulse/App/ClickPulseApp.swift`：
```swift
import SwiftUI

@main
struct ClickPulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }   // 纯菜单栏 App：无主窗口，菜单栏由 AppDelegate 装配
    }
}
```
`ClickPulse/App/AppDelegate.swift`（先放一个最小可见图标，后续 Task 接管）：
```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "cursorarrow.click", accessibilityDescription: "ClickPulse")
        statusItem = item
    }
}
```

- [ ] **Step 4: 加 GRDB 依赖**

Xcode → File → Add Package Dependencies → `https://github.com/groue/GRDB.swift` → 加到 ClickPulse target。

- [ ] **Step 5: 编译运行验证**

Run: 在 Xcode 运行（⌘R）。
Expected: Dock 无图标，**菜单栏右上角出现一个鼠标光标图标**，点击暂无反应。`RUN_TESTS` 能跑通空测试。

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: Xcode 菜单栏 App 脚手架 + GRDB 依赖 + 关沙箱"
```

---

## Task 2: MouseButton 与 TimeBucket（时间分桶，TDD）

**Files:**
- Create: `ClickPulse/Aggregate/MouseButton.swift`
- Create: `ClickPulse/Store/TimeBucket.swift`
- Test: `ClickPulseTests/TimeBucketTests.swift`

- [ ] **Step 1: 写失败测试**

`ClickPulseTests/TimeBucketTests.swift`：
```swift
import XCTest
@testable import ClickPulse

final class TimeBucketTests: XCTestCase {
    // 固定东八区日历，避免依赖运行环境时区
    private func cal(_ tzID: String = "Asia/Shanghai") -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: tzID)!
        c.firstWeekday = 2   // 周一
        return c
    }

    func test_localHourAndWeekday_areLocal_notUTC() {
        // 2026-06-01 14:30:00 Asia/Shanghai 是周一
        var comp = DateComponents()
        comp.year = 2026; comp.month = 6; comp.day = 1; comp.hour = 14; comp.minute = 30
        let date = cal().date(from: comp)!
        let b = TimeBucket.current(date: date, calendar: cal())
        XCTAssertEqual(b.localHour, 14)       // 本地 14 点，不是 UTC 6 点
        XCTAssertEqual(b.localWeekday, 1)     // 周一 = 1
    }

    func test_sunday_mapsTo7() {
        var comp = DateComponents()
        comp.year = 2026; comp.month = 6; comp.day = 7; comp.hour = 9   // 2026-06-07 是周日
        let date = cal().date(from: comp)!
        XCTAssertEqual(TimeBucket.current(date: date, calendar: cal()).localWeekday, 7)
    }

    func test_hourTimestamp_isStartOfLocalHour() {
        var comp = DateComponents()
        comp.year = 2026; comp.month = 6; comp.day = 1; comp.hour = 14; comp.minute = 59; comp.second = 59
        let date = cal().date(from: comp)!
        let b = TimeBucket.current(date: date, calendar: cal())
        // 整点应回到 14:00:00
        let expected = Int(cal().date(bySettingHour: 14, minute: 0, second: 0, of: date)!.timeIntervalSince1970)
        XCTAssertEqual(b.hourTimestamp, expected)
    }

    func test_startOfWeek_isMonday() {
        var comp = DateComponents()
        comp.year = 2026; comp.month = 6; comp.day = 3   // 周三
        let date = cal().date(from: comp)!
        let monday = TimeBucket.startOfWeek(date: date, calendar: cal())
        var mComp = DateComponents(); mComp.year = 2026; mComp.month = 6; mComp.day = 1
        XCTAssertEqual(monday, Int(cal().date(from: mComp)!.timeIntervalSince1970))
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `RUN_TESTS`
Expected: 编译失败（`TimeBucket`/`MouseButton` 未定义）。

- [ ] **Step 3: 实现**

`ClickPulse/Aggregate/MouseButton.swift`：
```swift
enum MouseButton: Int, CaseIterable {
    case left = 0, right = 1, middle = 2, other = 3
}
```
`ClickPulse/Store/TimeBucket.swift`：
```swift
import Foundation

struct TimeBucket: Equatable {
    let hourTimestamp: Int   // 本地墙钟整点对应的 epoch 秒
    let localHour: Int       // 0–23
    let localWeekday: Int    // 周一=1 … 周日=7

    static func current(date: Date = Date(), calendar: Calendar = .current) -> TimeBucket {
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .weekday], from: date)
        let startOfHour = calendar.date(from: DateComponents(
            year: comps.year, month: comps.month, day: comps.day, hour: comps.hour))!
        // Calendar.weekday: 周日=1…周六=7 → 转成 周一=1…周日=7
        let mondayBased = ((comps.weekday! + 5) % 7) + 1
        return TimeBucket(
            hourTimestamp: Int(startOfHour.timeIntervalSince1970),
            localHour: comps.hour!,
            localWeekday: mondayBased)
    }

    static func startOfHour(date: Date = Date(), calendar: Calendar = .current) -> Int {
        Int(calendar.dateInterval(of: .hour, for: date)!.start.timeIntervalSince1970)
    }
    static func startOfDay(date: Date = Date(), calendar: Calendar = .current) -> Int {
        Int(calendar.startOfDay(for: date).timeIntervalSince1970)
    }
    static func startOfWeek(date: Date = Date(), calendar: Calendar = .current) -> Int {
        Int(calendar.dateInterval(of: .weekOfYear, for: date)!.start.timeIntervalSince1970)
    }
    static func startOfMonth(date: Date = Date(), calendar: Calendar = .current) -> Int {
        Int(calendar.dateInterval(of: .month, for: date)!.start.timeIntervalSince1970)
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `RUN_TESTS`
Expected: PASS（4 个用例）。注：`startOfWeek` 依赖 `calendar.firstWeekday = 2`。

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: TimeBucket 本地时区分桶 + MouseButton（TDD）"
```

---

## Task 3: ClickStore — schema 与迁移（TDD）

**Files:**
- Create: `ClickPulse/Store/ClickStore.swift`
- Create: `ClickPulse/Store/Migrations.swift`
- Test: `ClickPulseTests/ClickStoreSchemaTests.swift`

- [ ] **Step 1: 写失败测试**

`ClickPulseTests/ClickStoreSchemaTests.swift`：
```swift
import XCTest
import GRDB
@testable import ClickPulse

final class ClickStoreSchemaTests: XCTestCase {
    private func tempURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cp-\(UUID().uuidString).sqlite")
    }

    func test_migrationCreatesTablesAndSetsVersion() throws {
        let url = tempURL()
        let store = try ClickStore(path: url)
        let exists = try store.dbQueue.read { db in
            try db.tableExists("click_hourly") && db.tableExists("meta")
        }
        XCTAssertTrue(exists)
        let version = try store.dbQueue.read { db in
            try Int.fetchOne(db, sql: "PRAGMA user_version") ?? -1
        }
        XCTAssertEqual(version, 1)
    }

    func test_openingTwiceIsIdempotent() throws {
        let url = tempURL()
        _ = try ClickStore(path: url)
        XCTAssertNoThrow(try ClickStore(path: url))   // 再次打开不重复建表/不报错
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `RUN_TESTS`
Expected: 编译失败（`ClickStore` 未定义）。

- [ ] **Step 3: 实现迁移与 store 初始化**

`ClickPulse/Store/Migrations.swift`：
```swift
import GRDB

enum Migrations {
    static func makeMigrator() -> DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE click_hourly (
                    hour_ts       INTEGER NOT NULL,
                    local_hour    INTEGER NOT NULL,
                    local_weekday INTEGER NOT NULL,
                    button        INTEGER NOT NULL,
                    count         INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY (hour_ts, button)
                );
            """)
            try db.execute(sql: "CREATE INDEX idx_click_hour ON click_hourly(hour_ts);")
            try db.execute(sql: "CREATE INDEX idx_click_local ON click_hourly(local_weekday, local_hour);")
            try db.execute(sql: "CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);")
            try db.execute(sql: "PRAGMA user_version = 1;")
        }
        return m
    }
}
```
`ClickPulse/Store/ClickStore.swift`：
```swift
import GRDB
import Foundation

final class ClickStore {
    let dbQueue: DatabaseQueue

    init(path: URL) throws {
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        var config = Configuration()
        config.prepareDatabase { db in try db.execute(sql: "PRAGMA journal_mode = WAL;") }
        dbQueue = try DatabaseQueue(path: path.path, configuration: config)
        try Migrations.makeMigrator().migrate(dbQueue)
        // DatabaseMigrator 用自己的 grdb_migrations 表记录已应用迁移；额外显式置 user_version 便于外部校验
        try dbQueue.write { db in try db.execute(sql: "PRAGMA user_version = 1;") }
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `RUN_TESTS`
Expected: PASS（2 个用例）。

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: ClickStore 初始化 + DatabaseMigrator v1 schema（TDD）"
```

---

## Task 4: ClickStore — 增量写入 upsert（TDD）

**Files:**
- Modify: `ClickPulse/Store/ClickStore.swift`
- Test: `ClickPulseTests/ClickStoreWriteTests.swift`

- [ ] **Step 1: 写失败测试**

`ClickPulseTests/ClickStoreWriteTests.swift`：
```swift
import XCTest
@testable import ClickPulse

final class ClickStoreWriteTests: XCTestCase {
    private func makeStore() throws -> ClickStore {
        try ClickStore(path: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cp-\(UUID().uuidString).sqlite"))
    }
    private let bucket = TimeBucket(hourTimestamp: 1_780_000_000, localHour: 14, localWeekday: 1)

    func test_addAccumulatesSameBucketButton() throws {
        let store = try makeStore()
        try store.add(bucket: bucket, button: .left, delta: 3)
        try store.add(bucket: bucket, button: .left, delta: 2)
        XCTAssertEqual(try store.total(), 5)
    }

    func test_differentButtonsAreSeparateRows() throws {
        let store = try makeStore()
        try store.add(bucket: bucket, button: .left, delta: 4)
        try store.add(bucket: bucket, button: .right, delta: 1)
        XCTAssertEqual(try store.total(), 5)
        XCTAssertEqual(try store.sumByButton(since: 0)[.left], 4)
        XCTAssertEqual(try store.sumByButton(since: 0)[.right], 1)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `RUN_TESTS`
Expected: 编译失败（`add`/`total`/`sumByButton` 未定义）。

- [ ] **Step 3: 实现 add（先加最小 total/sumByButton 让测试可编译）**

在 `ClickStore.swift` 增加：
```swift
extension ClickStore {
    func add(bucket: TimeBucket, button: MouseButton, delta: Int) throws {
        guard delta != 0 else { return }
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO click_hourly (hour_ts, local_hour, local_weekday, button, count)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(hour_ts, button) DO UPDATE SET count = count + excluded.count;
                """,
                arguments: [bucket.hourTimestamp, bucket.localHour, bucket.localWeekday, button.rawValue, delta])
        }
    }

    func total() throws -> Int {
        try dbQueue.read { db in try Int.fetchOne(db, sql: "SELECT COALESCE(SUM(count),0) FROM click_hourly") ?? 0 }
    }

    func sumByButton(since hourTs: Int) throws -> [MouseButton: Int] {
        try dbQueue.read { db in
            var result: [MouseButton: Int] = [:]
            let rows = try Row.fetchAll(db, sql:
                "SELECT button, SUM(count) AS c FROM click_hourly WHERE hour_ts >= ? GROUP BY button",
                arguments: [hourTs])
            for row in rows {
                if let b = MouseButton(rawValue: row["button"]) { result[b] = row["c"] }
            }
            return result
        }
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `RUN_TESTS`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: ClickStore 增量 upsert 写入（TDD）"
```

---

## Task 5: ClickStore — 派生查询（时/日/周/月/总/热力图/趋势，TDD）

**Files:**
- Modify: `ClickPulse/Store/ClickStore.swift`
- Test: `ClickPulseTests/ClickStoreQueryTests.swift`

- [ ] **Step 1: 写失败测试**

`ClickPulseTests/ClickStoreQueryTests.swift`：
```swift
import XCTest
@testable import ClickPulse

final class ClickStoreQueryTests: XCTestCase {
    private func makeStore() throws -> ClickStore {
        try ClickStore(path: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cp-\(UUID().uuidString).sqlite"))
    }

    func test_sumSinceCutoff() throws {
        let store = try makeStore()
        try store.add(bucket: TimeBucket(hourTimestamp: 100, localHour: 0, localWeekday: 1), button: .left, delta: 5)
        try store.add(bucket: TimeBucket(hourTimestamp: 200, localHour: 1, localWeekday: 1), button: .left, delta: 7)
        XCTAssertEqual(try store.sum(since: 150), 7)   // 只数 >=150
        XCTAssertEqual(try store.sum(since: 0), 12)
    }

    func test_heatmapBucketsByLocalWeekdayHour() throws {
        let store = try makeStore()
        // 周一(1) 14 点 累计 3；周日(7) 9 点 累计 2
        try store.add(bucket: TimeBucket(hourTimestamp: 1, localHour: 14, localWeekday: 1), button: .left, delta: 3)
        try store.add(bucket: TimeBucket(hourTimestamp: 2, localHour: 9, localWeekday: 7), button: .right, delta: 2)
        let grid = try store.heatmap()                 // [weekdayIndex 0..6][hour 0..23]
        XCTAssertEqual(grid.count, 7)
        XCTAssertEqual(grid[0].count, 24)
        XCTAssertEqual(grid[0][14], 3)                 // 周一(index0) 14 点
        XCTAssertEqual(grid[6][9], 2)                  // 周日(index6) 9 点
        XCTAssertEqual(grid[0][9], 0)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `RUN_TESTS`
Expected: 编译失败（`sum`/`heatmap` 未定义）。

- [ ] **Step 3: 实现查询**

在 `ClickStore.swift` 增加：
```swift
extension ClickStore {
    func sum(since hourTs: Int) throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql:
                "SELECT COALESCE(SUM(count),0) FROM click_hourly WHERE hour_ts >= ?",
                arguments: [hourTs]) ?? 0
        }
    }

    /// 返回 7×24 矩阵：grid[weekday-1][hour] = 累计点击（含所有按键）
    func heatmap() throws -> [[Int]] {
        var grid = Array(repeating: Array(repeating: 0, count: 24), count: 7)
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT local_weekday AS w, local_hour AS h, SUM(count) AS c
                FROM click_hourly GROUP BY local_weekday, local_hour
                """)
            for row in rows {
                let w: Int = row["w"], h: Int = row["h"], c: Int = row["c"]
                if (1...7).contains(w), (0...23).contains(h) { grid[w - 1][h] = c }
            }
        }
        return grid
    }

    /// 近 days 天每天总点击，返回按 day epoch 升序的 (dayStartTs, count)
    func dailyTrend(sinceDayStart: Int) throws -> [(day: Int, count: Int)] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT (hour_ts - (hour_ts % 86400)) AS day, SUM(count) AS c
                FROM click_hourly WHERE hour_ts >= ?
                GROUP BY day ORDER BY day ASC
                """, arguments: [sinceDayStart])
            return rows.map { (day: $0["day"], count: $0["c"]) }
        }
    }
}
```
> 注：`dailyTrend` 的 86400 取整仅用于趋势分组的近似日界；五档「日/周/月」严格边界由调用方用 `TimeBucket.startOfDay/Week/Month` 传入 `sum(since:)`（见 Task 10 StatsProvider），不依赖此近似。

- [ ] **Step 4: 跑测试确认通过**

Run: `RUN_TESTS`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: ClickStore 派生查询 sum/heatmap/dailyTrend（TDD）"
```

---

## Task 6: ClickCounter — 并发安全计数 + swap 翻篇（TDD）

**Files:**
- Create: `ClickPulse/Aggregate/ClickCounter.swift`
- Test: `ClickPulseTests/ClickCounterTests.swift`

- [ ] **Step 1: 写失败测试**

`ClickPulseTests/ClickCounterTests.swift`：
```swift
import XCTest
@testable import ClickPulse

final class ClickCounterTests: XCTestCase {
    func test_incrementThenDrainReturnsAndResets() {
        let c = ClickCounter()
        c.increment(.left); c.increment(.left); c.increment(.right)
        let first = c.drain()
        XCTAssertEqual(first[.left], 2)
        XCTAssertEqual(first[.right], 1)
        let second = c.drain()                 // drain 后清零
        XCTAssertEqual(second.values.reduce(0, +), 0)
    }

    func test_concurrentIncrementsAreNotLost() {
        let c = ClickCounter()
        let iterations = 10_000
        DispatchQueue.concurrentPerform(iterations: iterations) { _ in c.increment(.left) }
        XCTAssertEqual(c.drain()[.left], iterations)   // 无 data race 丢计数
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `RUN_TESTS`
Expected: 编译失败（`ClickCounter` 未定义）。

- [ ] **Step 3: 实现（os_unfair_lock 保护 + swap）**

`ClickPulse/Aggregate/ClickCounter.swift`：
```swift
import os

final class ClickCounter {
    private var counts: [MouseButton: Int] = [:]
    private let lock = OSAllocatedUnfairLock()

    func increment(_ button: MouseButton) {
        lock.withLock { counts[button, default: 0] += 1 }
    }

    /// 原子取出当前计数并清零（整点翻篇 / flush 用）
    func drain() -> [MouseButton: Int] {
        lock.withLock {
            let snapshot = counts
            counts = [:]
            return snapshot
        }
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `RUN_TESTS`
Expected: PASS（并发用例验证无丢计数）。

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: ClickCounter 并发计数 + swap 翻篇（TDD）"
```

---

## Task 7: ExportService — CSV/JSON（TDD）

**Files:**
- Create: `ClickPulse/System/ExportService.swift`
- Test: `ClickPulseTests/ExportServiceTests.swift`

- [ ] **Step 1: 写失败测试**

`ClickPulseTests/ExportServiceTests.swift`：
```swift
import XCTest
@testable import ClickPulse

final class ExportServiceTests: XCTestCase {
    private let rows = [
        HourRow(hourTs: 1_780_000_000, localHour: 14, localWeekday: 1,
                counts: [.left: 10, .right: 2, .middle: 1, .other: 0])
    ]

    func test_csvHasHeaderAndRow() {
        let csv = ExportService.csv(rows: rows)
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.first, "hour_iso8601,local_hour,local_weekday,left,right,middle,other")
        XCTAssertTrue(lines[1].hasSuffix(",14,1,10,2,1,0"))
    }

    func test_jsonRoundTrips() throws {
        let data = try ExportService.json(rows: rows, timezone: "Asia/Shanghai", schemaVersion: 1)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["schema_version"] as? Int, 1)
        XCTAssertEqual(obj["timezone"] as? String, "Asia/Shanghai")
        XCTAssertEqual((obj["records"] as? [[String: Any]])?.count, 1)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `RUN_TESTS`
Expected: 编译失败（`HourRow`/`ExportService` 未定义）。

- [ ] **Step 3: 实现**

`ClickPulse/System/ExportService.swift`：
```swift
import Foundation

struct HourRow {
    let hourTs: Int
    let localHour: Int
    let localWeekday: Int
    let counts: [MouseButton: Int]
    func c(_ b: MouseButton) -> Int { counts[b] ?? 0 }
}

enum ExportService {
    static func csv(rows: [HourRow]) -> String {
        var out = "hour_iso8601,local_hour,local_weekday,left,right,middle,other\n"
        let fmt = ISO8601DateFormatter()
        for r in rows {
            let iso = fmt.string(from: Date(timeIntervalSince1970: TimeInterval(r.hourTs)))
            out += "\(iso),\(r.localHour),\(r.localWeekday),\(r.c(.left)),\(r.c(.right)),\(r.c(.middle)),\(r.c(.other))\n"
        }
        return out
    }

    static func json(rows: [HourRow], timezone: String, schemaVersion: Int) throws -> Data {
        let fmt = ISO8601DateFormatter()
        let records: [[String: Any]] = rows.map { r in
            ["hour": fmt.string(from: Date(timeIntervalSince1970: TimeInterval(r.hourTs))),
             "local_hour": r.localHour, "local_weekday": r.localWeekday,
             "left": r.c(.left), "right": r.c(.right), "middle": r.c(.middle), "other": r.c(.other)]
        }
        let root: [String: Any] = [
            "exported_at": fmt.string(from: Date()),
            "timezone": timezone, "schema_version": schemaVersion, "records": records]
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `RUN_TESTS`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: ExportService CSV/JSON 导出（TDD）"
```

---

# Phase 2：系统与 GUI 集成（实现 + 手动验证）

> 这些组件依赖系统权限/事件/菜单栏/launchd，无法 unit test。每个 Task 给**完整实现** + **手动验证步骤**。

## Task 8: PermissionManager（输入监控权限）

**Files:**
- Create: `ClickPulse/System/PermissionManager.swift`

- [ ] **Step 1: 实现**

`ClickPulse/System/PermissionManager.swift`：
```swift
import CoreGraphics
import AppKit

enum PermissionManager {
    /// 静默检测是否已授予「输入监控」（不弹窗）
    static var isGranted: Bool { CGPreflightListenEventAccess() }

    /// 触发系统授权弹窗；返回当前是否已授权
    @discardableResult
    static func request() -> Bool { CGRequestListenEventAccess() }

    /// 直达系统设置 → 隐私与安全性 → 输入监控
    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 2: 手动验证**

临时在 `AppDelegate.applicationDidFinishLaunching` 末尾加 `print("granted=\(PermissionManager.isGranted)")`，运行：
Expected: 控制台打印 `granted=false`（首次未授权）。调用 `PermissionManager.request()` 应弹出系统授权请求。验证后移除临时 print。

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: PermissionManager 输入监控权限检测/申请/引导"
```

---

## Task 9: EventTapController（CGEventTap + 自愈 + 唤醒重建）

**Files:**
- Create: `ClickPulse/Capture/EventTapController.swift`

- [ ] **Step 1: 实现**

`ClickPulse/Capture/EventTapController.swift`：
```swift
import CoreGraphics
import AppKit

final class EventTapController {
    /// 每次点击回调（在主 run loop 线程）
    var onClick: ((MouseButton) -> Void)?
    /// 健康状态变化：true=正常监听中，false=tap 创建/重建失败
    var onHealthChange: ((Bool) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var healthTimer: Timer?

    func start() {
        installTap()
        healthTimer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
            self?.verifyHealth()
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    func stop() {
        healthTimer?.invalidate(); healthTimer = nil
        teardownTap()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func didWake() { rebuild() }   // 唤醒后立即重建，不等 Timer

    private func installTap() {
        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let ctrl = Unmanaged<EventTapController>.fromOpaque(refcon!).takeUnretainedValue()
            ctrl.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask, callback: callback, userInfo: refcon) else {
            onHealthChange?(false); return
        }
        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        onHealthChange?(true)
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        let button: MouseButton
        switch type {
        case .leftMouseDown:  button = .left
        case .rightMouseDown: button = .right
        case .otherMouseDown:
            button = event.getIntegerValueField(.mouseEventButtonNumber) == 2 ? .middle : .other
        default: return
        }
        onClick?(button)
    }

    private func verifyHealth() {
        guard let tap = tap, CGEvent.tapIsEnabled(tap: tap) else { rebuild(); return }
    }

    private func rebuild() { teardownTap(); installTap() }

    private func teardownTap() {
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        runLoopSource = nil
        tap = nil
    }
}
```

- [ ] **Step 2: 手动验证（需先授权）**

临时在 AppDelegate 接 `eventTap.onClick = { print("click \($0)") }` 并 `eventTap.start()`，在系统设置授予 ClickPulse「输入监控」后运行：
Expected: 左/右/中键点击分别打印 `click left/right/middle`；撤销授权后 45 秒内或重建时 `onHealthChange(false)`。验证后移除临时代码。

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: EventTapController 全局点击监听 + 自愈 + 唤醒重建"
```

---

## Task 10: Aggregator + StatsProvider + appCalendar

**Files:**
- Create: `ClickPulse/Aggregate/Aggregator.swift`
- Create: `ClickPulse/Stats/StatsProvider.swift`
- Create: `ClickPulse/Store/Calendar+App.swift`
- Test: `ClickPulseTests/StatsProviderTests.swift`

- [ ] **Step 1: 写失败测试（StatsProvider 派生正确）**

`ClickPulseTests/StatsProviderTests.swift`：
```swift
import XCTest
@testable import ClickPulse

final class StatsProviderTests: XCTestCase {
    func test_refreshComputesFiveBuckets() throws {
        let store = try ClickStore(path: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cp-\(UUID().uuidString).sqlite"))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        cal.firstWeekday = 2
        var comp = DateComponents(); comp.year = 2026; comp.month = 6; comp.day = 3; comp.hour = 10
        let now = cal.date(from: comp)!   // 2026-06-03 10:00 周三

        // 本小时 +5
        let hb = TimeBucket.current(date: now, calendar: cal)
        try store.add(bucket: hb, button: .left, delta: 5)

        let provider = StatsProvider(store: store)
        provider.refresh(calendar: cal, now: now)
        XCTAssertEqual(provider.snapshot.hour, 5)
        XCTAssertEqual(provider.snapshot.day, 5)
        XCTAssertEqual(provider.snapshot.total, 5)
        XCTAssertEqual(provider.snapshot.byButton[.left], 5)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `RUN_TESTS`
Expected: 编译失败（`StatsProvider` 未定义）。

- [ ] **Step 3: 实现**

`ClickPulse/Store/Calendar+App.swift`：
```swift
import Foundation
extension Calendar {
    /// 应用统一日历：本地时区 + 周一为一周起点
    static var appCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone.current
        c.firstWeekday = 2
        return c
    }
}
```
`ClickPulse/Stats/StatsProvider.swift`：
```swift
import Foundation
import Observation

struct StatsSnapshot: Equatable {
    var hour = 0, day = 0, week = 0, month = 0, total = 0
    var byButton: [MouseButton: Int] = [:]
}

@Observable
final class StatsProvider {
    private let store: ClickStore
    var snapshot = StatsSnapshot()
    var heatmap: [[Int]] = Array(repeating: Array(repeating: 0, count: 24), count: 7)

    init(store: ClickStore) { self.store = store }

    func refresh(calendar: Calendar = .appCalendar, now: Date = Date()) {
        var s = StatsSnapshot()
        s.hour  = (try? store.sum(since: TimeBucket.startOfHour(date: now, calendar: calendar)))  ?? 0
        s.day   = (try? store.sum(since: TimeBucket.startOfDay(date: now, calendar: calendar)))   ?? 0
        s.week  = (try? store.sum(since: TimeBucket.startOfWeek(date: now, calendar: calendar)))  ?? 0
        s.month = (try? store.sum(since: TimeBucket.startOfMonth(date: now, calendar: calendar))) ?? 0
        s.total = (try? store.total()) ?? 0
        s.byButton = (try? store.sumByButton(since: 0)) ?? [:]
        snapshot = s
        heatmap = (try? store.heatmap()) ?? heatmap
    }
}
```
`ClickPulse/Aggregate/Aggregator.swift`：
```swift
import Foundation

/// 把内存计数定时落库；翻篇用 drain(swap)。
/// 误差说明：flush 间隔(默认5s)内跨整点的点击会归到上一小时桶，最多一个间隔的点击、仅整点边界一次——对统计无实质影响。
final class Aggregator {
    private let counter: ClickCounter
    private let store: ClickStore
    private var lastBucket: TimeBucket
    private var timer: Timer?
    var onFlush: (() -> Void)?

    init(counter: ClickCounter, store: ClickStore) {
        self.counter = counter
        self.store = store
        self.lastBucket = TimeBucket.current(calendar: .appCalendar)
    }

    func start(interval: TimeInterval = 5) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.flush()
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    /// 退出/休眠前也应主动调用，确保不丢内存计数
    func flush() {
        let snap = counter.drain()
        for (button, n) in snap where n != 0 {
            try? store.add(bucket: lastBucket, button: button, delta: n)
        }
        lastBucket = TimeBucket.current(calendar: .appCalendar)
        onFlush?()
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `RUN_TESTS`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: Aggregator 定时落库 + StatsProvider 派生 + appCalendar（TDD）"
```

---

## Task 11: ClickStore.allRows（导出数据源，TDD）

**Files:**
- Modify: `ClickPulse/Store/ClickStore.swift`
- Test: `ClickPulseTests/ClickStoreAllRowsTests.swift`

- [ ] **Step 1: 写失败测试**

`ClickPulseTests/ClickStoreAllRowsTests.swift`：
```swift
import XCTest
@testable import ClickPulse

final class ClickStoreAllRowsTests: XCTestCase {
    func test_allRowsGroupsButtonsPerBucket() throws {
        let store = try ClickStore(path: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cp-\(UUID().uuidString).sqlite"))
        let b = TimeBucket(hourTimestamp: 1_780_000_000, localHour: 14, localWeekday: 1)
        try store.add(bucket: b, button: .left, delta: 10)
        try store.add(bucket: b, button: .right, delta: 2)
        let rows = try store.allRows()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].c(.left), 10)
        XCTAssertEqual(rows[0].c(.right), 2)
        XCTAssertEqual(rows[0].localHour, 14)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `RUN_TESTS` → 编译失败（`allRows` 未定义）。

- [ ] **Step 3: 实现**

在 `ClickStore.swift` 增加：
```swift
extension ClickStore {
    /// 每个小时桶一行，按键聚成 HourRow（供导出）
    func allRows() throws -> [HourRow] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT hour_ts, local_hour, local_weekday, button, count
                FROM click_hourly ORDER BY hour_ts ASC
                """)
            var byBucket: [Int: (Int, Int, [MouseButton: Int])] = [:]
            for r in rows {
                let ts: Int = r["hour_ts"]
                var entry = byBucket[ts] ?? (r["local_hour"], r["local_weekday"], [:])
                if let b = MouseButton(rawValue: r["button"]) { entry.2[b] = r["count"] }
                byBucket[ts] = entry
            }
            return byBucket.keys.sorted().map { ts in
                let e = byBucket[ts]!
                return HourRow(hourTs: ts, localHour: e.0, localWeekday: e.1, counts: e.2)
            }
        }
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `RUN_TESTS` → PASS。

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: ClickStore.allRows 导出数据源（TDD）"
```

---

## Task 12: StatusItemManager + IconStateController（菜单栏图标 + popover）

**Files:**
- Create: `ClickPulse/UI/StatusItemManager.swift`

- [ ] **Step 1: 实现**

`ClickPulse/UI/StatusItemManager.swift`：
```swift
import AppKit
import SwiftUI

enum IconState { case ok, warning }

final class StatusItemManager {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()

    init<Content: View>(rootView: Content) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: rootView)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)
        setState(.ok)
    }

    func setState(_ state: IconState) {
        let symbol = state == .ok ? "cursorarrow.click" : "exclamationmark.triangle"
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "ClickPulse")
        img?.isTemplate = true
        statusItem.button?.image = img
        statusItem.button?.appearsDisabled = (state == .warning)
    }

    @objc private func toggle() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
```

- [ ] **Step 2: 手动验证**

临时在 AppDelegate 用 `StatusItemManager(rootView: Text("hi").padding())` 替换 Task 1 的裸图标，运行：
Expected: 点击菜单栏图标弹出含 "hi" 的小面板，点别处收起。

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: StatusItemManager 菜单栏图标 + NSPopover + 状态切换"
```

---

## Task 13: SwiftUI 面板视图

**Files:**
- Create: `ClickPulse/UI/PanelView.swift`
- Create: `ClickPulse/UI/DashboardView.swift`
- Create: `ClickPulse/UI/HeatmapView.swift`
- Create: `ClickPulse/UI/TrendView.swift`
- Create: `ClickPulse/UI/ExportView.swift`
- Create: `ClickPulse/UI/PermissionView.swift`

- [ ] **Step 1: 实现 PanelView（顶层容器 + Tab 切换）**

`ClickPulse/UI/PanelView.swift`：
```swift
import SwiftUI

enum PanelTab: String, CaseIterable { case 趋势, 热力图, 导出, 设置 }

struct PanelView: View {
    @Bindable var stats: StatsProvider
    let store: ClickStore
    let permissionGranted: Bool
    var onRequestPermission: () -> Void = {}
    var launchAtLogin: Binding<Bool>

    @State private var tab: PanelTab = .趋势

    var body: some View {
        VStack(spacing: 12) {
            if !permissionGranted {
                PermissionView(onRequest: onRequestPermission)
            }
            DashboardView(stats: stats)
            Picker("", selection: $tab) {
                ForEach(PanelTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            Group {
                switch tab {
                case .趋势:   TrendView(store: store)
                case .热力图: HeatmapView(grid: stats.heatmap)
                case .导出:   ExportView(store: store)
                case .设置:   SettingsView(launchAtLogin: launchAtLogin)
                }
            }.frame(height: 220)
        }
        .padding(14)
        .frame(width: 360)
    }
}

struct SettingsView: View {
    @Binding var launchAtLogin: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("开机自启 + 崩溃自动拉起", isOn: $launchAtLogin)
            Text("数据目录：~/Library/Application Support/com.liuzhuo.clickpulse/")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

- [ ] **Step 2: 实现 DashboardView（分按键切换 + 五档）**

`ClickPulse/UI/DashboardView.swift`：
```swift
import SwiftUI

private enum ButtonFilter: String, CaseIterable { case 合计, 左键, 右键, 中键, 其它 }

struct DashboardView: View {
    @Bindable var stats: StatsProvider
    @State private var filter: ButtonFilter = .合计

    /// 当前过滤下的缩放系数：合计=1，单按键=该键占比（用 byButton 估算各档同比例）
    private func value(_ total: Int) -> Int {
        switch filter {
        case .合计: return total
        case .左键: return scaled(total, .left)
        case .右键: return scaled(total, .right)
        case .中键: return scaled(total, .middle)
        case .其它: return scaled(total, .other)
        }
    }
    private func scaled(_ total: Int, _ b: MouseButton) -> Int {
        let all = stats.snapshot.byButton.values.reduce(0, +)
        guard all > 0 else { return 0 }
        return Int((Double(total) * Double(stats.snapshot.byButton[b] ?? 0) / Double(all)).rounded())
    }

    private var filters: [ButtonFilter] {
        var fs: [ButtonFilter] = [.合计, .左键, .右键, .中键]
        if (stats.snapshot.byButton[.other] ?? 0) > 0 { fs.append(.其它) }
        return fs
    }

    var body: some View {
        VStack(spacing: 8) {
            Picker("", selection: $filter) {
                ForEach(filters, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            HStack(spacing: 0) {
                cell("时", value(stats.snapshot.hour))
                cell("日", value(stats.snapshot.day))
                cell("周", value(stats.snapshot.week))
                cell("月", value(stats.snapshot.month))
                cell("总", value(stats.snapshot.total))
            }
        }
    }

    private func cell(_ label: String, _ n: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(n)").font(.title3).monospacedDigit().fontWeight(.semibold)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
}
```
> 注：单按键各档采用「按总体分按键占比同比例缩放」近似（首版避免为每档每按键单独建查询）。若日后要精确单按键五档，给 `ClickStore.sumByButton(since:)` 各档分别传入对应 cutoff 即可，接口已具备。

- [ ] **Step 3: 实现 HeatmapView（7×24，区分真实0/无数据）**

`ClickPulse/UI/HeatmapView.swift`：
```swift
import SwiftUI

struct HeatmapView: View {
    let grid: [[Int]]   // [weekday0..6][hour0..23]
    private let weekdays = ["一","二","三","四","五","六","日"]

    private var maxVal: Int { grid.flatMap { $0 }.max() ?? 0 }
    private var hasData: Bool { maxVal > 0 }

    var body: some View {
        if !hasData {
            VStack { Spacer(); Text("开始点击后这里会出现统计").foregroundStyle(.secondary); Spacer() }
        } else {
            VStack(spacing: 2) {
                ForEach(0..<7, id: \.self) { w in
                    HStack(spacing: 2) {
                        Text(weekdays[w]).font(.caption2).frame(width: 14)
                        ForEach(0..<24, id: \.self) { h in cell(grid[w][h]) }
                    }
                }
                Text("颜色越深点击越多 · 横轴 0–23 时").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func cell(_ v: Int) -> some View {
        let intensity = maxVal > 0 ? Double(v) / Double(maxVal) : 0
        // 真实 0 用极浅底色；>0 用蓝色按强度加深
        return RoundedRectangle(cornerRadius: 2)
            .fill(v == 0 ? Color.gray.opacity(0.12) : Color.accentColor.opacity(0.15 + 0.85 * intensity))
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
    }
}
```

- [ ] **Step 4: 实现 TrendView（近 30 天折线）**

`ClickPulse/UI/TrendView.swift`：
```swift
import SwiftUI
import Charts

struct TrendView: View {
    let store: ClickStore
    @State private var points: [(day: Date, count: Int)] = []

    var body: some View {
        Group {
            if points.allSatisfy({ $0.count == 0 }) {
                VStack { Spacer(); Text("开始点击后这里会出现统计").foregroundStyle(.secondary); Spacer() }
            } else {
                Chart(points, id: \.day) { p in
                    LineMark(x: .value("日期", p.day), y: .value("点击", p.count))
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        let cal = Calendar.appCalendar
        let since = TimeBucket.startOfDay(date: Date().addingTimeInterval(-30 * 86400), calendar: cal)
        let raw = (try? store.dailyTrend(sinceDayStart: since)) ?? []
        points = raw.map { (Date(timeIntervalSince1970: TimeInterval($0.day)), $0.count) }
    }
}
```

- [ ] **Step 5: 实现 ExportView + PermissionView**

`ClickPulse/UI/ExportView.swift`：
```swift
import SwiftUI
import AppKit

struct ExportView: View {
    let store: ClickStore
    @State private var message = ""

    var body: some View {
        VStack(spacing: 12) {
            Text("导出全部统计数据").font(.subheadline)
            HStack {
                Button("导出 CSV") { export(.csv) }
                Button("导出 JSON") { export(.json) }
            }
            Button("打开数据目录") {
                NSWorkspace.shared.open(URL(fileURLWithPath:
                    NSHomeDirectory() + "/Library/Application Support/com.liuzhuo.clickpulse"))
            }
            if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private enum Kind { case csv, json }
    private func export(_ kind: Kind) {
        let rows = (try? store.allRows()) ?? []
        let panel = NSSavePanel()
        panel.nameFieldStringValue = kind == .csv ? "clickpulse.csv" : "clickpulse.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            switch kind {
            case .csv:  try ExportService.csv(rows: rows).data(using: .utf8)!.write(to: url)
            case .json: try ExportService.json(rows: rows,
                            timezone: TimeZone.current.identifier, schemaVersion: 1).write(to: url)
            }
            message = "已导出到 \(url.lastPathComponent)"
        } catch { message = "导出失败：\(error.localizedDescription)" }
    }
}
```
`ClickPulse/UI/PermissionView.swift`：
```swift
import SwiftUI

struct PermissionView: View {
    var onRequest: () -> Void
    var body: some View {
        VStack(spacing: 6) {
            Label("未获得「输入监控」权限，当前未在统计", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
            Button("去授权") { onRequest() }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }
}
```

- [ ] **Step 6: 手动验证**

把 PanelView 接入 StatusItemManager（临时用假 StatsProvider + 真 ClickStore 跑通编译），运行点开面板：
Expected: 五档数字、分按键分段、趋势/热力图/导出/设置 Tab 都能渲染（数据可能为 0/空状态文案）。

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: SwiftUI 面板（五档/分按键/趋势/热力图/导出/设置）"
```

---

## Task 14: LaunchAgentService（SMAppService.agent + bundle plist）

**Files:**
- Create: `ClickPulse/System/LaunchAgentService.swift`
- Create: `ClickPulse/LaunchAgents/com.liuzhuo.clickpulse.plist`
- Modify: 工程加 Copy Files build phase，把 plist 放进 `Contents/Library/LaunchAgents/`

- [ ] **Step 1: 创建随 bundle 分发的 LaunchAgent plist**

`ClickPulse/LaunchAgents/com.liuzhuo.clickpulse.plist`：
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.liuzhuo.clickpulse</string>
    <key>BundleProgram</key><string>Contents/MacOS/ClickPulse</string>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key>
    <dict><key>SuccessfulExit</key><false/></dict>
    <key>ThrottleInterval</key><integer>10</integer>
    <key>ProcessType</key><string>Interactive</string>
    <key>LimitLoadToSessionType</key><array><string>Aqua</string></array>
</dict>
</plist>
```

- [ ] **Step 2: 把 plist 复制进 bundle**

Xcode → ClickPulse target → Build Phases → 新增 Copy Files Phase：Destination = Wrapper，Subpath = `Contents/Library/LaunchAgents`，加入上面的 plist 文件。

- [ ] **Step 3: 实现 LaunchAgentService**

`ClickPulse/System/LaunchAgentService.swift`：
```swift
import ServiceManagement

enum LaunchAgentService {
    private static let plistName = "com.liuzhuo.clickpulse.plist"
    private static var agent: SMAppService { SMAppService.agent(plistName: plistName) }

    static var isEnabled: Bool { agent.status == .enabled }

    static func setEnabled(_ on: Bool) throws {
        if on { try agent.register() } else { try agent.unregister() }
    }
}
```

- [ ] **Step 4: 手动验证**

设置面板里打开「开机自启」开关后：
Run: `launchctl print gui/$(id -u)/com.liuzhuo.clickpulse | head`
Expected: 能看到该 service 已注册；`SMAppService.agent.status == .enabled`。关掉开关后 unregister。

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: LaunchAgentService 用 SMAppService.agent 注册（支持 KeepAlive）"
```

---

## Task 15: AppDelegate 串联 + 故障可见 + 单实例 + 退出/休眠 flush

**Files:**
- Modify: `ClickPulse/App/AppDelegate.swift`

- [ ] **Step 1: 实现完整 AppDelegate**

`ClickPulse/App/AppDelegate.swift`：
```swift
import AppKit
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: ClickStore!
    private let counter = ClickCounter()
    private var aggregator: Aggregator!
    private let eventTap = EventTapController()
    private var stats: StatsProvider!
    private var statusManager: StatusItemManager!
    private var launchAtLogin = false
    private var eventTapStarted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // 单实例仲裁：已有实例（通常是 launchd 托管的权威实例）则本实例干净退出
        let others = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.liuzhuo.clickpulse")
            .filter { $0 != .current }
        if !others.isEmpty { NSApp.terminate(nil); return }   // exit(0)，不触发 KeepAlive

        // 数据层
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.liuzhuo.clickpulse", isDirectory: true)
        store = try! ClickStore(path: dir.appendingPathComponent("clickpulse.sqlite"))
        stats = StatsProvider(store: store)
        aggregator = Aggregator(counter: counter, store: store)
        launchAtLogin = LaunchAgentService.isEnabled

        // 菜单栏 + 面板
        let panel = PanelView(
            stats: stats, store: store,
            permissionGranted: PermissionManager.isGranted,
            onRequestPermission: { PermissionManager.request(); PermissionManager.openSettings() },
            launchAtLogin: Binding(get: { [weak self] in self?.launchAtLogin ?? false },
                                   set: { [weak self] on in
                                       try? LaunchAgentService.setEnabled(on); self?.launchAtLogin = on }))
        statusManager = StatusItemManager(rootView: panel)

        // 监听 → 计数
        eventTap.onClick = { [weak self] button in self?.counter.increment(button) }
        eventTap.onHealthChange = { [weak self] healthy in
            DispatchQueue.main.async { self?.updateHealth(healthy) }
        }
        aggregator.onFlush = { [weak self] in
            self?.syncPermissionAndTap()
            self?.stats.refresh()
            self?.refreshIcon()
        }

        // 通知授权（用于故障提示）
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }

        // 启动
        syncPermissionAndTap()   // 已授权则启动 tap；未授权则等轮询恢复
        aggregator.start()
        stats.refresh()
        refreshIcon()

        // 休眠前 flush，退出前 flush
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
    }

    /// 每次 flush(≈5s) 调用：授权状态与 tap 启停同步——用户刚授权时自动开始统计，撤销时停止
    private func syncPermissionAndTap() {
        if PermissionManager.isGranted {
            if !eventTapStarted { eventTap.start(); eventTapStarted = true }
        } else if eventTapStarted {
            eventTap.stop(); eventTapStarted = false
        }
    }

    @objc private func willSleep() { aggregator.flush() }

    func applicationWillTerminate(_ notification: Notification) { aggregator.flush() }

    private func updateHealth(_ healthy: Bool) {
        if !healthy {
            statusManager.setState(.warning)
            notify(title: "ClickPulse 已停止统计", body: "请到「系统设置 → 隐私与安全性 → 输入监控」重新授权。")
        } else {
            refreshIcon()
        }
    }

    private func refreshIcon() {
        statusManager.setState(PermissionManager.isGranted ? .ok : .warning)
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
```

- [ ] **Step 2: 手动验证（端到端冒烟）**

授权「输入监控」后运行：
Expected: 点击鼠标 → 5 秒内面板「时/日/总」数字增长；撤销授权 → 图标变警告态 + 收到系统通知；重开自启开关 → `launchctl` 可见。

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: AppDelegate 串联全链路 + 故障可见 + 单实例 + 退出/休眠 flush"
```

---

# Phase 3：构建、签名与交付

## Task 16: 固定自签名证书 + 构建/重签脚本

**Files:**
- Create: `scripts/build.command`
- Create: `scripts/resign.command`

- [ ] **Step 1: 一次性创建固定自签名 Code Signing 证书（GUI，仅一次）**

打开「钥匙串访问」→ 菜单「证书助理 → 创建证书」：
- 名称：`ClickPulse Self-Signed`
- 身份类型：自签名根
- 证书类型：**代码签名**
- 创建后留在「登录」钥匙串。
**立即备份**：右键该证书 → 导出 → 存为 `ClickPulse-signing.p12`（设密码）妥善保存（换机/重装用）。

- [ ] **Step 2: build.command（建产物 + 签名 + 装到 /Applications）**

`scripts/build.command`：
```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CERT="ClickPulse Self-Signed"
APP="/Applications/ClickPulse.app"

echo "==> 编译 Release"
xcodebuild -project ClickPulse.xcodeproj -scheme ClickPulse \
  -configuration Release -derivedDataPath build -quiet

BUILT="build/Build/Products/Release/ClickPulse.app"
echo "==> 签名（固定身份：$CERT）"
codesign --force --deep --options runtime --sign "$CERT" "$BUILT"

echo "==> 安装到 /Applications"
rm -rf "$APP"
cp -R "$BUILT" "$APP"
xattr -dr com.apple.quarantine "$APP" || true   # 本地产物通常无 quarantine，保险起见

echo "✅ 完成：$APP"
echo "首次运行后请到 系统设置 → 隐私与安全性 → 输入监控 勾选 ClickPulse"
open "$APP"
```
设可执行：`chmod +x scripts/build.command`。

- [ ] **Step 3: resign.command（换机/重装：从 .p12 恢复证书并重签）**

`scripts/resign.command`：
```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
P12="${1:-ClickPulse-signing.p12}"
echo "==> 从 $P12 导入签名证书到登录钥匙串"
security import "$P12" -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign
echo "==> 重新构建+签名+安装"
exec scripts/build.command
```
设可执行：`chmod +x scripts/resign.command`。

- [ ] **Step 4: 验证**

Run: `scripts/build.command`
Expected: 产出 `/Applications/ClickPulse.app` 并启动；`codesign -dv /Applications/ClickPulse.app` 显示 Authority=`ClickPulse Self-Signed`。

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "build: 固定自签名构建脚本 build.command + resign.command"
```

---

## Task 17: 端到端安装、授权与验收

**Files:**（无新增，验收清单）

- [ ] **Step 1: 全新安装走查**

1. 跑 `scripts/build.command` → `/Applications/ClickPulse.app` 启动、菜单栏出现图标（首次为警告态，因未授权）。
2. 点图标 → 面板顶部显示「未获得输入监控权限」+「去授权」。
3. 点「去授权」→ 系统设置打开 → 勾选 ClickPulse → 退出并重开 App（或 App 自动恢复）。
4. 授权后图标转正常态。

- [ ] **Step 2: 功能验收（对照需求）**

- 左/右/中键各点几下 → 5 秒内「时/日/周/月/总」增长；分按键切换数字联动（R1/R2）。
- 趋势 Tab 有当日点 / 空状态文案（R3）。
- 热力图 Tab 当前小时格子加深（R4）。
- 导出 CSV/JSON → 文件内容正确（R5）。
- 设置开「开机自启」→ `launchctl print gui/$(id -u)/com.liuzhuo.clickpulse` 可见（R7）。

- [ ] **Step 3: 守护验收**

- `kill -9 $(pgrep ClickPulse)` → 10 秒内进程被 launchd 拉起（R7 崩溃自动拉起）。
- 菜单「退出」（exit 0）→ 不被拉起（验证 KeepAlive SuccessfulExit=false 语义）。

- [ ] **Step 4: 重启验收**

- 重启 Mac → 登录后 ClickPulse 自动出现在菜单栏，授权保持（固定签名身份 → TCC 未失效）。

- [ ] **Step 5: Commit（如有收尾改动）**

```bash
git add -A && git commit -m "docs: 端到端验收清单"
```

---

## 需求覆盖对照（self-review 用）

| 需求 | 实现位置 |
|---|---|
| R1 全局监听左/右/中 + 分按键 | Task 9 EventTapController + Task 13 DashboardView 分按键 |
| R2 菜单栏图标 + 五档面板 | Task 12 StatusItemManager + Task 13 DashboardView |
| R3 历史趋势 | Task 5 dailyTrend + Task 13 TrendView |
| R4 时段热力图 | Task 5 heatmap（本地口径）+ Task 13 HeatmapView |
| R5 CSV/JSON 导出 | Task 7 ExportService + Task 11 allRows + Task 13 ExportView |
| R6 按小时粒度持久化派生 | Task 2 TimeBucket + Task 3-5 ClickStore |
| R7 自启 + 崩溃拉起 | Task 14 LaunchAgentService（SMAppService.agent KeepAlive）+ Task 15 单实例 |
| R8 极轻量 7×24 | Task 6 加锁计数 + Task 10 定时落库（回调路径极短）|
| R9 隐私本地 | 全程本地 SQLite，无网络代码；Task 13 打开数据目录 |
| R10 权限申请/检测/引导 | Task 8 PermissionManager + Task 13 PermissionView + Task 15 故障可见 |

---
