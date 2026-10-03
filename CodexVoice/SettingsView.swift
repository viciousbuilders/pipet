import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: PipetModel = .shared
    @State private var tab = "Dictation"
    @State private var practice = ""
    @State private var copied = false
    @FocusState private var practiceFocused: Bool
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    init(model: PipetModel = .shared, initialTab: String = "Dictation") {
        self.model = model
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if tab == "Dictation" {
                        instruction
                        PipetSetupView(model: model)
                        practiceCard
                        if let transcript = model.lastTranscript { transcriptCard(transcript) }
                    } else {
                        PipetPreferencesView(model: model)
                    }
                }
                .padding(.horizontal, 28).padding(.bottom, 24)
            }
            footer.padding(.horizontal, 28).padding(.vertical, 16)
        }
        .font(.system(size: 13))
        .foregroundStyle(PipetTheme.ink)
        .tint(PipetTheme.accent)
        .background(PipetTheme.background)
        .frame(minWidth: 520, idealWidth: 620, minHeight: 600, idealHeight: 760)
        .task { model.refreshPermissions(); await model.refreshCodex() }
        .onReceive(timer) { _ in
            model.refreshPermissions()
            Task { await model.refreshCodex() }
        }
        .onChange(of: model.lastTranscript) { _, _ in copied = false }
        .onChange(of: tab) { _, _ in practiceFocused = false }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshAccess()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            PipetLogo(size: 66)
            VStack(alignment: .leading, spacing: 2) {
                Text("Pipet").font(.system(size: 30, weight: .bold, design: .rounded))
                HStack(spacing: 3) {
                    Text("by").foregroundStyle(PipetTheme.secondary)
                    Link("viciousbuilders", destination: URL(string: "https://viciousbuilders.com")!)
                        .help("Visit viciousbuilders.com")
                }
                .font(.system(size: 12))
            }
            Spacer()
            Picker("Pipet pages", selection: $tab) {
                Text("Dictation").tag("Dictation")
                Text("Settings").tag("Settings")
            }
            .pickerStyle(.segmented).labelsHidden()
            .frame(width: 170)
        }
    }

    private var instruction: some View {
        HStack(alignment: .center, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Say it. See it typed.")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                Text("Click a text field in any app. Hold Control-M, speak, and release to insert your words.")
                    .foregroundStyle(PipetTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
            }
            Spacer(minLength: 0)
            ShortcutKeys()
        }
        .padding(.vertical, 4)
    }

    private var practiceCard: some View {
        PipetCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Try a little hello").font(.system(size: 16, weight: .semibold, design: .rounded))
                    Spacer()
                    Button("Clear") { practice = ""; practiceFocused = true }
                        .buttonStyle(.borderless).disabled(practice.isEmpty)
                }
                ZStack(alignment: .topLeading) {
                    if practice.isEmpty && !practiceFocused {
                        Text("Click here, hold Control-M, and say something.")
                            .foregroundStyle(PipetTheme.secondary)
                            .padding(.horizontal, 10).padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $practice)
                        .font(.system(size: 14)).scrollContentBackground(.hidden)
                        .scrollIndicators(.hidden)
                        .padding(5).focused($practiceFocused)
                        .accessibilityLabel("Practice dictation text")
                        .accessibilityHint("Click here, then hold Control M and speak. Release to insert the transcript.")
                }
                .frame(height: 100)
                .background(PipetTheme.inset.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(practiceFocused ? PipetTheme.accent : PipetTheme.rule, lineWidth: practiceFocused ? 2 : 1))
                .background(EditorFocusDismissal(isFocused: practiceFocused) {
                    practiceFocused = false
                })
                dictationStatus
            }
        }
    }

    @ViewBuilder private var dictationStatus: some View {
        switch model.state {
        case .idle:
            EmptyView()
        case .starting:
            status("Starting your microphone…", symbol: "mic", color: PipetTheme.accent)
        case .recording:
            status("Listening. Release Control-M when you’re done.", symbol: "waveform", color: PipetTheme.accent)
        case .transcribing:
            status("Turning your voice into words…", symbol: "ellipsis.bubble", color: PipetTheme.accent)
        case .inserting:
            status("Putting your words at the cursor…", symbol: "text.cursor", color: PipetTheme.accent)
        case .error(let message):
            status(message, symbol: "exclamationmark.circle", color: PipetTheme.accent)
        }
    }

    private func status(_ text: String, symbol: String, color: Color) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 12, weight: .medium))
            .foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.updatesFrequently)
    }

    private func transcriptCard(_ transcript: String) -> some View {
        PipetCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Your last words").font(.system(size: 16, weight: .semibold, design: .rounded))
                    Spacer()
                    Button {
                        model.copyTranscript(); copied = true
                    } label: { Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") }
                    .buttonStyle(.bordered)
                }
                Text(transcript).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Text("Kept only until you quit Pipet.")
                    .font(.system(size: 12)).foregroundStyle(PipetTheme.secondary)
            }
        }
    }

    private var footer: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield").accessibilityHidden(true)
            Text("Audio goes to OpenAI for transcription. Temporary recordings are deleted after each attempt.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11)).foregroundStyle(PipetTheme.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PipetTheme.background)
    }
}

/// Watches clicks without intercepting them, so buttons and links still work.
private struct EditorFocusDismissal: NSViewRepresentable {
    var isFocused: Bool
    var dismiss: () -> Void

    func makeNSView(context: Context) -> FocusBoundaryView {
        FocusBoundaryView()
    }

    func updateNSView(_ view: FocusBoundaryView, context: Context) {
        view.isFocused = isFocused
        view.dismiss = dismiss
    }

    static func dismantleNSView(_ view: FocusBoundaryView, coordinator: ()) {
        view.stopMonitoring()
    }

    final class FocusBoundaryView: NSView {
        var isFocused = false
        var dismiss: (() -> Void)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
                let consumed = MainActor.assumeIsolated {
                    guard let self, self.isFocused, let window = self.window, event.window === window else { return false }
                    let escape = event.type == .keyDown && event.keyCode == 53
                    let outside = event.type != .keyDown && !self.bounds.contains(self.convert(event.locationInWindow, from: nil))
                    if escape || outside {
                        window.makeFirstResponder(nil)
                        self.dismiss?()
                    }
                    return escape
                }
                return consumed ? nil : event
            }
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
