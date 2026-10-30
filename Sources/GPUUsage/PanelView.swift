import SwiftUI

struct PanelView: View {
    @EnvironmentObject var state: AppState

    /// Transparent margin around the glass. Glass casts a soft glow past its edges; if the
    /// window is tight, that glow is cut off in a straight line and reads as a backing plate.
    static let margin: CGFloat = 32

    // Like Control Center: no panel behind the content, every block is its own piece of glass.
    var body: some View {
        VStack(spacing: 10) {
            if state.showingSettings {
                SettingsView().frame(width: 420).fixedSize(horizontal: false, vertical: true)
            } else {
                header
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 10) {
                        if state.machines.isEmpty {
                            EmptyTile()
                        }
                        ForEach(state.machines) { MachineTile(machine: $0) }
                    }
                    .frame(width: 370)
                    if !state.accounts.isEmpty {
                        AccountsColumn().frame(width: 230)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                footer
            }
        }
        .padding(Self.margin)
    }

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "cpu").foregroundStyle(SectionTheme.autodl.shade(1).gradient)
                Text(summary)
            }
            .font(.system(size: 13, weight: .medium))
            Spacer()
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Text(updatedText).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassSurface(Capsule(), tint: nil, clear: state.clearGlass)
    }

    private var summary: String {
        let running = state.runningCount, idle = state.idleCount
        if state.machines.isEmpty { return L("还没有添加服务器", "No servers yet") }
        if running == 0 { return L("没有在跑的机器", "Nothing running") }
        if idle > 0 {
            return L("\(running) 台开机，\(idle) 台空闲中", "\(running) running, \(idle) idle")
        }
        return L("\(running) 台在跑，GPU 都在干活", "\(running) running, all GPUs busy")
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button { state.showingSettings = true } label: { chip(Text(L("设置", "Settings"))) }
            Spacer()
            Button {
                Task { await state.refresh() }
            } label: {
                chip(Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(state.isRefreshing ? 360 : 0))
                    .animation(state.isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default,
                               value: state.isRefreshing))
            }
            .help(L("立即刷新", "Refresh now"))
            Button { NSApp.terminate(nil) } label: { chip(Text(L("退出", "Quit"))) }
        }
        .buttonStyle(.plain)
    }

    private func chip(_ content: some View) -> some View {
        content
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .contentShape(Capsule())
            .glassSurface(Capsule(), tint: nil, clear: state.clearGlass)
    }

    private var updatedText: String {
        guard let d = state.lastUpdated else { return L("正在读取…", "Loading…") }
        if Date().timeIntervalSince(d) < 60 { return L("刚刚更新", "Just updated") }
        let f = RelativeDateTimeFormatter()
        f.locale = Language.locale
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }
}

// MARK: - Tiles

struct Tile<Content: View>: View {
    @EnvironmentObject var state: AppState
    var theme: SectionTheme
    var dimmed = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .glassSurface(RoundedRectangle(cornerRadius: 28, style: .continuous),
                          tint: dimmed ? nil : theme.glassTint, clear: state.clearGlass)
    }
}

struct TileHeader: View {
    var title: String
    var detail: String?
    var theme: SectionTheme

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 11)
                .padding(.vertical, 4)
                .background(theme.shade(0).gradient, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.shade(0).gradient)
                    .lineLimit(1)
            }
        }
    }
}

