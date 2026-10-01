import AppKit
import SwiftUI

@MainActor
final class DictationHUDController {
    private let model = HUDModel()
    private var hideWorkItem: DispatchWorkItem?
    private lazy var panel: NSPanel = {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 94), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: PipetHUD(model: model))
        return panel
    }()

    func update(for state: DictationController.State) {
        hideWorkItem?.cancel()
        model.state = state
        switch state {
        case .idle: hide(after: 0.15)
        case .starting, .recording, .transcribing, .inserting: show()
        case .error: show(); hide(after: 10)
        }
    }

    private func show() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 28))
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    private func hide(after delay: TimeInterval) {
        let item = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}

@MainActor private final class HUDModel: ObservableObject {
    @Published var state: DictationController.State = .idle
}

private struct PipetHUD: View {
    @ObservedObject var model: HUDModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            PipetLogo(size: 56)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(presentation.title).font(.system(size: 15, weight: .semibold, design: .rounded))
                    if presentation.busy { ProgressView().controlSize(.mini) }
                    if presentation.listening {
                        Image(systemName: "waveform")
                            .foregroundStyle(PipetTheme.accent)
                            .symbolEffect(.pulse, isActive: !reduceMotion)
                    }
                }
                Text(presentation.detail).font(.system(size: 11))
                    .foregroundStyle(PipetTheme.secondary).lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(width: 360, height: 94)
        .foregroundStyle(PipetTheme.ink)
        .background(PipetTheme.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(PipetTheme.rule, lineWidth: 1))
    }

    private var presentation: (title: String, detail: String, busy: Bool, listening: Bool) {
        switch model.state {
        case .idle: ("Pipet", "Ready when you are", false, false)
        case .starting: ("Getting ready", "Keep holding Control-M", true, false)
        case .recording: ("I’m listening", "Release Control-M to type your words", false, true)
        case .transcribing: ("Finding your words", "Transcribing with your Codex account", true, false)
        case .inserting: ("Here come your words", "Inserting at your cursor", true, false)
        case .error(let message): ("Let’s try that again", message, false, false)
        }
    }
}
