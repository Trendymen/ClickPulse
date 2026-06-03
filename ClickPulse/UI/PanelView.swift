import SwiftUI

enum PanelTab: String, CaseIterable { case 趋势, 热力图, 导出, 设置 }

struct PanelView: View {
    @Bindable var stats: StatsProvider
    let store: ClickStore
    let permissionGranted: Bool
    var onRequestPermission: () -> Void = {}

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
                case .设置:   SettingsView()
                }
            }.frame(height: 220)
        }
        .padding(14)
        .frame(width: 360)
    }
}

struct SettingsView: View {
    @State private var launchAtLogin = LaunchAgentService.isEnabled
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("开机自启（登录时打开）", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    try? LaunchAgentService.setEnabled(on)
                }
            Text("数据目录：~/Library/Application Support/com.liuzhuo.clickpulse/")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
