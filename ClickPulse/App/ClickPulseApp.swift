import SwiftUI

@main
struct ClickPulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }   // 纯菜单栏 App：无主窗口，菜单栏由 AppDelegate 装配
    }
}
