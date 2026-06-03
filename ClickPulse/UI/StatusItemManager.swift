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
        statusItem.button?.action = #selector(buttonClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        setState(.ok)
    }

    func setState(_ state: IconState) {
        let symbol = state == .ok ? "cursorarrow.click" : "exclamationmark.triangle"
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "ClickPulse")
        img?.isTemplate = true
        statusItem.button?.image = img
        statusItem.button?.appearsDisabled = (state == .warning)
    }

    @objc private func buttonClicked() {
        let isRight = NSApp.currentEvent?.type == .rightMouseUp
            || NSApp.currentEvent?.modifierFlags.contains(.control) == true
        if isRight { showContextMenu() } else { togglePopover() }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu() {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()
        let quit = NSMenuItem(title: "退出 ClickPulse", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
