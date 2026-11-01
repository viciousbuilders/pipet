import Foundation

@main
struct TextInsertionPolicyTests {
    @MainActor
    static func main() throws {
        let suite = "Pipet.InsertionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = InsertionPreferences(defaults: defaults)
        for bundleID in ["dev.custom.editor", "com.apple.TextEdit", "au.vietbrosinaus.pipet"] {
            precondition(preferences.method(for: bundleID) == .paste, "All apps must default to paste")
        }
        preferences.set(.accessibility, for: "dev.custom.editor")
        precondition(InsertionPreferences(defaults: defaults).method(for: "dev.custom.editor") == .accessibility)
        precondition(preferences.method(for: "com.t3tools.t3code") == .automatic)
        preferences.set(nil, for: "dev.custom.editor")
        precondition(preferences.method(for: "dev.custom.editor") == .paste)
        defaults.set(["dev.custom.editor": "invalid"], forKey: InsertionPreferences.overridesKey)
        precondition(preferences.method(for: "dev.custom.editor") == .paste)

        precondition(preferences.method(for: "com.anthropic.claudefordesktop") == .automatic)
        preferences.set(.paste, for: "com.t3tools.t3code")
        precondition(preferences.method(for: "com.t3tools.t3code") == .paste, "Explicit paste must override automatic")
        preferences.set(nil, for: "com.t3tools.t3code")
        precondition(preferences.method(for: "com.t3tools.t3code") == .automatic)

        func find(_ nodes: [Int: [Int]], _ kinds: [Int: EditableTargetSearch.Kind], failAt: Int? = nil) -> Int? {
            EditableTargetSearch.find(root: 0, children: { $0 == failAt ? nil : nodes[$0, default: []] }, classify: { kinds[$0] ?? .container })
        }
        precondition(find([:], [0: .editor(focused: true)]) == 0)
        precondition(find([0: [1], 1: [2]], [2: .editor(focused: false)]) == 2, "Find an editor nested in a focused web container")
        precondition(find([0: [1, 2]], [1: .editor(focused: false), 2: .editor(focused: true)]) == 2)
        precondition(find([0: [1, 2]], [1: .editor(focused: false), 2: .editor(focused: false)]) == nil, "Do not guess between editors")
        precondition(find([0: [1, 2]], [1: .editor(focused: true), 2: .editor(focused: true)]) == nil)
        precondition(find([0: [1], 1: [2]], [1: .blocked, 2: .editor(focused: true)]) == nil, "Do not traverse secure or disabled controls")
        precondition(find([0: [1, 2]], [1: .editor(focused: false)], failAt: 2) == nil, "Incomplete search cannot choose a candidate")
        precondition(find([0: [1, 2]], [1: .editor(focused: false), 2: .unavailable]) == nil)
        precondition(find([0: [0]], [:]) == nil, "Cycles must terminate")
        precondition(find([0: Array(1...257)], [1: .editor(focused: true)]) == nil, "Large searches must fail closed")

        for bundleID in ["com.t3tools.t3code", "com.anthropic.claudefordesktop"] {
            precondition(preferences.writeMethod(for: bundleID) == .paste, "Electron composers need paste input events")
            preferences.set(.accessibility, for: bundleID)
            precondition(preferences.writeMethod(for: bundleID) == .accessibility, "Explicit direct override remains available")
            preferences.set(nil, for: bundleID)
        }
        preferences.set(.automatic, for: "dev.custom.editor")
        precondition(preferences.writeMethod(for: "dev.custom.editor") == .automatic)

        let emoji = InsertionSnapshot(value: "Hi 🐱 there", selection: NSRange(location: 3, length: 2))
        precondition(emoji.expectedValue(inserting: "世界") == "Hi 世界 there", "Ranges must use UTF-16")
        let caret = InsertionSnapshot(value: "abc", selection: NSRange(location: 3, length: 0))
        precondition(caret.expectedValue(inserting: "\nhello") == "abc\nhello")
        precondition(InsertionSnapshot(value: "", selection: NSRange(location: 0, length: 0)).expectedValue(inserting: "hello") == "hello")
        precondition(InsertionSnapshot(value: "abc", selection: NSRange(location: NSNotFound, length: 1)).expectedValue(inserting: "x") == nil)
        precondition(InsertionSnapshot(value: "abc", selection: NSRange(location: 2, length: Int.max)).expectedValue(inserting: "x") == nil)
        precondition(InsertionSnapshot(value: nil, selection: nil).expectedValue(inserting: "x") == nil)
        precondition(caret != InsertionSnapshot(value: "abc", selection: NSRange(location: 0, length: 0)), "Moved selection must invalidate target")
        precondition(caret != InsertionSnapshot(value: "abcd", selection: caret.selection), "Edited field must invalidate target")
        print("Text insertion regression checks passed")
    }
}
