import ServiceManagement

enum LaunchAgentService {
    private static let plistName = "com.liuzhuo.clickpulse.plist"
    private static var agent: SMAppService { SMAppService.agent(plistName: plistName) }

    static var isEnabled: Bool { agent.status == .enabled }

    static func setEnabled(_ on: Bool) throws {
        if on { try agent.register() } else { try agent.unregister() }
    }
}
