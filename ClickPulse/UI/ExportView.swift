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
