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
                Section("Text insertion") {
                    Text("Paste is the default for every app, including web editors. If an app blocks paste, add it below and choose Direct insertion.")
                        .foregroundStyle(PipetTheme.secondary)
                    ForEach(model.insertionOverrides.keys.sorted(), id: \.self) { bundleID in
                        HStack {
                            Picker(model.insertionAppName(for: bundleID), selection: Binding(
                                get: { InsertionMethod(rawValue: model.insertionOverrides[bundleID] ?? "") ?? .paste },
                                set: { model.setInsertionMethod($0, for: bundleID) }
                            )) {
                                Text("Paste").tag(InsertionMethod.paste)
                                Text("Direct insertion").tag(InsertionMethod.accessibility)
                            }
                            Button("Remove") { model.setInsertionMethod(nil, for: bundleID) }
                                .accessibilityLabel("Remove override for \(model.insertionAppName(for: bundleID))")
                        }
                    }
                    Button("Add app…") { model.addInsertionApp() }
                    Text("If the destination changes, Pipet stops. If insertion cannot be verified, check the field before copying your last transcript.")
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
                    Link("Made by viciousbuilders", destination: URL(string: "https://viciousbuilders.com")!)
                    Text("Built on Codex Voice by Anthony Kroeger (anthnykr). Thanks to the GOAT.")
                    Link("Original project and MIT license", destination: URL(string: "https://github.com/anthnykr/codex-voice")!)
                }
            }
            .formStyle(.grouped).scrollContentBackground(.hidden).scrollDisabled(true).frame(height: 960 + CGFloat(model.insertionOverrides.count) * 44)
            if let error = model.settingsError {
                Label(error, systemImage: "exclamationmark.circle").foregroundStyle(PipetTheme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
