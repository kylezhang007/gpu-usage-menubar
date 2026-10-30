import Foundation

enum Provider: String, Codable, CaseIterable, Identifiable {
    case autodl, runpod, vast, lambda, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .autodl: return "AutoDL"
        case .runpod: return "RunPod"
        case .vast: return "Vast.ai"
        case .lambda: return "Lambda"
        case .other: return L("其他", "Other")
        }
    }

    var theme: SectionTheme {
        switch self {
        case .autodl: return .autodl
        case .runpod: return .runpod
        case .vast: return .vast
        case .lambda, .other: return .other
        }
    }
}

/// A server the user added by its SSH command (key-based login, no password stored).
struct Server: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var provider: Provider
    var ssh: String
}

struct GPU: Equatable {
    var name: String
    var util: Double          // %
    var memUsedMiB: Double
    var memTotalMiB: Double
    var temp: Double?
    var power: Double?        // W
}

struct Disk: Equatable {
    var mount: String
    var usedKB: Double
    var totalKB: Double
    var percent: Double { totalKB > 0 ? usedKB / totalKB * 100 : 0 }
}

/// One machine on the panel: an SSH server, or a RunPod / Vast.ai instance found through their API.
struct Machine: Identifiable, Equatable {
    enum State: Equatable {
        case loading
        case offline(String)
        case stopped              // reported as stopped by the provider's API
        case online
    }

    var id: String
    var name: String
    var provider: Provider
    var state: State = .loading
    var gpus: [GPU] = []
    var memPercentOverride: Double?   // providers that only report VRAM as a percent
    var uptime: TimeInterval?
    var disks: [Disk] = []
    var costPerHour: Money?

    var util: Double { gpus.isEmpty ? 0 : gpus.map(\.util).reduce(0, +) / Double(gpus.count) }
    var memUsedGB: Double { gpus.map(\.memUsedMiB).reduce(0, +) / 1024 }
    var memTotalGB: Double { gpus.map(\.memTotalMiB).reduce(0, +) / 1024 }
    var memPercent: Double { memPercentOverride ?? (memTotalGB > 0 ? memUsedGB / memTotalGB * 100 : 0) }
    var maxTemp: Double? { gpus.compactMap(\.temp).max() }
    var totalPower: Double? { let p = gpus.compactMap(\.power); return p.isEmpty ? nil : p.reduce(0, +) }
    var fullestDisk: Disk? { disks.max { $0.percent < $1.percent } }

    /// "RTX 4090 × 2"
    var gpuSummary: String? {
        guard let first = gpus.first?.name else { return nil }
        let short = first
            .replacingOccurrences(of: "NVIDIA ", with: "")
            .replacingOccurrences(of: "GeForce ", with: "")
            .replacingOccurrences(of: " PCIe", with: "")
            .replacingOccurrences(of: " SXM4", with: "")
            .replacingOccurrences(of: " SXM5", with: "")
        return gpus.count > 1 ? "\(short) × \(gpus.count)" : short
    }
}

struct Money: Equatable {
    var amount: Double
    var currency: String         // "CNY" or "USD"

    var formatted: String {
        (currency == "CNY" ? "¥" : "$") + String(format: "%.2f", amount)
    }
}

/// One provider account's balance and how fast it's going down.
struct Account: Identifiable, Equatable {
    var id: Provider { provider }
    var provider: Provider
    var balance: Money?
    var voucher: Money?
    var spendPerHour: Money?
    var todaySpend: Money?
    var weekSpend: Money?
    var totalSpend: Money?
    var daily: [Double?] = []        // last 7 days' spend, oldest first
    var error: String?

    var hoursLeft: Double? {
        guard let b = balance?.amount, let s = spendPerHour?.amount, s > 0.001 else { return nil }
        return b / s
    }
}

enum FetchError: LocalizedError {
    case http(Int)
    case badResponse
    case message(String)

    var errorDescription: String? {
        switch self {
        case .http(401), .http(403): return L("Key 无效或没有权限", "Invalid key or no access")
        case .http(429): return L("请求太频繁，稍后再试", "Rate limited, retrying later")
        case .http(let code): return L("请求失败（\(code)）", "Request failed (\(code))")
        case .badResponse: return L("返回的数据看不懂", "Unexpected response")
        case .message(let m): return m
        }
    }
}

enum HTTP {
    static func json(_ request: URLRequest) async throws -> Any {
        var request = request
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FetchError.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw FetchError.http(http.statusCode) }
        return try JSONSerialization.jsonObject(with: data)
    }

    static func describe(_ error: Error) -> String {
        if let e = error as? FetchError { return e.errorDescription ?? L("出错了", "Something went wrong") }
        if (error as NSError).domain == NSURLErrorDomain { return L("网络连接失败", "No connection") }
        return L("出错了", "Something went wrong")
    }
}

func doubleValue(_ any: Any?) -> Double? {
    if let d = any as? Double { return d }
    if let n = any as? NSNumber { return n.doubleValue }
    if let s = any as? String { return Double(s.trimmingCharacters(in: .whitespaces)) }
    return nil
}

/// "3h12m", "1d04h", "42m"
func formatDuration(_ seconds: TimeInterval) -> String {
    let mins = max(0, Int(seconds / 60))
    let d = mins / 1440, h = mins % 1440 / 60, m = mins % 60
    if d > 0 { return String(format: "%dd%02dh", d, h) }
    if h > 0 { return String(format: "%dh%02dm", h, m) }
    return "\(m)m"
}
