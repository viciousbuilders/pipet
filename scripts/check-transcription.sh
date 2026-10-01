#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"
mkdir -p .build
say -o .build/transcription-check.aiff "This is a test of voice dictation on my MacBook."
afconvert -f WAVE -d LEI16@44100 -c 1 .build/transcription-check.aiff .build/transcription-check.wav
cat > .build/TranscriptionCheck.swift <<'SWIFT'
import Foundation

@main
struct TranscriptionCheck {
    static func main() async throws {
        let auth = CodexAuthService()
        if CommandLine.arguments.contains("--refresh") {
            _ = try await auth.refreshCredentials()
            print("Codex authentication refresh succeeded.")
        }
        let service = CodexTranscriptionService(authService: auth)
        let recording = RecordedAudio(url: URL(fileURLWithPath: ".build/transcription-check.wav"), contentType: "audio/wav", filename: "test.wav")
        let transcript = try await service.transcribe(recording)
        print("Transcript: \(transcript)")
        guard transcript.lowercased().contains("test of voice dictation") else {
            throw NSError(domain: "TranscriptionCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "The transcript did not match the test sentence."])
        }
        print("PASS: the app's transcription service works with your Codex sign-in.")
    }
}
SWIFT
swiftc -swift-version 6 -parse-as-library CodexVoice/AudioCaptureService.swift CodexVoice/PermissionCoordinator.swift CodexVoice/DebugLogger.swift CodexVoice/CodexAuthService.swift CodexVoice/CodexTranscriptionService.swift .build/TranscriptionCheck.swift -o .build/TranscriptionCheck
.build/TranscriptionCheck "$@"
