import Foundation
import ServiceManagement
import UserNotifications

@MainActor
final class AppState: ObservableObject {
    @Published var servers: [Server] {
        didSet { saveServers(); Task { await refresh() } }
    }
    @Published private(set) var machines: [Machine] = []
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var history: [String: [Double]] = [:]   // GPU util samples, oldest first
    @Published private(set) var idleSince: [String: Date] = [:]
    @Published var lastUpdated: Date?
    @Published var isRefreshing = false
    @Published var showingSettings = false

    @Published var refreshSeconds: Int {
        didSet { UserDefaults.standard.set(refreshSeconds, forKey: "refreshSeconds"); scheduleTimer() }
    }
    @Published var idleAlertMinutes: Int {
        didSet { UserDefaults.standard.set(idleAlertMinutes, forKey: "idleAlertMinutes") }
    }
    @Published var clearGlass: Bool {
        didSet { UserDefaults.standard.set(clearGlass, forKey: "clearGlass") }
    }
    @Published var language: Language {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "language") }
    }

    /// GPU use below this counts as idle.
    static let idleThreshold = 5.0
    static let historyLength = 60

    private var timer: Timer?
    private var alerted = Set<String>()   // one notification per idle stretch / low-balance episode

    init() {
        let defaults = UserDefaults.standard
        servers = (defaults.data(forKey: "servers")).flatMap { try? JSONDecoder().decode([Server].self, from: $0) } ?? []
        let saved = defaults.integer(forKey: "refreshSeconds")
        refreshSeconds = saved > 0 ? saved : 60
        idleAlertMinutes = defaults.object(forKey: "idleAlertMinutes") as? Int ?? 30
        clearGlass = defaults.object(forKey: "clearGlass") as? Bool ?? true
        language = Language.current
        machines = servers.map { Machine(id: $0.id.uuidString, name: $0.name, provider: $0.provider) }
        scheduleTimer()
        if Self.canNotify {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        Task { await refresh() }
    }

    /// `GPUUsage --demo` shows made-up machines, for screenshots without real servers.
    let demo = CommandLine.arguments.contains("--demo")

    private func loadDemo() {
        func gpus(_ name: String, _ n: Int, util: Double, used: Double, total: Double, temp: Double, power: Double) -> [GPU] {
            Array(repeating: GPU(name: name, util: util, memUsedMiB: used * 1024, memTotalMiB: total * 1024, temp: temp, power: power), count: n)
        }
        var a = Machine(id: "demo-a", name: L("炼丹", "train"), provider: .autodl, state: .online)
        a.gpus = gpus("NVIDIA GeForce RTX 4090", 1, util: 87, used: 18, total: 24, temp: 71, power: 310)
        a.uptime = 3 * 3600 + 12 * 60
        a.disks = [Disk(mount: "/root/autodl-tmp", usedKB: 31 * 1_048_576, totalKB: 50 * 1_048_576)]
        var b = Machine(id: "demo-b", name: L("推理", "serve"), provider: .autodl, state: .online)
        b.gpus = gpus("NVIDIA A800 80GB PCIe", 2, util: 2, used: 3, total: 80, temp: 38, power: 62)
        b.uptime = 5 * 3600 + 40 * 60
        b.disks = [Disk(mount: "/", usedKB: 12 * 1_048_576, totalKB: 30 * 1_048_576)]
        var c = Machine(id: "demo-c", name: "h100", provider: .runpod, state: .online)
        c.gpus = gpus("H100 80GB HBM3", 2, util: 94, used: 0, total: 0, temp: 0, power: 0).map { var g = $0; g.temp = nil; g.power = nil; return g }
        c.memPercentOverride = 91
        c.uptime = 28 * 3600 + 15 * 60
        c.costPerHour = Money(amount: 5.38, currency: "USD")
        machines = [a, b, c]
        let steps = (0..<60).map(Double.init)
        let busy: [Double] = steps.map { x in 80 + 8 * sin(x / 4) }
        let stalled: [Double] = steps.map { x in x < 18 ? 72 : 1.5 }
        let full: [Double] = steps.map { x in 90 + 4 * cos(x / 5) }
        history = ["demo-a": busy, "demo-b": stalled, "demo-c": full]
        idleSince = ["demo-b": Date().addingTimeInterval(-42 * 60)]
        accounts = [
            Account(provider: .autodl, balance: Money(amount: 128.40, currency: "CNY"),
                    voucher: Money(amount: 20, currency: "CNY"), spendPerHour: Money(amount: 3.98, currency: "CNY"),
                    todaySpend: Money(amount: 23.65, currency: "CNY"), totalSpend: Money(amount: 871.60, currency: "CNY")),
            Account(provider: .runpod, balance: Money(amount: 42.10, currency: "USD"), spendPerHour: Money(amount: 5.38, currency: "USD")),
            Account(provider: .vast, balance: Money(amount: 15.00, currency: "USD"), spendPerHour: Money(amount: 0, currency: "USD")),
        ]
        lastUpdated = Date()
    }

    func refresh() async {
        if demo { loadDemo(); return }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let servers = self.servers
        let autodl = Keychain.get(.autodlToken)
        let runpod = Keychain.get(.runpodKey)
        let vast = Keychain.get(.vastKey)

        async let sshMachines: [Machine] = withTaskGroup(of: (Int, Machine).self) { group in
            for (i, s) in servers.enumerated() { group.addTask { (i, await SSHProbe.probe(s)) } }
            var out: [(Int, Machine)] = []
            for await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }
        async let autodlAccount: Account? = autodl != nil ? AutoDLProvider.account(token: autodl!) : nil
        async let runpodResult: (Account, [Machine])? = runpod != nil ? RunPodProvider.fetch(key: runpod!) : nil
        async let vastResult: (Account, [Machine])? = vast != nil ? VastProvider.fetch(key: vast!) : nil

        var all = await sshMachines
        var accounts: [Account] = []
        if let a = await autodlAccount { accounts.append(a) }
        if let (a, m) = await runpodResult { accounts.append(a); all += m }
        if let (a, m) = await vastResult { accounts.append(a); all += m }

        track(all)
        machines = all
        self.accounts = accounts
        lastUpdated = Date()
        notifyIfNeeded()
    }

    /// Keeps a short GPU-use history per machine and when each one went idle.
    private func track(_ machines: [Machine]) {
        let now = Date()
        for m in machines {
            guard m.state == .online else {
                idleSince[m.id] = nil
                continue
            }
            var h = history[m.id] ?? []
            h.append(m.util)
            history[m.id] = Array(h.suffix(Self.historyLength))
            if m.util < Self.idleThreshold {
                if idleSince[m.id] == nil { idleSince[m.id] = now }
            } else {
                idleSince[m.id] = nil
                alerted.remove("idle-" + m.id)
            }
        }
    }

    func idleMinutes(_ m: Machine) -> Int? {
        idleSince[m.id].map { Int(Date().timeIntervalSince($0) / 60) }
    }

    var runningCount: Int { machines.filter { $0.state == .online }.count }
    var idleCount: Int {
        machines.filter { m in m.state == .online && (idleMinutes(m) ?? 0) >= max(idleAlertMinutes, 10) }.count
    }

    // MARK: - Notifications

    private func notifyIfNeeded() {
        if idleAlertMinutes > 0 {
            for m in machines where m.state == .online {
                guard let mins = idleMinutes(m), mins >= idleAlertMinutes, alerted.insert("idle-" + m.id).inserted else { continue }
                post(L("\(m.name) 空闲 \(mins) 分钟了", "\(m.name) has been idle for \(mins) min"),
                     L("GPU 几乎没在用，记得关机省钱。", "The GPU is barely in use. Shut it down to stop paying."))
            }
        }
        for a in accounts {
            let key = "low-" + a.provider.rawValue
            if let h = a.hoursLeft, h < 3, let b = a.balance {
                guard alerted.insert(key).inserted else { continue }
                post(L("\(a.provider.title) 余额只够约 \(max(1, Int(h))) 小时", "\(a.provider.title) balance lasts about \(max(1, Int(h))) h"),
                     L("当前余额 \(b.formatted)，记得充值，不然机器会被关机。", "Balance is \(b.formatted). Top up before the machines get shut down."))
            } else {
                alerted.remove(key)
            }
        }
    }

    /// Notifications need a real app bundle; a bare debug binary would crash.
    private static var canNotify: Bool { Bundle.main.bundleIdentifier != nil }

    private func post(_ title: String, _ body: String) {
        guard Self.canNotify else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // MARK: - Settings

    private func saveServers() {
        UserDefaults.standard.set(try? JSONEncoder().encode(servers), forKey: "servers")
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(refreshSeconds), repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            if newValue { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
        }
    }
}
