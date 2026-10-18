import AppKit
import Foundation

@MainActor
final class DictationController {
    enum State {
        case idle
        case starting
        case recording
        case transcribing
        case inserting
        case error(String)

        var statusText: String {
            switch self {
            case .idle:
                return "Idle"
            case .starting:
                return "Starting microphone…"
            case .recording:
                return "Listening…"
            case .transcribing:
                return "Transcribing with Codex…"
            case .inserting:
                return "Inserting…"
            case .error(let message):
                return message
            }
        }
    }

    private let permissionCoordinator: PermissionCoordinator
    private let audioCaptureService: AudioCaptureService
    private let transcriptionService: CodexTranscriptionService
    private let textInsertionService: TextInsertionService

    private(set) var state: State = .idle {
        didSet {
            onStateChange?(state)
        }
    }

    var onStateChange: ((State) -> Void)?
    private var hotkeyHeld = false
    private var recordingCancelled = false
    private var targetPID: pid_t?
    private var insertionTarget: TextInsertionService.Target?
    private(set) var lastTranscript: String?

    init(
        permissionCoordinator: PermissionCoordinator,
        audioCaptureService: AudioCaptureService,
        transcriptionService: CodexTranscriptionService,
        textInsertionService: TextInsertionService
    ) {
        self.permissionCoordinator = permissionCoordinator
        self.audioCaptureService = audioCaptureService
        self.transcriptionService = transcriptionService
        self.textInsertionService = textInsertionService
    }

    func handleHotkeyPressed() {
        switch state {
        case .starting, .recording, .transcribing, .inserting:
            DebugLogger.write("Hotkey press ignored because state=\(state.statusText)")
            return
        case .idle, .error:
            break
        }

        DebugLogger.write("Hotkey pressed")
        hotkeyHeld = true
        recordingCancelled = false
        targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        insertionTarget = nil
        state = .starting
        Task { @MainActor in
            await beginDictation()
        }
    }

    func handleHotkeyReleased() {
        hotkeyHeld = false
        guard case .recording = state else {
            DebugLogger.write("Hotkey release ignored because state=\(state.statusText)")
            return
        }

        DebugLogger.write("Hotkey released")
        Task { @MainActor in
            await finishDictation()
        }
    }

    func cancelRecording() {
        switch state {
        case .starting:
            // Keep starting occupied until beginDictation returns from its
            // pending permission/target work, so a new recording cannot race it.
            hotkeyHeld = false
            recordingCancelled = true
            audioCaptureService.cancel()
        case .recording:
            hotkeyHeld = false
            recordingCancelled = true
            audioCaptureService.cancel()
            insertionTarget = nil
            state = .idle
        case .idle, .transcribing, .inserting, .error:
            break
        }
    }

    private func beginDictation() async {
        do {
            guard case .trusted = permissionCoordinator.accessibilityStatus(promptIfNeeded: false) else {
                state = .error("Open Pipet and enable text insertion to get started.")
                return
            }
            let target = if let targetPID {
                await textInsertionService.captureTarget(expectedPID: targetPID)
            } else {
                nil as TextInsertionService.Target?
            }
            guard hotkeyHeld, !recordingCancelled else { state = .idle; return }
            guard let target else {
                state = .error("Click an editable field before holding Right Command. Secure fields are not supported.")
                return
            }
            insertionTarget = target
            try await audioCaptureService.start()
            guard hotkeyHeld else {
                audioCaptureService.cancel()
                state = .idle
                return
            }
            state = .recording
        } catch {
            if recordingCancelled { state = .idle; return }
            if case AudioCaptureError.authorizationDenied = error {
                permissionCoordinator.openMicrophoneSettings()
            }
            DebugLogger.write("Begin dictation failed: \(error.localizedDescription)")
            state = .error(error.localizedDescription)
        }
    }

    private func finishDictation() async {
        state = .transcribing
        guard let recording = audioCaptureService.stop() else {
            state = .idle
            return
        }

        let transcript: String
        do {
            transcript = try await transcriptionService.transcribe(recording)
        } catch {
            audioCaptureService.deleteRecording(recording)
            if case AudioCaptureError.authorizationDenied = error {
                permissionCoordinator.openMicrophoneSettings()
            }
            DebugLogger.write("Finish dictation failed during transcription: \(error.localizedDescription)")
            state = .error(error.localizedDescription)
            return
        }

        audioCaptureService.deleteRecording(recording)

        guard !transcript.isEmpty else {
            DebugLogger.write("Transcript was empty")
            state = .idle
            return
        }

        lastTranscript = transcript
        guard let insertionTarget else {
            state = .error("Use Copy Last Transcript in the Pipet menu.")
            return
        }
        state = .inserting
        switch permissionCoordinator.accessibilityStatus(promptIfNeeded: true) {
        case .trusted:
            switch await textInsertionService.insert(transcript, into: insertionTarget) {
            case .confirmed:
                state = .idle
            case .unverified:
                state = .error("Insertion could not be verified. Check the field before using Copy Last Transcript.")
            case .failed(let message):
                state = .error(message)
            }
        case .needsPrompt:
            permissionCoordinator.openAccessibilitySettings()
            DebugLogger.write("Accessibility permission missing at insert time")
            state = .error("Grant Accessibility")
        }
    }
}
