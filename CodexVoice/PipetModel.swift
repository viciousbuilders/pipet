import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class PipetModel: ObservableObject {
    static let shared = PipetModel()
    @Published var state: DictationController.State = .idle
    @Published var lastTranscript: String?
    @Published var microphoneReady = false
    @Published var accessibilityReady = false
    @Published var codexReady = false
    @Published var checkingCodex = true
    @Published var requestingMicrophone = false
    @Published var loginEnabled = false
    @Published var settingsError: String?
    @Published var restarting = false
    @Published var insertionOverrides = InsertionPreferences().overrides
    private let permissions = PermissionCoordinator()
    private let auth = CodexAuthService()

    var ready: Bool { microphoneReady && accessibilityReady && codexReady }
    var readyCount: Int { [microphoneReady, accessibilityReady, codexReady].filter { $0 }.count }

    func refreshPermissions() {
        microphoneReady = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityReady = AXIsProcessTrusted()
        loginEnabled = SMAppService.mainApp.status == .enabled
    }

    func refreshCodex() async {
        codexReady = (try? await auth.currentCredentials()) != nil
        checkingCodex = false
    }

    func allowMicrophone() {
        guard !requestingMicrophone else { return }
        if microphoneReady { permissions.openMicrophoneSettings(); return }
        requestingMicrophone = true
        Task { @MainActor in
            let allowed = await permissions.requestMicrophonePermission()
            requestingMicrophone = false
            refreshPermissions()
            if !allowed { permissions.openMicrophoneSettings() }
        }
    }

    func allowAccessibility() {
        _ = permissions.accessibilityStatus(promptIfNeeded: true)
        permissions.openAccessibilitySettings()
    }

    func refreshAccess() {
        refreshPermissions()
        Task { await refreshCodex() }
    }

    func restart() {
        guard !restarting else { return }
        // Keep the current process until LaunchServices has accepted the restart.
        restarting = true
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["--restart-from", String(ProcessInfo.processInfo.processIdentifier)]
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            Task { @MainActor in
                if let error {
                    self.restarting = false
                    self.settingsError = "Could not restart Pipet: \(error.localizedDescription)"
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    func showCodexHelp() {
        if let url = URL(string: "https://developers.openai.com/codex/cli/") { NSWorkspace.shared.open(url) }
    }

    func setOpenAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            settingsError = SMAppService.mainApp.status == .requiresApproval ? "Allow Pipet in System Settings → General → Login Items." : nil
        } catch { settingsError = error.localizedDescription }
        refreshPermissions()
    }

    func setInsertionMethod(_ method: InsertionMethod?, for bundleID: String) {
        InsertionPreferences().set(method, for: bundleID)
        insertionOverrides = InsertionPreferences().overrides
    }

    func addInsertionApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose an app for an insertion override"
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        setInsertionMethod(.paste, for: bundleID)
    }

    func insertionAppName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path)
    }

    func copyTranscript() {
        guard let lastTranscript else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastTranscript, forType: .string)
    }
}
