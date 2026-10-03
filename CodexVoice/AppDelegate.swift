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
        if arguments.contains("--check-web-insertion") {
            Task { @MainActor in
                let service = TextInsertionService()
                let captured = await service.captureTarget()
                guard let target = captured, target.snapshot.value?.trimmingCharacters(in: .whitespacesAndNewlines) == "Pipet web check" else {
                    print("Web fixture focus: frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none"), captured=\(captured?.bundleID ?? "none"), valueLength=\(captured?.snapshot.value?.count ?? -1)")
                    print("Open the web-check fixture and focus its marked editor first."); exit(1)
                }
                switch await service.insert(" passed", into: target) {
                case .confirmed: print("PASS: external web insertion confirmed"); exit(0)
                case .unverified: print("Paste sent; verify the fixture's input-event count."); exit(0)
                case .failed(let message): print("Web insertion failed: \(message)"); exit(1)
                }
            }
            return
        }
        if arguments.contains("--check-insertion") {
            Task { @MainActor in
                do { try await checkInsertion(); print("PASS: live insertion checks"); exit(0) }
                catch { print("Insertion check failed: \(error.localizedDescription)"); exit(1) }
            }
            return
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


extension AppDelegate {
    /// Opt-in test surface; never touches another app's editor or microphone.
    private func checkInsertion() async throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: "PipetInsertionCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        try require(AXIsProcessTrusted(), "Enable Accessibility for this signed Pipet before running the live check.")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 400), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Pipet insertion check"
        window.isReleasedWhenClosed = false
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 620, height: 180))
        let otherEditor = NSTextView(frame: NSRect(x: 0, y: 200, width: 620, height: 180))
        window.contentView?.addSubview(editor)
        window.contentView?.addSubview(otherEditor)
        window.initialFirstResponder = editor
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(editor)
        editor.string = "Hi 🐱 there"
        editor.setSelectedRange(NSRange(location: 3, length: 2))
        try await Task.sleep(for: .seconds(1))
        let service = TextInsertionService()
        let preferences = InsertionPreferences()
        let bundleID = Bundle.main.bundleIdentifier ?? "au.vietbrosinaus.pipet"
        let previousMethod = preferences.overrides[bundleID].flatMap(InsertionMethod.init(rawValue:))
        preferences.set(.paste, for: bundleID)
        defer { preferences.set(previousMethod, for: bundleID) }
        guard let target = await service.captureTarget(), target.pid == ProcessInfo.processInfo.processIdentifier else { try require(false, "Could not capture test editor"); return }
        let pasteboard = NSPasteboard.general
        let initial = pasteboard.pasteboardItems?.map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { values, type in
                values[type] = item.data(forType: type)
            }
        } ?? []
        defer {
            window.close()
            // The test owns clipboard markers only; don't overwrite a real user copy.
            if ["Pipet clipboard check", "Pipet newer copy"].contains(pasteboard.string(forType: .string) ?? "") {
                pasteboard.clearContents()
                let items = initial.map { values in
                    let item = NSPasteboardItem()
                    for (type, data) in values { item.setData(data, forType: type) }
                    return item
                }
                if !items.isEmpty { pasteboard.writeObjects(items) }
            }
        }
        pasteboard.clearContents()
        pasteboard.setString("Pipet clipboard check", forType: .string)
        let result = await service.insert("世界", into: target)
        if case .failed(let message) = result { try require(false, "Native paste blocked: \(message)") }
        try require(editor.string == "Hi 世界 there", "Native paste did not replace the UTF-16 selection")
        if case .confirmed = result {} else { try require(false, "Native insertion was not confirmed") }
        try require(pasteboard.string(forType: .string) == "Pipet clipboard check", "Clipboard was not restored")
        print("PASS: native selected-text paste, verification, clipboard restoration")

        window.makeFirstResponder(editor)
        try await Task.sleep(for: .milliseconds(300))
        guard let focusTarget = await service.captureTarget() else { try require(false, "Could not capture focus target"); return }
        window.makeFirstResponder(otherEditor)
        try await Task.sleep(for: .milliseconds(300))
        let changedResult = await service.insert("must not land", into: focusTarget)
        if case .failed = changedResult {} else { try require(false, "Changed focus was not blocked") }
        try require(otherEditor.string.isEmpty, "Wrong field received text")
        window.makeFirstResponder(editor)
        try await Task.sleep(for: .milliseconds(300))
        guard let selectionTarget = await service.captureTarget() else { try require(false, "Could not capture selection target"); return }
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        try await Task.sleep(for: .milliseconds(300))
        let selectionResult = await service.insert("must not land", into: selectionTarget)
        if case .failed = selectionResult {} else { try require(false, "Changed selection was not blocked") }
        print("PASS: changed field and selection are blocked")

        guard let copyTarget = await service.captureTarget() else { try require(false, "Could not capture clipboard target"); return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            pasteboard.clearContents()
            pasteboard.setString("Pipet newer copy", forType: .string)
        }
        _ = await service.insert("hello ", into: copyTarget)
        try require(pasteboard.string(forType: .string) == "Pipet newer copy", "New clipboard content was overwritten")
        print("PASS: concurrent copy is preserved")
        preferences.set(.accessibility, for: bundleID)
        guard let directTarget = await service.captureTarget() else { try require(false, "Could not capture direct target"); return }
        let directResult = await service.insert("direct ", into: directTarget)
        if case .confirmed = directResult {} else { try require(false, "Direct insertion override was not confirmed") }
        print("PASS: direct insertion override")

    }
}
