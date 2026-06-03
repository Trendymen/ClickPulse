import ServiceManagement

enum LaunchAgentService {
    /// 现代登录项（macOS 13+）：注册主 App 为登录项，显示在「在登录时打开」，
    /// 开机自启、无 legacy 后台项。代价：不提供崩溃自动拉起（SMAppService 登录项限制）。
    private static var service: SMAppService { SMAppService.mainApp }

    static var isEnabled: Bool { service.status == .enabled }

    static func setEnabled(_ on: Bool) throws {
        if on { try service.register() } else { try service.unregister() }
    }
}
