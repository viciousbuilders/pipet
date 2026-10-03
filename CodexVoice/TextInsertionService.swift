import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

enum InsertionMethod: String, CaseIterable {
    case paste
    case accessibility
}

@MainActor
struct InsertionPreferences {
    static let overridesKey = "insertionMethodOverrides"
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var overrides: [String: String] { defaults.dictionary(forKey: Self.overridesKey) as? [String: String] ?? [:] }

    func method(for bundleID: String) -> InsertionMethod {
        InsertionMethod(rawValue: overrides[bundleID] ?? "") ?? .paste
    }

    func set(_ method: InsertionMethod?, for bundleID: String) {
        var values = overrides
        values[bundleID] = method?.rawValue
        defaults.set(values, forKey: Self.overridesKey)
    }
}

struct InsertionSnapshot: Equatable, Sendable {
    let value: String?
    let selection: NSRange?

    func expectedValue(inserting text: String) -> String? {
        guard let value, let selection else { return nil }
        let current = value as NSString
        // Accessibility ranges use UTF-16, not Swift character counts.
        guard selection.location >= 0, selection.length >= 0,
              selection.location <= current.length,
              selection.length <= current.length - selection.location else { return nil }
        return current.replacingCharacters(in: selection, with: text)
    }
}

@MainActor
final class TextInsertionService {
    // AX references are immutable IPC handles. The dedicated actor owns all reads
    // and writes; sending a retained handle across executors does not access AppKit.
    struct Target: @unchecked Sendable {
        let pid: pid_t
        let bundleID: String
        let element: AXUIElement
        let snapshot: InsertionSnapshot
    }

    enum Result {
        case confirmed
        case unverified
        case failed(String)
    }

    private let accessibility = AccessibilityClient()

