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
