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
