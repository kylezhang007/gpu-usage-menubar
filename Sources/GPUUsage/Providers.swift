import Foundation

/// AutoDL: wallet balance through the developer API. GPU stats come over SSH.
enum AutoDLProvider {
    static func account(token: String) async -> Account {
        var account = Account(provider: .autodl)
        do {
            var req = URLRequest(url: URL(string: "https://api.autodl.com/api/v1/dev/wallet/balance")!)
            req.httpMethod = "POST"
            req.setValue(token, forHTTPHeaderField: "Authorization")   // raw token, no "Bearer"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            // The docs list no parameters, but without a JSON body it answers RequestParameterIsWrong.
            req.httpBody = Data("{}".utf8)
            guard let json = try await HTTP.json(req) as? [String: Any] else { throw FetchError.badResponse }
            guard json["code"] as? String == "Success", let data = json["data"] as? [String: Any] else {
                throw FetchError.message((json["code"] as? String) == "AuthorizeFailed"
                                         ? L("Token 无效", "Invalid token")
                                         : (json["msg"] as? String ?? L("返回的数据看不懂", "Unexpected response")))
            }
            // Amounts are in thousandths of a yuan.
            account.balance = doubleValue(data["assets"]).map { Money(amount: $0 / 1000, currency: "CNY") }
            if let v = doubleValue(data["voucher_balance"]), v > 0 {
                account.voucher = Money(amount: v / 1000, currency: "CNY")
            }
        } catch {
            account.error = HTTP.describe(error)
        }
        return account
    }
}

/// RunPod: balance, spend rate and every pod's GPU stats from one GraphQL query, no SSH needed.
enum RunPodProvider {
    static func fetch(key: String) async -> (Account, [Machine]) {
        var account = Account(provider: .runpod)
        let query = """
        query { myself { clientBalance currentSpendPerHr pods { id name desiredStatus costPerHr gpuCount \
        machine { gpuDisplayName } runtime { uptimeInSeconds gpus { gpuUtilPercent memoryUtilPercent } } } } }
        """
        do {
            var c = URLComponents(string: "https://api.runpod.io/graphql")!
            c.queryItems = [URLQueryItem(name: "api_key", value: key)]
            var req = URLRequest(url: c.url!)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])
            guard let json = try await HTTP.json(req) as? [String: Any],
                  let me = (json["data"] as? [String: Any])?["myself"] as? [String: Any] else {
                throw FetchError.http(401)
            }
            account.balance = doubleValue(me["clientBalance"]).map { Money(amount: $0, currency: "USD") }
            account.spendPerHour = doubleValue(me["currentSpendPerHr"]).map { Money(amount: $0, currency: "USD") }

            let machines = (me["pods"] as? [[String: Any]] ?? []).map { pod -> Machine in
                var m = Machine(id: "runpod-" + (pod["id"] as? String ?? UUID().uuidString),
                                name: pod["name"] as? String ?? "pod", provider: .runpod)
                let runtime = pod["runtime"] as? [String: Any]
                let gpus = runtime?["gpus"] as? [[String: Any]] ?? []
                let gpuName = (pod["machine"] as? [String: Any])?["gpuDisplayName"] as? String ?? "GPU"
                m.gpus = gpus.map { GPU(name: gpuName, util: doubleValue($0["gpuUtilPercent"]) ?? 0,
                                        memUsedMiB: 0, memTotalMiB: 0) }
                if !gpus.isEmpty {
                    m.memPercentOverride = gpus.compactMap { doubleValue($0["memoryUtilPercent"]) }.reduce(0, +) / Double(gpus.count)
                }
                m.uptime = doubleValue(runtime?["uptimeInSeconds"])
                m.costPerHour = doubleValue(pod["costPerHr"]).map { Money(amount: $0, currency: "USD") }
                m.state = runtime == nil || (pod["desiredStatus"] as? String) != "RUNNING" ? .stopped : .online
                return m
            }
            return (account, machines)
        } catch {
            account.error = HTTP.describe(error)
            return (account, [])
        }
    }
}

/// Vast.ai: balance plus every rented instance's GPU stats, no SSH needed.
enum VastProvider {
    static func fetch(key: String) async -> (Account, [Machine]) {
        var account = Account(provider: .vast)
        func request(_ path: String) -> URLRequest {
            var req = URLRequest(url: URL(string: "https://console.vast.ai/api/v0/" + path)!)
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            return req
        }
        do {
            guard let user = try await HTTP.json(request("users/current/")) as? [String: Any] else {
                throw FetchError.badResponse
            }
            account.balance = doubleValue(user["credit"] ?? user["balance"]).map { Money(amount: $0, currency: "USD") }

            let list = (try? await HTTP.json(request("instances/")) as? [String: Any])?["instances"] as? [[String: Any]] ?? []
            let machines = list.map { inst -> Machine in
                let idText = (inst["id"] as? NSNumber)?.stringValue ?? "\(inst["id"] ?? "")"
                var m = Machine(id: "vast-" + idText,
                                name: (inst["label"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "#\(idText)",
                                provider: .vast)
                let count = Int(doubleValue(inst["num_gpus"]) ?? 1)
                let ramMiB = doubleValue(inst["gpu_ram"]) ?? 0
                let util = doubleValue(inst["gpu_util"]) ?? 0
                m.gpus = Array(repeating: GPU(name: inst["gpu_name"] as? String ?? "GPU", util: util,
                                              memUsedMiB: 0, memTotalMiB: ramMiB,
                                              temp: doubleValue(inst["gpu_temp"]), power: nil), count: max(count, 1))
                if let v = doubleValue(inst["vmem_usage"]) { m.memPercentOverride = v <= 1 ? v * 100 : v }
                if let start = doubleValue(inst["start_date"]) { m.uptime = Date().timeIntervalSince1970 - start }
                m.costPerHour = doubleValue(inst["dph_total"]).map { Money(amount: $0, currency: "USD") }
                m.state = (inst["actual_status"] as? String) == "running" ? .online : .stopped
                return m
            }
            let running = machines.filter { $0.state == .online }.compactMap(\.costPerHour?.amount)
            if !running.isEmpty { account.spendPerHour = Money(amount: running.reduce(0, +), currency: "USD") }
            return (account, machines)
        } catch {
            account.error = HTTP.describe(error)
            return (account, [])
        }
    }
}

/// AutoDL doesn't report a spend rate, so it's estimated from how fast the balance drops.
/// Samples persist across launches; a top-up (balance going up) starts a fresh history.
enum BurnRate {
    private static let key = "balanceHistory"

    static func record(_ provider: Provider, balance: Double) -> Double? {
        var all = UserDefaults.standard.dictionary(forKey: key) as? [String: [[Double]]] ?? [:]
        var samples = all[provider.rawValue] ?? []
        let now = Date().timeIntervalSince1970
        if let last = samples.last, balance > last[1] + 0.005 { samples = [] }
        samples.append([now, balance])
        samples = samples.filter { now - $0[0] < 3 * 3600 }   // last 3 hours
        all[provider.rawValue] = samples
        UserDefaults.standard.set(all, forKey: key)

        guard let first = samples.first, now - first[0] >= 20 * 60 else { return nil }
        let perHour = (first[1] - balance) / ((now - first[0]) / 3600)
        return perHour > 0.001 ? perHour : 0
    }
}
