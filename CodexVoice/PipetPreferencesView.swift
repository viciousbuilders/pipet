import AppKit
import SwiftUI

struct PipetPreferencesView: View {
    @ObservedObject var model: PipetModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Make Pipet feel at home").font(.system(size: 24, weight: .semibold, design: .rounded))
            Form {
                Section("Everyday use") {
                    Toggle("Open Pipet when I log in", isOn: Binding(get: { model.loginEnabled }, set: { model.setOpenAtLogin($0) }))
                    Text("Pipet lives in your menu bar. Hold Control-M in any editable text field to dictate.")
                        .foregroundStyle(PipetTheme.secondary)
                }
                Section("Permissions") {
                    HStack {
                        Label("Microphone", systemImage: "mic")
                        Spacer()
                        Button("Open Settings") { model.allowMicrophone() }
                    }
                    HStack {
                        Label("Text insertion", systemImage: "text.cursor")
                        Spacer()
                        Button("Open Settings") { model.allowAccessibility() }
                    }
                }
                Section("Your words stay yours") {
                    Text("Pipet reads your local Codex sign-in to transcribe using your account. Audio is sent to OpenAI after you release Control-M. An internet connection is required.")
                    Text("Temporary audio is deleted after each attempt. Your last transcript stays in memory until you quit. Pipet does not automatically send messages or submit forms.")
                    Text("Clipboard contents are restored after insertion, unless you copy something else in the meantime.")
                }
                Section("About") {
                    LabeledContent("Pipet", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0")
                    Link("Made by vietbrosinaus", destination: URL(string: "https://vietbrosinaus.com")!)
                    Text("Built on Codex Voice by Anthony Kroeger (anthnykr). Thanks to the GOAT.")
                    Link("Original project and MIT license", destination: URL(string: "https://github.com/anthnykr/codex-voice")!)
                }
            }
            .formStyle(.grouped).scrollContentBackground(.hidden).scrollDisabled(true).frame(height: 760)
            if let error = model.settingsError {
                Label(error, systemImage: "exclamationmark.circle").foregroundStyle(PipetTheme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
