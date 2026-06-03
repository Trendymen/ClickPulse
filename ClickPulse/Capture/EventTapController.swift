import CoreGraphics
import AppKit

final class EventTapController {
    /// 每次点击回调（在主 run loop 线程）
    var onClick: ((MouseButton) -> Void)?
    /// 健康状态变化：true=正常监听中，false=tap 创建/重建失败
    var onHealthChange: ((Bool) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var healthTimer: Timer?

    func start() {
        installTap()
        healthTimer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
            self?.verifyHealth()
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    func stop() {
        healthTimer?.invalidate(); healthTimer = nil
        teardownTap()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func didWake() { rebuild() }   // 唤醒后立即重建，不等 Timer

    private func installTap() {
        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let ctrl = Unmanaged<EventTapController>.fromOpaque(refcon!).takeUnretainedValue()
            ctrl.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask, callback: callback, userInfo: refcon) else {
            onHealthChange?(false); return
        }
        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        onHealthChange?(true)
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        let button: MouseButton
        switch type {
        case .leftMouseDown:  button = .left
        case .rightMouseDown: button = .right
        case .otherMouseDown:
            button = event.getIntegerValueField(.mouseEventButtonNumber) == 2 ? .middle : .other
        default: return
        }
        onClick?(button)
    }

    private func verifyHealth() {
        guard let tap = tap, CGEvent.tapIsEnabled(tap: tap) else { rebuild(); return }
    }

    private func rebuild() { teardownTap(); installTap() }

    private func teardownTap() {
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        runLoopSource = nil
        tap = nil
    }
}
