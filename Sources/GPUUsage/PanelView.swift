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
                        AccountsTile().frame(width: 170).frame(maxHeight: .infinity)
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

    private var footerLine: some View {
        HStack {
            if let idle {
                Text(L("空闲 \(idle) 分钟，记得关机", "Idle \(idle) min, shut it down?"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SectionTheme.warn.gradient)
            } else {
                Text(L("已开机", "Up")).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            if let cost = machine.costPerHour {
                Text(L("\(cost.formatted)/时", "\(cost.formatted)/h"))
                    .font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
            }
            if let up = machine.uptime {
                Text(formatDuration(up))
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
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

struct AccountsTile: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Tile(theme: .accounts) {
            TileHeader(title: L("余额", "Balance"), detail: nil, theme: .accounts)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(state.accounts.enumerated()), id: \.element.id) { i, a in
                    if i > 0 { Spacer(minLength: 12) } else { Spacer(minLength: 4) }
                    cell(a)
                }
                Spacer(minLength: 4)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func cell(_ a: Account) -> some View {
        let low = (a.hoursLeft ?? .infinity) < 3
        let shade = low ? SectionTheme.warn : a.provider.theme.shade(0)
        return VStack(alignment: .leading, spacing: 2) {
            Text(a.balance?.formatted ?? "—")
                .font(.system(size: 19, weight: .semibold).monospacedDigit())
                .foregroundStyle(shade.gradient)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(a.provider.title).font(.system(size: 12)).foregroundStyle(.secondary)
            if let error = a.error {
                Text(error).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            } else if let rate = a.spendPerHour {
                Text(rateText(rate, a.hoursLeft))
                    .font(.system(size: 11))
                    .foregroundStyle(low ? AnyShapeStyle(SectionTheme.warn.gradient) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            if let v = a.voucher {
                Text(L("代金券 \(v.formatted)", "Vouchers \(v.formatted)")).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private func rateText(_ rate: Money, _ hours: Double?) -> String {
        guard rate.amount > 0.001 else { return L("当前没有扣费", "Not spending now") }
        let per = L("\(rate.formatted)/时", "\(rate.formatted)/h")
        guard let hours else { return per }
        let left = hours >= 48 ? L("约 \(Int(hours / 24)) 天", "~\(Int(hours / 24))d") : L("约 \(Int(hours)) 小时", "~\(Int(hours))h")
        return "\(per) · \(left)"
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
