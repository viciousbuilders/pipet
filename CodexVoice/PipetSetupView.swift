import SwiftUI

struct PipetSetupView: View {
    @ObservedObject var model: PipetModel
    var body: some View {
        PipetCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(model.ready ? "You’re all set" : "A few things before we start")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Spacer()
                    Text("\(model.readyCount) of 3 ready").font(.system(size: 12)).foregroundStyle(PipetTheme.secondary)
                }
                row(title: "Microphone", detail: model.microphoneReady ? "Pipet can hear you while you hold the shortcut." : "Only listens while you hold Control-M.", icon: "mic", ready: model.microphoneReady) {
                    if model.requestingMicrophone {
                        ProgressView().controlSize(.small).accessibilityLabel("Requesting microphone access")
                    } else if !model.microphoneReady {
                        Button("Allow") { model.allowMicrophone() }.buttonStyle(.bordered)
                    }
                }
                Divider().overlay(PipetTheme.rule)
                row(title: "Text insertion", detail: model.accessibilityReady ? "Your words can land in other apps." : "Enable Pipet in macOS Accessibility settings.", icon: "text.cursor", ready: model.accessibilityReady) {
                    if !model.accessibilityReady {
                        Button("Enable") { model.allowAccessibility() }.buttonStyle(.bordered)
                    }
                }
                Divider().overlay(PipetTheme.rule)
                row(title: "Codex sign-in", detail: model.codexReady ? "Connected to your existing Codex account." : "Install Codex CLI and sign in with your account.", icon: "person.crop.circle", ready: model.codexReady) {
                    if model.checkingCodex {
                        ProgressView().controlSize(.small).accessibilityLabel("Checking Codex sign-in")
                    } else if !model.codexReady {
                        Button("Set up") { model.showCodexHelp() }.buttonStyle(.bordered)
                    }
                }
                if !model.accessibilityReady {
                    Divider().overlay(PipetTheme.rule)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Enabled in Settings? Refresh access or restart Pipet.")
                            .font(.system(size: 11)).foregroundStyle(PipetTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Refresh access") { model.refreshAccess() }
                            Button(model.restarting ? "Restarting…" : "Restart Pipet") { model.restart() }
                                .disabled(model.restarting)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                if let error = model.settingsError {
                    Text(error).font(.system(size: 11)).foregroundStyle(PipetTheme.accent)
                }
            }
        }
    }

    private func row<Action: View>(title: String, detail: String, icon: String, ready: Bool, @ViewBuilder action: () -> Action) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 17))
                .foregroundStyle(ready ? PipetTheme.success : PipetTheme.accent)
                .frame(width: 30, height: 34).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(PipetTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if ready {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(PipetTheme.success)
                    .accessibilityLabel("\(title) ready")
            } else { action() }
        }
    }
}
