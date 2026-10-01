import AppKit
import Foundation
import SwiftUI

@MainActor
final class StatusItemController {
    private let permissionCoordinator: PermissionCoordinator
    private let dictationController: DictationController

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var settingsWindow: NSWindow?

    init(permissionCoordinator: PermissionCoordinator, dictationController: DictationController) {
        self.permissionCoordinator = permissionCoordinator
        self.dictationController = dictationController
    }

    func start() {
        configureButton()
        configureMenu()
        updateAppearance(for: .idle)
    }

    func handleStateChange(_ state: DictationController.State) {
        updateAppearance(for: state)
        statusItem.menu?.items.first(where: { $0.action == #selector(copyLastTranscript) })?.isEnabled = dictationController.lastTranscript != nil
    }

    private func configureButton() {
        statusItem.button?.image = NSImage(systemSymbolName: "bubble.left.fill", accessibilityDescription: "Pipet")
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.toolTip = "Pipet. Hold Control-M to dictate."
    }

    private func configureMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Hold Control-M to dictate", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        let copyItem = NSMenuItem(title: "Copy Last Transcript", action: #selector(copyLastTranscript), keyEquivalent: "")
        copyItem.target = self
        copyItem.isEnabled = false
        menu.addItem(copyItem)
        menu.addItem(.separator())

        let accessibilityItem = NSMenuItem(title: "Open Accessibility Settings", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        let settingsItem = NSMenuItem(title: "Open Pipet…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let restartItem = NSMenuItem(title: "Restart Pipet", action: #selector(restart), keyEquivalent: "")
        restartItem.target = self
        menu.addItem(restartItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Pipet", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func updateAppearance(for state: DictationController.State) {
        let symbol = switch state {
        case .idle: "bubble.left.fill"
        case .recording: "waveform"
        case .starting, .transcribing: "ellipsis.bubble.fill"
        case .inserting: "text.cursor"
        case .error: "exclamationmark.bubble.fill"
        }
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Pipet: \(state.statusText)")
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.title = ""

        statusItem.button?.toolTip = "Pipet: \(state.statusText)"
    }

    @objc
    private func openAccessibilitySettings() {
        permissionCoordinator.openAccessibilitySettings()
    }

    @objc
    func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Pipet"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView())
            window.minSize = NSSize(width: 520, height: 620)
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func copyLastTranscript() {
        guard let transcript = dictationController.lastTranscript else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
    }

    @objc
    private func restart() { PipetModel.shared.restart() }

    @objc
    private func quit() {
        NSApp.terminate(nil)
    }
}
