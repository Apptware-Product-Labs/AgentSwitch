import Foundation

/// Thin wrapper over `/usr/bin/security`.
///
/// Claude Code on macOS keeps its OAuth token in the login Keychain as a generic
/// password named `Claude Code-credentials` (the name is derived from the *literal*
/// config path, so symlinking `~/.claude` alone does not change which token is used).
/// We go through the same `security` tool Claude Code uses so the item's access
/// control list stays compatible and neither side gets permission prompts.
enum KeychainTool {
    static let claudeLiveService = "Claude Code-credentials"

    static func profileService(_ tool: Tool, _ profileID: String) -> String {
        "AgentSwitch-\(tool.rawValue)-\(profileID)"
    }

    /// Returns the secret, or nil if the item doesn't exist.
    static func read(service: String) -> String? {
        let r = run(["find-generic-password", "-s", service, "-w"])
        guard r.status == 0 else { return nil }
        var s = r.stdout
        if s.hasSuffix("\n") { s.removeLast() }
        return s
    }

    static func exists(service: String) -> Bool {
        run(["find-generic-password", "-s", service]).status == 0
    }

    static func write(service: String, value: String) throws {
        let r = run(["add-generic-password", "-U", "-a", NSUserName(), "-s", service, "-w", value])
        guard r.status == 0 else { throw KeychainError.failed(service, r.stderr) }
    }

    static func delete(service: String) {
        _ = run(["delete-generic-password", "-s", service])
    }

    enum KeychainError: LocalizedError {
        case failed(String, String)
        var errorDescription: String? {
            if case .failed(let svc, let msg) = self { return "Keychain update failed for \(svc): \(msg)" }
            return nil
        }
    }

    private static func run(_ args: [String]) -> (status: Int32, stdout: String, stderr: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch { return (-1, "", error.localizedDescription) }
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus,
                String(decoding: o, as: UTF8.self),
                String(decoding: e, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
