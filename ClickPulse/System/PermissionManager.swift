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