struct EmptyTile: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        Tile(theme: .autodl) {
            TileHeader(title: L("添加服务器", "Add a server"), detail: nil, theme: .autodl)
            Text(L("在设置里粘贴 AutoDL 控制台给的 SSH 登录命令，比如 ssh -p 12345 root@connect.westb.seetacloud.com。RunPod 和 Vast.ai 填好 API Key 就会自动出现。",
                   "Paste the SSH command from your provider's console in Settings, like ssh -p 12345 root@host. RunPod and Vast.ai machines show up once you add their API key."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct MachineTile: View {
    @EnvironmentObject var state: AppState
    var machine: Machine

    private var theme: SectionTheme { machine.provider.theme }
    private var idle: Int? {
        guard let m = state.idleMinutes(machine), m >= 10 else { return nil }
        return m
    }

    var body: some View {
        Tile(theme: theme, dimmed: machine.state != .online) {
            TileHeader(title: "\(machine.provider.title) · \(machine.name)", detail: machine.gpuSummary, theme: theme)
            switch machine.state {
            case .online:
                HStack(spacing: 16) {
                    Rings(values: [machine.util, machine.memPercent], theme: theme, warn: idle != nil)
                    VStack(spacing: 7) {
                        Row(label: L("GPU 利用率", "GPU"), value: machine.util, shade: idle != nil ? SectionTheme.warn : theme.shade(0),
                            detail: gpuDetail)
                        Row(label: L("显存", "VRAM"), value: machine.memPercent, shade: theme.shade(1), detail: memDetail)
                        if let disk = machine.fullestDisk {
                            Row(label: disk.mount == "/" ? L("系统盘", "System disk") : L("数据盘", "Data disk"),
                                value: disk.percent, shade: disk.percent >= 90 ? SectionTheme.warn : theme.shade(1),
                                detail: String(format: "%.0f/%.0fG", disk.usedKB / 1_048_576, disk.totalKB / 1_048_576),
                                small: true)
                        }
                    }
                }
                Sparkline(values: state.history[machine.id] ?? [], shade: idle != nil ? SectionTheme.warn : theme.shade(0))
                footerLine
            case .loading:
                Status(text: L("正在连接…", "Connecting…"))
            case .stopped:
                Status(text: L("已停止", "Stopped"))
            case .offline(let reason):
                Status(text: reason)
            }
        }
    }

    private var gpuDetail: String {
        var parts: [String] = []
        if let t = machine.maxTemp { parts.append("\(Int(t))°C") }
        if let p = machine.totalPower { parts.append("\(Int(p))W") }
        return parts.joined(separator: " ")
    }

    private var memDetail: String {
        machine.memTotalGB > 0 ? String(format: "%.1f/%.0fG", machine.memUsedGB, machine.memTotalGB) : ""
    }

    /// Uptime, how long the GPU has sat idle, and cost: three evenly spaced figures.
    private var footerLine: some View {
        let idleNow = machine.util < AppState.idleThreshold
        let idleFor = state.idleSince[machine.id].map { Date().timeIntervalSince($0) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 0) {
                stat(L("已开机", "Up"), machine.uptime.map(formatDuration) ?? "—")
                stat(L("GPU 空置", "GPU idle"), idleNow ? (idleFor.map(formatDuration) ?? "0m") : L("在用", "busy"),
                     shade: idle != nil ? SectionTheme.warn : nil)
                if let cost = machine.costPerHour {
                    stat(L("每小时", "Per hour"), cost.formatted)
                }
            }
            if let idle {
                Text(L("空置 \(idle) 分钟了，记得关机省钱", "Idle \(idle) min. Shut it down to stop paying"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SectionTheme.warn.gradient)
            }
        }
    }

    private func stat(_ label: String, _ value: String, shade: Shade? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(shade.map { AnyShapeStyle($0.gradient) } ?? AnyShapeStyle(.primary))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Status: View {
    var text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "moon.zzz").foregroundStyle(.secondary)
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Row: View {
    var label: String
    var value: Double
    var shade: Shade
    var detail: String
    var small = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            HStack(spacing: 7) {
                Circle().fill(shade.gradient).frame(width: 6, height: 6)
                Text(label)
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(Int(value.rounded()))%")
                .font(.system(size: small ? 14 : 18, weight: .semibold).monospacedDigit())
                .foregroundStyle(shade.gradient)
                .frame(width: 52, alignment: .trailing)

            Text(detail)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .frame(width: 82, alignment: .trailing)
        }
    }
}

/// Concentric rings: GPU use outside, VRAM inside.
struct Rings: View {
    var values: [Double]
    var theme: SectionTheme
    var warn = false
    private let diameters: [CGFloat] = [64, 42]

    var body: some View {
        ZStack {
            ForEach(Array(values.prefix(2).enumerated()), id: \.offset) { i, v in
                let shade = (warn && i == 0) ? SectionTheme.warn : theme.shade(i)
                Circle().stroke(shade.track, lineWidth: 8).frame(width: diameters[i], height: diameters[i])
                Circle()
                    .trim(from: 0, to: max(0.001, min(v, 100) / 100))
                    .stroke(shade.gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: diameters[i], height: diameters[i])
                    .animation(.easeOut(duration: 0.6), value: v)
            }
        }
        .frame(width: 76, height: 76)
    }
}

/// GPU use over the last hour or so, so a stalled run stands out at a glance.
struct Sparkline: View {
    var values: [Double]
    var shade: Shade

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                if pts.count > 1 {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                        pts.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: pts.last!.x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [Color(hex: shade.to, opacity: 0.25), Color(hex: shade.to, opacity: 0)],
                                         startPoint: .top, endPoint: .bottom))
                    Path { p in
                        p.move(to: pts[0])
                        pts.dropFirst().forEach { p.addLine(to: $0) }
                    }
                    .stroke(shade.gradient, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .frame(height: 22)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        let n = AppState.historyLength
        let step = size.width / CGFloat(max(n - 1, 1))
        let start = CGFloat(n - values.count) * step
        return values.enumerated().map { i, v in
            CGPoint(x: start + CGFloat(i) * step, y: size.height - 1 - CGFloat(min(v, 100) / 100) * (size.height - 2))
        }
    }
}

/// One glass card per account, stacked like the machines on the left.
struct AccountsColumn: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 10) {
            // Natural height for each card, so short accounts don't stretch into empty glass.
            ForEach(state.accounts) { AccountCell(account: $0).fixedSize(horizontal: false, vertical: true) }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Big balance on top, then a two-column list whose figures share one right edge,
/// so the decimal points line up down the column. Money is always blue; amber
/// only when the balance is about to run out.
private struct AccountCell: View {
    var account: Account

    private var low: Bool { (account.hoursLeft ?? .infinity) < 3 }
    private var blue: Shade { SectionTheme.accounts.shade(0) }

    var body: some View {
        Tile(theme: .accounts) {
            // Same header as a machine card: name in a pill, the key fact on the right.
            TileHeader(title: account.provider.title, detail: nil, theme: .accounts)
                .overlay(alignment: .trailing) {
                    if let h = account.hoursLeft {
                        Text(L("可用 ", "Lasts ") + duration(h))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(low ? SectionTheme.warn.gradient : SectionTheme.accounts.shade(0).gradient)
                    }
                }

            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("余额", "Balance")).font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(account.balance?.formatted ?? "—")
                        .font(.system(size: 24, weight: .semibold).monospacedDigit())
                        .tracking(-0.6)
                        .foregroundStyle(low ? SectionTheme.warn.gradient : blue.gradient)
                        .lineLimit(1)
                        .fixedSize()
                }
                Spacer(minLength: 6)
                if let week = account.weekSpend {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(L("本周", "This week")).font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(week.formatted)
                            .font(.system(size: 15, weight: .semibold).monospacedDigit())
                            .foregroundStyle(SectionTheme.accounts.shade(1).gradient)
                            .lineLimit(1)
                    }
                }
            }

            if let error = account.error {
                Text(error).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                let rows = figures
                if !rows.isEmpty {
                    VStack(spacing: 4) {
                        ForEach(rows, id: \.0) { line($0.0, $0.1) }
                    }
                    .padding(.top, 2)
                }
                if account.daily.contains(where: { $0 != nil }) {
                    DailyChart(values: account.daily, currency: account.balance?.currency ?? "CNY")
                        .padding(.top, 2)
                }
            }
        }
    }

    private var figures: [(String, String)] {
        var rows: [(String, String)] = []
        if let v = account.todaySpend { rows.append((L("今日", "Today"), v.formatted)) }
        if let v = account.totalSpend { rows.append((L("累计", "Total"), v.formatted)) }
        if let r = account.spendPerHour { rows.append((L("每小时", "Per hour"), r.amount > 0.001 ? r.formatted : L("未扣费", "—"))) }
        if let v = account.voucher { rows.append((L("代金券", "Vouchers"), v.formatted)) }
        return rows
    }

    private func line(_ label: String, _ value: String, warn: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 11.5)).foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(warn ? SectionTheme.warn.gradient : SectionTheme.accounts.shade(1).gradient)
                .lineLimit(1)
        }
    }

    private func duration(_ hours: Double) -> String {
        hours >= 48 ? L("约 \(Int(hours / 24)) 天", "~\(Int(hours / 24))d") : L("约 \(Int(hours)) 小时", "~\(Int(hours))h")
    }
}

