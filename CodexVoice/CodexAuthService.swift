import Foundation

struct CodexCredentials {
    let accessToken: String
    let accountID: String
}

enum CodexAuthError: LocalizedError {
    case authFileMissing
    case credentialsUnavailable
    case refreshFailed(String)

    var errorDescription: String? {
        switch self {
        case .authFileMissing:
            return "Codex auth could not be found. Sign in to Codex first."
        case .credentialsUnavailable:
            return "Codex auth is incomplete. Sign in to Codex again."
        case .refreshFailed(let message):
            return "Codex auth refresh failed: \(message)"
        }
    }
}

actor CodexAuthService {
    private struct AuthFile: Decodable {
        struct Tokens: Decodable {
            let access_token: String
            let account_id: String
        }

        let tokens: Tokens
    }

    private let authFileURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODEX_HOME"] ?? NSString(string: "~/.codex").expandingTildeInPath).appendingPathComponent("auth.json")

    func currentCredentials() throws -> CodexCredentials {
        try readCredentials()
    }

    func refreshCredentials() async throws -> CodexCredentials {
        try await refreshAuthState()
        return try readCredentials()
    }

    private func readCredentials() throws -> CodexCredentials {
        guard FileManager.default.fileExists(atPath: authFileURL.path) else {
            throw CodexAuthError.authFileMissing
        }

        let data = try Data(contentsOf: authFileURL)
        let authFile = try JSONDecoder().decode(AuthFile.self, from: data)

        guard !authFile.tokens.access_token.isEmpty, !authFile.tokens.account_id.isEmpty else {
            throw CodexAuthError.credentialsUnavailable
        }

        return CodexCredentials(
            accessToken: authFile.tokens.access_token,
            accountID: authFile.tokens.account_id
        )
    }

    private func refreshAuthState() async throws {
        let codexBinaryURL = try resolveCodexBinaryURL()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("codex-voice-auth-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("stdout")
        let errorURL = directory.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        FileManager.default.createFile(atPath: errorURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let output = try FileHandle(forWritingTo: outputURL)
        let errors = try FileHandle(forWritingTo: errorURL)
        defer { try? output.close(); try? errors.close() }

        let process = Process()
        let input = Pipe()
        process.executableURL = codexBinaryURL
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
        }

        func send(_ message: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: message)
            data.append(0x0A)
            try input.fileHandleForWriting.write(contentsOf: data)
        }

        // Keep stdin open, and finish initialization before asking for a refresh.
        // Closing stdin early lets current CLI versions exit before replying.
        try send([
            "id": 1, "method": "initialize",
            "params": ["clientInfo": ["name": "codex-voice", "version": "0.2.0"]],
        ])
        try await waitForResponse(id: 1, at: outputURL, process: process)
        try send(["method": "initialized"])
        try send(["id": 2, "method": "account/read", "params": ["refreshToken": true]])
        try await waitForResponse(id: 2, at: outputURL, process: process)
    }

    private func waitForResponse(id: Int, at url: URL, process: Process) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while ContinuousClock.now < deadline {
            let data = try Data(contentsOf: url)
            for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
                guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      (object["id"] as? Int) == id else { continue }
                guard object["result"] != nil, object["error"] == nil else {
                    throw CodexAuthError.refreshFailed("Codex rejected the authentication request. Open Codex and sign in again.")
                }
                return
            }
            guard process.isRunning else {
                throw CodexAuthError.refreshFailed("Codex exited before confirming authentication.")
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw CodexAuthError.refreshFailed("Codex did not respond within 20 seconds. Open Codex and sign in again.")
    }

    private func resolveCodexBinaryURL() throws -> URL {
        let candidatePaths = [
            ProcessInfo.processInfo.environment["CODEX_CLI_PATH"],
            codexBinaryPathFromPATH(),
            NSString(string: "~/.local/bin/codex").expandingTildeInPath,
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
        ].compactMap { $0 }

        if let executablePath = candidatePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: executablePath)
        }

        throw CodexAuthError.refreshFailed(
            """
            Codex CLI could not be found. Install Codex, make `codex` available on your PATH, \
            or set CODEX_CLI_PATH to the executable location.
            """
        )
    }

    private func codexBinaryPathFromPATH() -> String? {
        let process = Process()
        let outputPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["codex"]
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return nil
        }

        let path = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }
}
