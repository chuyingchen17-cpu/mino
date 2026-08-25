import AppKit

/// Owns GitHub Device Flow code writes so automatic and manual copying cannot
/// drift into different behavior.
package enum GitHubDeviceCodeClipboard {
    package static func normalizedCode(_ rawCode: String) -> String? {
        let compact = rawCode
            .uppercased()
            .unicodeScalars
            .filter { scalar in
                switch scalar.value {
                case 48...57, 65...90:
                    true
                default:
                    false
                }
            }
            .map(String.init)
            .joined()
        guard compact.count == 8 else { return nil }
        let split = compact.index(compact.startIndex, offsetBy: 4)
        return "\(compact[..<split])-\(compact[split...])"
    }

    @MainActor
    @discardableResult
    package static func copy(
        _ rawCode: String,
        to pasteboard: NSPasteboard = .general
    ) -> Bool {
        guard let code = normalizedCode(rawCode) else { return false }

        // GitHub CLI uses `/usr/bin/pbcopy` on macOS. Match that path for the
        // system clipboard so GitHub's segmented activation form receives one
        // plain-text payload rather than an AppKit object representation.
        if pasteboard.name == .general,
           copyWithSystemPasteboard(code),
           pasteboard.string(forType: .string) == code {
            return true
        }

        pasteboard.clearContents()
        guard pasteboard.setString(code, forType: .string) else { return false }
        return pasteboard.string(forType: .string) == code
    }

    private static func copyWithSystemPasteboard(_ code: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")
        let input = Pipe()
        process.standardInput = input

        do {
            try process.run()
            try input.fileHandleForWriting.write(contentsOf: Data(code.utf8))
            try input.fileHandleForWriting.close()
            process.waitUntilExit()
            return process.terminationReason == .exit && process.terminationStatus == 0
        } catch {
            try? input.fileHandleForWriting.close()
            return false
        }
    }
}
