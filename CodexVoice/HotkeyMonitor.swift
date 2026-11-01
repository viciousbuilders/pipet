import Carbon
import AppKit
import Foundation

/// Recognize a standalone Right Command press/release, without consuming chords.
/// Recording state belongs to DictationController so errors cannot desynchronize it.
struct DictationHotkeyGesture {
    enum Action: Equatable { case toggle, cancel }
    private(set) var rightCommandDown = false
    private var standalone = false

    mutating func flagsChanged(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Action? {
        let wasDown = rightCommandDown
        rightCommandDown = flags.rawValue & UInt(NX_DEVICERCMDKEYMASK) != 0
        let otherModifiers: NSEvent.ModifierFlags = [.shift, .control, .option, .function]
        let leftCommandDown = flags.rawValue & UInt(NX_DEVICELCMDKEYMASK) != 0
        let hasOtherModifier = !flags.intersection(otherModifiers).isEmpty || leftCommandDown
        if !rightCommandDown {
            let shouldToggle = wasDown && standalone && !hasOtherModifier
                && keyCode == UInt16(kVK_RightCommand)
            standalone = false
            return shouldToggle ? .toggle : nil
        }
        if hasOtherModifier {
            standalone = false
        } else if !wasDown && keyCode == UInt16(kVK_RightCommand) {
            standalone = true
        }
        return nil
    }

    mutating func keyDown(keyCode: UInt16) -> Action? {
        standalone = false
        return keyCode == UInt16(kVK_Escape) ? .cancel : nil
    }

    mutating func reset() {
        standalone = false
        rightCommandDown = false
    }
}

@MainActor
final class HotkeyMonitor {
    private let onToggle: () -> Void
    private let onCancel: () -> Void
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var gesture = DictationHotkeyGesture()

    init(onToggle: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.onToggle = onToggle
        self.onCancel = onCancel
    }

    func start() {
        guard localMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        // AppKit delivers both monitor handlers on the main thread. Observe
        // rather than consume events, so Command shortcuts still reach apps.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }
        let notifications = NSWorkspace.shared.notificationCenter
        // System shortcuts such as Command-Tab may bypass event monitors.
        // A changed app must cancel rather than dictate into a new destination.
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.didActivateApplicationNotification] {
            workspaceObservers.append(notifications.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reset() }
            })
        }
        DebugLogger.write("Right Command hotkey monitor started")
    }

    func stop() {
        reset()
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        let notifications = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers { notifications.removeObserver(observer) }
        globalMonitor = nil
        localMonitor = nil
        workspaceObservers.removeAll()
    }

    private func handle(_ event: NSEvent) {
        let action = event.type == .flagsChanged
            ? gesture.flagsChanged(keyCode: event.keyCode, flags: event.modifierFlags)
            : gesture.keyDown(keyCode: event.keyCode)
        switch action {
        case .toggle: onToggle()
        case .cancel: onCancel()
        case nil: break
        }
    }

    private func reset() {
        gesture.reset()
        onCancel()
    }
}
