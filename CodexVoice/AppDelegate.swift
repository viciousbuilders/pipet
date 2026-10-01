import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appController: AppController?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        appController?.openWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) { appController?.stop() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        if arguments.contains("--diagnostics") {
            print("Pipet \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "unknown")")
            print("Bundle: \(Bundle.main.bundleIdentifier ?? "unknown")")
            print("Icon present: \(Bundle.main.url(forResource: "Pipet", withExtension: "icns") != nil)")
            print("Logo present: \(Bundle.main.url(forResource: "PipetLogo", withExtension: "png") != nil)")
            exit(0)
        }
        if let index = arguments.firstIndex(of: "--check-transcription"), arguments.count > index + 1 {
            let url = URL(fileURLWithPath: arguments[index + 1])
            Task {
                do {
                    let service = CodexTranscriptionService(authService: CodexAuthService())
                    let transcript = try await service.transcribe(RecordedAudio(url: url, contentType: "audio/wav", filename: "test.wav"))
                    print("Transcript: \(transcript)")
                    exit(transcript.isEmpty ? 1 : 0)
                } catch { print("Transcription failed: \(error.localizedDescription)"); exit(1) }
            }
            return
        }
        if let index = arguments.firstIndex(of: "--restart-from"), arguments.count > index + 1,
           let pid = Int32(arguments[index + 1]), pid != ProcessInfo.processInfo.processIdentifier {
            Task {
                // Let the previous instance release Control-M before registering it.
                for _ in 0..<100 {
                    guard let previous = NSRunningApplication(processIdentifier: pid), !previous.isTerminated else { break }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                startController(showWindow: true)
            }
        } else {
            startController(showWindow: false)
        }
    }

    private func startController(showWindow: Bool) {
        appController = AppController()
        appController?.start()
        if showWindow { appController?.openWindow() }
    }
}
