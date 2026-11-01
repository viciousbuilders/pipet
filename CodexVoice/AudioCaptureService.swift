import AVFoundation
import Foundation

struct RecordedAudio {
    let url: URL
    let contentType: String
    let filename: String
}

enum AudioCaptureError: LocalizedError {
    case authorizationDenied
    case recorderUnavailable

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Microphone permission was denied."
        case .recorderUnavailable:
            return "The microphone could not start recording."
        }
    }
}

@MainActor
final class AudioCaptureService {
    private let permissionCoordinator: PermissionCoordinator
    private let media = RecordingMediaController()
    private var generation = 0
    private var recorder: AVAudioRecorder?
    private var currentRecordingURL: URL?
    private var recordingStartedAt: Date?
    private var recordingFiles = Set<URL>()

    init(permissionCoordinator: PermissionCoordinator) {
        self.permissionCoordinator = permissionCoordinator
    }

    func start() async throws {
        guard await permissionCoordinator.requestMicrophonePermission() else {
            DebugLogger.write("Microphone permission denied")
            throw AudioCaptureError.authorizationDenied
        }

        cancel()
        let token = generation
        await media.pause()
        guard token == generation else { throw CancellationError() }

        let recordingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-voice-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        recordingFiles.insert(recordingURL)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
        ]

        let recorder: AVAudioRecorder
        do {
            recorder = try AVAudioRecorder(url: recordingURL, settings: settings)
        } catch {
            deleteFile(at: recordingURL)
            media.resume()
            throw error
        }
        recorder.isMeteringEnabled = true

        guard recorder.record() else {
            DebugLogger.write("Recorder failed to start")
            deleteFile(at: recordingURL)
            media.resume()
            throw AudioCaptureError.recorderUnavailable
        }

        self.recorder = recorder
        currentRecordingURL = recordingURL
        recordingStartedAt = Date()
        DebugLogger.write("Recording started: \(recordingURL.lastPathComponent)")
    }

    func stop() -> RecordedAudio? {
        media.resume()
        guard let recorder, let recordingURL = currentRecordingURL else {
            DebugLogger.write("Stop called without active recorder")
            return nil
        }

        let duration = Date().timeIntervalSince(recordingStartedAt ?? Date())
        recorder.stop()
        self.recorder = nil
        currentRecordingURL = nil
        recordingStartedAt = nil
        DebugLogger.write("Recording stopped: duration=\(String(format: "%.2f", duration))s file=\(recordingURL.lastPathComponent)")

        guard duration >= 0.12 else {
            DebugLogger.write("Recording too short, discarded")
            deleteFile(at: recordingURL)
            return nil
        }

        return RecordedAudio(
            url: recordingURL,
            contentType: "audio/wav",
            filename: recordingURL.lastPathComponent
        )
    }

    func cancel() {
        generation += 1
        media.resume()
        recorder?.stop()
        DebugLogger.write("Recording cancelled")

        for url in recordingFiles { deleteFile(at: url) }

        recorder = nil
        currentRecordingURL = nil
        recordingStartedAt = nil
    }

    func waitForPlaybackRestoration() async { await media.waitForRestoration() }

    func deleteRecording(_ recording: RecordedAudio) {
        DebugLogger.write("Deleting recording: \(recording.filename)")
        deleteFile(at: recording.url)
    }

    private func deleteFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
        recordingFiles.remove(url)
    }
}

// MediaRemote is optional: never toggle blindly or start a player whose identity
// macOS does not expose. Unsupported players keep playing rather than being muted.
@MainActor
protocol MediaPlaybackBackend {
    func state() async -> MediaPlaybackState?
    func send(play: Bool) -> Bool
}

struct MediaPlaybackState: Equatable, Sendable {
    let pid: Int32
    let playing: Bool
}

@MainActor
final class RecordingMediaController {
    private let backend: any MediaPlaybackBackend
    private var generation = 0
    private var pausedPID: Int32?
    private var restoration: Task<Void, Never>?

    init(backend: any MediaPlaybackBackend = SystemMediaPlaybackBackend()) {
        self.backend = backend
    }

    func pause() async {
        generation += 1
        let token = generation
        await restoration?.value
        guard token == generation, pausedPID == nil,
              let state = await backend.state(), token == generation,
              state.pid > 0, state.playing else { return }
        if backend.send(play: false) { pausedPID = state.pid }
    }

    func resume() {
        generation += 1
        guard let pid = pausedPID else { return }
        pausedPID = nil
        restoration = Task { @MainActor [backend] in
            // Let the asynchronous pause command settle before reading its state.
            try? await Task.sleep(for: .milliseconds(150))
            guard let state = await backend.state(), state.pid == pid, !state.playing else { return }
            _ = backend.send(play: true)
        }
    }

    func waitForRestoration() async { await restoration?.value }
}

@MainActor
final class SystemMediaPlaybackBackend: MediaPlaybackBackend {
    private typealias ReadPID = @convention(c) (DispatchQueue, @escaping @convention(block) (Int32) -> Void) -> Void
    private typealias ReadPlaying = @convention(c) (DispatchQueue, @escaping @convention(block) (Bool) -> Void) -> Void
    private typealias SendCommand = @convention(c) (Int32, CFDictionary?) -> Bool
    private let framework: CFBundle?

    init() {
        framework = CFBundleCreate(kCFAllocatorDefault, URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework") as CFURL)
    }

    private func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let framework, let pointer = CFBundleGetFunctionPointerForName(framework, name as CFString) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    func state() async -> MediaPlaybackState? {
        guard let pid = symbol("MRMediaRemoteGetNowPlayingApplicationPID", as: ReadPID.self),
              let playing = symbol("MRMediaRemoteGetNowPlayingApplicationIsPlaying", as: ReadPlaying.self) else { return nil }
        return await withCheckedContinuation { continuation in
            let reply = MediaStateReply(continuation)
            pid(.main) { value in
                Task { @MainActor in reply.pid = value; reply.finishIfReady() }
            }
            playing(.main) { value in
                Task { @MainActor in reply.playing = value; reply.finishIfReady() }
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                reply.finish(nil)
            }
        }
    }

    func send(play: Bool) -> Bool {
        symbol("MRMediaRemoteSendCommand", as: SendCommand.self)?(play ? 0 : 1, nil) ?? false
    }
}

@MainActor
private final class MediaStateReply {
    var pid: Int32?
    var playing: Bool?
    private var continuation: CheckedContinuation<MediaPlaybackState?, Never>?
    init(_ continuation: CheckedContinuation<MediaPlaybackState?, Never>) { self.continuation = continuation }
    func finishIfReady() {
        if let pid, let playing { finish(MediaPlaybackState(pid: pid, playing: playing)) }
    }
    func finish(_ value: MediaPlaybackState?) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}
