import Foundation

/// Reads GPU, uptime and disk stats from a server over SSH with one short command.
/// Uses the system `ssh` and your existing key login, so no password is ever stored.
enum SSHProbe {
    /// Everything comes back in one round trip, split into sections by @@ markers.
    /// Uptime is PID 1's age: on AutoDL and other containers that's when the instance started.
    static let remoteScript = [
        "echo @@GPU",
        "nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw --format=csv,noheader,nounits 2>/dev/null",
        "echo @@UP",
        "ps -o etimes= -p 1 2>/dev/null || cut -d. -f1 /proc/uptime",
        "echo @@DISK",
        "df -kP / /root/autodl-tmp /workspace 2>/dev/null",
        "echo @@END",
    ].joined(separator: "; ")

    static func probe(_ server: Server) async -> Machine {
        var machine = Machine(id: server.id.uuidString, name: server.name, provider: server.provider)
        let result = await run(server.ssh, remote: remoteScript)
        guard result.status == 0, result.output.contains("@@END") else {
            machine.state = .offline(describe(result))
            return machine
        }
        parse(result.output, into: &machine)
        machine.state = machine.gpus.isEmpty
            ? .offline(L("没有找到 GPU（无卡模式？）", "No GPU found (CPU-only mode?)"))
            : .online
        return machine
    }

    static func parse(_ output: String, into machine: inout Machine) {
        var section = ""
        var seenMounts = Set<String>()
        for raw in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("@@") { section = line; continue }
            switch section {
            case "@@GPU":
                let f = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                guard f.count >= 4, let util = Double(f[1]) else { continue }
                machine.gpus.append(GPU(name: f[0], util: util,
                                        memUsedMiB: Double(f[2]) ?? 0, memTotalMiB: Double(f[3]) ?? 0,
                                        temp: f.count > 4 ? Double(f[4]) : nil,
                                        power: f.count > 5 ? Double(f[5]) : nil))
            case "@@UP":
                if machine.uptime == nil, let s = Double(line) { machine.uptime = s }
            case "@@DISK":
                let f = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard f.count >= 6, let total = Double(f[1]), let used = Double(f[2]), total > 0 else { continue }
                let mount = String(f[5])
                // The three paths often share one filesystem; count each once.
                guard seenMounts.insert(String(f[0]) + total.description).inserted else { continue }
                machine.disks.append(Disk(mount: mount, usedKB: used, totalKB: total))
            default:
                break
            }
        }
    }

    private static func describe(_ r: (status: Int32, output: String, error: String)) -> String {
        let e = r.error.lowercased()
        if r.status == -2 { return L("连接超时，可能已关机", "Timed out, probably powered off") }
        if e.contains("permission denied") { return L("SSH 免密登录没配好", "SSH key login isn't set up") }
        if e.contains("connection refused") || e.contains("timed out") || e.contains("no route")
            || e.contains("closed by remote") || e.contains("connection reset") {
            return L("已关机或连不上", "Powered off or unreachable")
        }
        if e.contains("could not resolve") { return L("网络连接失败", "No connection") }
        return L("已关机或连不上", "Powered off or unreachable")
    }

    // MARK: - ssh

    /// Splits "ssh -p 12345 root@host" into arguments, honoring simple quotes.
    static func arguments(of command: String) -> [String] {
        var args: [String] = []
        var current = ""
        var quote: Character?
        for ch in command {
            if let q = quote {
                if ch == q { quote = nil } else { current.append(ch) }
            } else if ch == "\"" || ch == "'" {
                quote = ch
            } else if ch == " " || ch == "\t" || ch == "\n" {
                if !current.isEmpty { args.append(current); current = "" }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { args.append(current) }
        if args.first == "ssh" || args.first?.hasSuffix("/ssh") == true { args.removeFirst() }
        return args
    }

    /// status -2 means our own timeout fired.
    static func run(_ command: String, remote: String, timeout: TimeInterval = 20) async -> (status: Int32, output: String, error: String) {
        // No ControlMaster/ControlPersist: the backgrounded master would keep our pipes open.
        let options = [
            "-o", "BatchMode=yes",                    // never prompt; key login only
            "-o", "ConnectTimeout=8",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=2",
        ]
        let args = options + arguments(of: command) + [remote]

        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                p.arguments = args
                let out = Pipe(), err = Pipe()
                p.standardOutput = out
                p.standardError = err
                p.standardInput = FileHandle.nullDevice
                do { try p.run() } catch {
                    continuation.resume(returning: (-1, "", error.localizedDescription)); return
                }
                var timedOut = false
                let timer = DispatchWorkItem { timedOut = true; p.terminate() }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                let errData = err.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                timer.cancel()
                continuation.resume(returning: (timedOut ? -2 : p.terminationStatus,
                                                String(data: outData, encoding: .utf8) ?? "",
                                                String(data: errData, encoding: .utf8) ?? ""))
            }
        }
    }
}