/// Spend per day for the last week: a soft blue line with a dot per day, today's dot
/// filled and labeled, so a costly day stands out against the rest.
private struct DailyChart: View {
    var values: [Double?]
    var currency: String

    private var maxValue: Double { max(values.compactMap { $0 }.max() ?? 0, 0.01) }
    private var blue: Shade { SectionTheme.accounts.shade(0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("近 7 天", "Last 7 days")).font(.system(size: 11.5)).foregroundStyle(.secondary)
                Spacer()
                Text(L("最高 ", "Peak ") + Money(amount: maxValue, currency: currency).formatted)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                let pts = points(in: geo.size)
                ZStack(alignment: .topLeading) {
                    if pts.count > 1 {
                        Path { p in
                            p.move(to: CGPoint(x: pts[0].point.x, y: geo.size.height))
                            pts.forEach { p.addLine(to: $0.point) }
                            p.addLine(to: CGPoint(x: pts.last!.point.x, y: geo.size.height))
                            p.closeSubpath()
                        }
                        .fill(LinearGradient(colors: [Color(hex: blue.to, opacity: 0.28), Color(hex: blue.to, opacity: 0)],
                                             startPoint: .top, endPoint: .bottom))
                        Path { p in
                            p.move(to: pts[0].point)
                            pts.dropFirst().forEach { p.addLine(to: $0.point) }
                        }
                        .stroke(blue.gradient, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    }
                    ForEach(pts, id: \.index) { pt in
                        let today = pt.index == values.count - 1
                        Circle()
                            .fill(today ? AnyShapeStyle(blue.gradient) : AnyShapeStyle(Color(hex: blue.from)))
                            .frame(width: today ? 6 : 3.5, height: today ? 6 : 3.5)
                            .position(pt.point)
                    }
                }
            }
            .frame(height: 38)
            HStack(spacing: 0) {
                ForEach(Array(values.indices), id: \.self) { i in
                    Text(weekday(i))
                        .font(.system(size: 9.5, weight: i == values.count - 1 ? .semibold : .regular))
                        .foregroundStyle(i == values.count - 1 ? AnyShapeStyle(blue.gradient) : AnyShapeStyle(.tertiary))
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// One slot per day, evenly spaced; days without data are skipped by the line.
    private func points(in size: CGSize) -> [(index: Int, point: CGPoint)] {
        let slot = size.width / CGFloat(values.count)
        return values.enumerated().compactMap { i, v in
            guard let v else { return nil }
            let y = size.height - 3 - CGFloat(v / maxValue) * (size.height - 6)
            return (i, CGPoint(x: slot * (CGFloat(i) + 0.5), y: y))
        }
    }

    private func weekday(_ i: Int) -> String {
        let day = Calendar.current.date(byAdding: .day, value: i - (values.count - 1), to: Date())!
        let f = DateFormatter()
        f.locale = Language.locale
        f.dateFormat = Language.isChinese ? "EEEEE" : "EEEEE"
        return f.string(from: day)
    }
}

// MARK: - Glass

extension View {
    /// Native Liquid Glass on macOS 26; frosted material with a light rim on older systems.
    @ViewBuilder
    func glassSurface<S: Shape>(_ shape: S, tint: Color?, clear: Bool) -> some View {
        if #available(macOS 26.0, *) {
            let base: Glass = clear ? .clear : .regular
            self.glassEffect(tint.map { base.tint($0) } ?? base, in: shape)
        } else {
            self
                .background(tint ?? .clear, in: shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.4), lineWidth: 1))
        }
    }
}
