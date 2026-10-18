import Carbon
import AppKit
import Foundation

/// Distinguish the two Command keys and leave ordinary Command chords alone.
/// Once interrupted, wait for a fresh press before starting another dictation.
struct DictationHotkeyGesture {
    enum Action: Equatable { case arm, release, cancel }
    private(set) var rightCommandDown = false
    private var armed = false
    private var recording = false

    mutating func flagsChanged(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Action? {
        let wasDown = rightCommandDown
        rightCommandDown = flags.rawValue & UInt(NX_DEVICERCMDKEYMASK) != 0
        if !rightCommandDown {
            armed = false
            guard recording else { return nil }
            recording = false
            return .release
        }
        let otherModifiers: NSEvent.ModifierFlags = [.shift, .control, .option, .function]
        let leftCommandDown = flags.rawValue & UInt(NX_DEVICELCMDKEYMASK) != 0
        if !flags.intersection(otherModifiers).isEmpty || leftCommandDown {
            return interrupt()
        }
        guard !wasDown, keyCode == UInt16(kVK_RightCommand) else { return nil }
        armed = true
        return .arm
    }

    mutating func keyDown() -> Action? { interrupt() }

    mutating func activate() -> Bool {
        guard armed, rightCommandDown else { return false }
        armed = false
        recording = true
        return true
    }

    mutating func reset() -> Action? {
        let action = interrupt()
        rightCommandDown = false
        return action
    }

    private mutating func interrupt() -> Action? {
        armed = false
        guard recording else { return nil }
        recording = false
        return .cancel
    }
}

@MainActor
final class HotkeyMonitor {
    private let onPress: () -> Void
    private let onRelease: () -> Void
    private let onCancel: () -> Void
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var pendingPress: Task<Void, Never>?
    private var gesture = DictationHotkeyGesture()

    init(onPress: @escaping () -> Void, onRelease: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.onPress = onPress
        self.onRelease = onRelease
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
            : gesture.keyDown()
        pendingPress?.cancel()
        pendingPress = nil
        switch action {
        case .arm:
            // Briefly wait to distinguish a hold from shortcuts like Command-C.
            pendingPress = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(150)) }
                catch { return }
                guard let self else { return }
                guard CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_RightCommand)) else {
                    self.reset()
                    return
                }
                guard self.gesture.activate() else { return }
                self.onPress()
            }
        case .release: onRelease()
        case .cancel: onCancel()
        case nil: break
        }
    }

    private func reset() {
        pendingPress?.cancel()
        pendingPress = nil
        if gesture.reset() == .cancel { onCancel() }
    }
}
