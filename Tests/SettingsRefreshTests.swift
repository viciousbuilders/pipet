import Combine
import Foundation

@main
struct SettingsRefreshTests {
    @MainActor
    static func main() async {
        let model = PipetModel()
        model.refreshPermissions()
        await model.refreshCodex()

        var changes = 0
        let observation = model.objectWillChange.sink { changes += 1 }
        for _ in 0..<5 {
            model.refreshPermissions()
            await model.refreshCodex()
        }
        precondition(changes == 0, "Unchanged access must not invalidate the settings UI")

        let microphoneReady = model.microphoneReady
        model.microphoneReady.toggle()
        changes = 0
        model.refreshPermissions()
        precondition(model.microphoneReady == microphoneReady)
        precondition(changes == 1, "An actual permission change must still update the UI")

        let codexReady = model.codexReady
        model.codexReady.toggle()
        changes = 0
        await model.refreshCodex()
        precondition(model.codexReady == codexReady)
        precondition(changes == 1, "An actual sign-in change must still update the UI")
        withExtendedLifetime(observation) {}
        print("Settings refresh regression checks passed")
    }
}
