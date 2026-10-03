import Foundation

@main
struct TextInsertionPolicyTests {
    @MainActor
    static func main() throws {
        let suite = "Pipet.InsertionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = InsertionPreferences(defaults: defaults)
        for bundleID in ["com.t3tools.t3code", "dev.custom.editor", "com.apple.TextEdit", "au.vietbrosinaus.pipet"] {
            precondition(preferences.method(for: bundleID) == .paste, "All apps must default to paste")
        }
        preferences.set(.accessibility, for: "dev.custom.editor")
        precondition(InsertionPreferences(defaults: defaults).method(for: "dev.custom.editor") == .accessibility)
        precondition(preferences.method(for: "com.t3tools.t3code") == .paste)
        preferences.set(nil, for: "dev.custom.editor")
        precondition(preferences.method(for: "dev.custom.editor") == .paste)
        defaults.set(["dev.custom.editor": "invalid"], forKey: InsertionPreferences.overridesKey)
        precondition(preferences.method(for: "dev.custom.editor") == .paste)

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
