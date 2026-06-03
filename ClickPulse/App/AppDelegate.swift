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
        // 测试环境下跳过整套启动逻辑：避免单实例仲裁 / 事件 tap / 真实数据库副作用干扰单元测试
        if NSClassFromString("XCTestCase") != nil { return }
        NSApp.setActivationPolicy(.accessory)

        // 单实例仲裁：已有实例（通常是 launchd 托管的权威实例）则本实例干净退出
        let others = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.liuzhuo.clickpulse")
            .filter { $0 != .current }
        if !others.isEmpty { NSApp.terminate(nil); return }

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
        eventTap.onClick = { [weak self] button in
            self?.counter.increment(button)
            DispatchQueue.main.async { self?.stats.bump(button) }   // 乐观更新：点击即跳
        }
        eventTap.onHealthChange = { [weak self] healthy in
            DispatchQueue.main.async { self?.updateHealth(healthy) }
        }
        aggregator.onFlush = { [weak self] in
            self?.syncPermissionAndTap()
            self?.stats.refresh()
            self?.refreshIcon()
        }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }

        syncPermissionAndTap()   // 已授权则启动 tap；未授权则等轮询恢复
        aggregator.start()
        stats.refresh()
        refreshIcon()

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

    @objc private func willSleep() { aggregator?.flush() }

    func applicationWillTerminate(_ notification: Notification) { aggregator?.flush() }

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
