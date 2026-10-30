import Foundation
import Security

/// Provider tokens live in the login Keychain, never in plain files.
///
/// Items are read and written through Apple's /usr/bin/security tool, so the Keychain
/// trusts that fixed, Apple-signed tool rather than this app. An unsigned app gets a new
/// identity on every build, which would otherwise make macOS ask for your password after
/// each update.
enum Keychain {
    private static let service = "com.local.gpuusage"

    enum Key: String, CaseIterable {
        case autodlToken, runpodKey, vastKey
    }

    static func get(_ key: Key) -> String? {
        let result = security(["find-generic-password", "-s", service, "-a", key.rawValue, "-w"])
        guard result.status == 0, let value = result.output, !value.isEmpty else { return nil }
        return value
    }

    static func set(_ key: Key, _ value: String?) {
        _ = security(["delete-generic-password", "-s", service, "-a", key.rawValue])
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return }
        // Sent as hex on stdin through `security -i`, so the value never appears in the process list.
        let hex = Data(value.utf8).map { String(format: "%02x", $0) }.joined()
        _ = security(["-i"], stdin: "add-generic-password -s \"\(service)\" -a \"\(key.rawValue)\" -X \(hex)\n")
    }

    private static func security(_ args: [String], stdin: String? = nil) -> (status: Int32, output: String?) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        let input = Pipe()
        if stdin != nil { p.standardInput = input }
        do { try p.run() } catch { return (-1, nil) }
        if let stdin {
            input.fileHandleForWriting.write(Data(stdin.utf8))
            try? input.fileHandleForWriting.close()
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (p.terminationStatus, text)
    }
}