    func captureTarget(expectedPID: pid_t? = nil) async -> Target? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              expectedPID == nil || app.processIdentifier == expectedPID else { return nil }
        let target = await accessibility.capture(pid: app.processIdentifier, bundleID: app.bundleIdentifier ?? "unknown")
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return nil }
        return target
    }

    func insert(_ text: String, into target: Target) async -> Result {
        guard !text.isEmpty else { return .failed("No words to insert.") }
        guard await waitForModifiersToRelease() else {
            return .failed("Release the shortcut keys, then use Copy Last Transcript.")
        }
        // Give the application time to process the shortcut's key-up events.
        try? await Task.sleep(for: .milliseconds(100))
        guard await targetIsCurrent(target) else {
            return .failed("The app, field, or selection changed. Use Copy Last Transcript.")
        }

        let expected = target.snapshot.expectedValue(inserting: text)
        if InsertionPreferences().method(for: target.bundleID) == .accessibility {
            // This explicit override never retries with paste: a partially applied AX
            // edit must not be inserted twice.
            guard await accessibility.insert(text, into: target, expectedValue: expected) else {
                return .failed("Direct insertion could not be confirmed. Check the field before using Copy Last Transcript.")
            }
            return await verify(expectedValue: expected, target: target)
        }
        return await insertViaPasteboard(text, into: target, expectedValue: expected)
    }

    private func targetIsCurrent(_ target: Target) async -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid else { return false }
        let matches = await accessibility.matches(target)
        return matches && NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid
    }

    private func insertViaPasteboard(_ text: String, into target: Target, expectedValue: String?) async -> Result {
        guard await targetIsCurrent(target), modifiersReleased() else {
            return .failed("The destination or shortcut keys changed. Use Copy Last Transcript.")
        }
        let pasteboard = NSPasteboard.general
        let previousItems = pasteboard.pasteboardItems?.map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { result, type in
                if let data = item.data(forType: type) { result[type] = data }
            }
        }
        pasteboard.clearContents()
        let written = pasteboard.setString(text, forType: .string)
        let transcriptChangeCount = pasteboard.changeCount
        defer {
            if pasteboard.changeCount == transcriptChangeCount { restorePasteboard(previousItems) }
        }
        guard written else { return .failed("Could not prepare the clipboard. Use Copy Last Transcript.") }
        guard pasteWithCGEvents() else { return .failed("Could not send paste. Use Copy Last Transcript.") }
        // Keep the temporary clipboard available for at least a second, even if AX
        // confirms early. Editors may read it asynchronously. Never overwrite a copy
        // the user makes in the meantime.
        let result = await verify(expectedValue: expectedValue, target: target)
        return result
    }

    private func verify(expectedValue: String?, target: Target) async -> Result {
        var confirmed = false
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        repeat {
            try? await Task.sleep(for: .milliseconds(50))
            if let expectedValue, !confirmed {
                confirmed = await accessibility.value(of: target) == expectedValue
            }
        } while clock.now < deadline
        DebugLogger.write("Insertion verification: \(confirmed ? "confirmed" : "unverified")")
        return confirmed ? .confirmed : .unverified
    }

    private func waitForModifiersToRelease() async -> Bool {
        for _ in 0 ..< 80 {
            if modifiersReleased() { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return false
    }

    private func modifiersReleased() -> Bool {
        let keys = [kVK_Control, kVK_RightControl, kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift, kVK_Option, kVK_RightOption]
        return !keys.contains(where: { CGEventSource.keyState(.combinedSessionState, key: CGKeyCode($0)) })
    }

    private func pasteWithCGEvents() -> Bool {
        let source = CGEventSource(stateID: .privateState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    private func restorePasteboard(_ items: [[NSPasteboard.PasteboardType: Data]]?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let restored = (items ?? []).map { values in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        if !restored.isEmpty { pasteboard.writeObjects(restored) }
    }
}


private actor AccessibilityClient {
    func capture(pid: pid_t, bundleID: String) -> TextInsertionService.Target? {
        guard let element = focusedElement(in: pid),
              attribute(kAXSubroleAttribute, of: element) as? String != kAXSecureTextFieldSubrole as String else { return nil }
        return TextInsertionService.Target(pid: pid, bundleID: bundleID, element: element, snapshot: snapshot(of: element))
    }

    func matches(_ target: TextInsertionService.Target) -> Bool {
        guard let focused = focusedElement(in: target.pid), CFEqual(focused, target.element) else { return false }
        return snapshot(of: focused) == target.snapshot
    }

    func value(of target: TextInsertionService.Target) -> String? { attribute(kAXValueAttribute, of: target.element) as? String }

    private func focusedElement(in pid: pid_t) -> AXUIElement? {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.5)
        guard let value = attribute(kAXFocusedUIElementAttribute, of: application),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        // Embedded web content can be hosted by a different process. The app's
        // focused-element attribute is authoritative; don't reject its child PID.
        let element = unsafeDowncast(value, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, 0.5)
        return element
    }

    private func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func snapshot(of element: AXUIElement) -> InsertionSnapshot {
        var selection: NSRange?
        if let object = attribute(kAXSelectedTextRangeAttribute, of: element), CFGetTypeID(object) == AXValueGetTypeID() {
            let rangeValue = unsafeDowncast(object, to: AXValue.self)
            var range = CFRange()
            if AXValueGetValue(rangeValue, .cfRange, &range) {
                selection = NSRange(location: range.location, length: range.length)
            }
        }
        return InsertionSnapshot(value: attribute(kAXValueAttribute, of: element) as? String, selection: selection)
    }

    func insert(_ text: String, into target: TextInsertionService.Target, expectedValue: String?) async -> Bool {
        guard matches(target), await MainActor.run(body: { NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid }) else { return false }
        let element = target.element
        let result = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        if result == .success { return true }
        // Only unsupported attributes are safe to fall back from; other errors may
        // represent an edit that was already partly applied.
        guard result == .attributeUnsupported || result == .notImplemented,
              let expectedValue else { return false }
        return AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, expectedValue as CFTypeRef) == .success
    }

}
