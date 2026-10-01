import AppKit

@MainActor
final class AppController {
    private let permissionCoordinator = PermissionCoordinator()
    private let textInsertionService = TextInsertionService()
    private lazy var audioCaptureService = AudioCaptureService(permissionCoordinator: permissionCoordinator)
    private let authService = CodexAuthService()
    private lazy var transcriptionService = CodexTranscriptionService(authService: authService)
    private lazy var dictationController = DictationController(
        permissionCoordinator: permissionCoordinator,
        audioCaptureService: audioCaptureService,
        transcriptionService: transcriptionService,
        textInsertionService: textInsertionService
    )
    private let hudController = DictationHUDController()
    private lazy var statusItemController = StatusItemController(
        permissionCoordinator: permissionCoordinator,
        dictationController: dictationController
    )
    private lazy var hotkeyMonitor = HotkeyMonitor(
        onPress: { [weak self] in
            self?.dictationController.handleHotkeyPressed()
        },
        onRelease: { [weak self] in
            self?.dictationController.handleHotkeyReleased()
        }
    )

    func openWindow() { statusItemController.openSettings() }
    func stop() { audioCaptureService.cancel() }

    func start() {
        DebugLogger.clear()
        DebugLogger.write("App start")
        statusItemController.start()
        dictationController.onStateChange = { [weak self] state in
            DebugLogger.write("State changed: \(state.statusText)")
            PipetModel.shared.state = state
            PipetModel.shared.lastTranscript = self?.dictationController.lastTranscript
            self?.statusItemController.handleStateChange(state)
            self?.hudController.update(for: state)
        }
        hotkeyMonitor.start()
        if !UserDefaults.standard.bool(forKey: "hasOpenedSetup") {
            statusItemController.openSettings()
            UserDefaults.standard.set(true, forKey: "hasOpenedSetup")
        }
    }
}
