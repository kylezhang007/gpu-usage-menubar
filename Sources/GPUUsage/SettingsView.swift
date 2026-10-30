import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var servers: [Server] = []
    @State private var autodl = Keychain.get(.autodlToken) ?? ""
    @State private var runpod = Keychain.get(.runpodKey) ?? ""
    @State private var vast = Keychain.get(.vastKey) ?? ""
    @State private var tests: [UUID: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("设置", "Settings")).font(.system(size: 17, weight: .semibold))
                Spacer()
                Button(L("完成", "Done")) { save() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SectionTheme.accounts.shade(0).gradient)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassSurface(Capsule(), tint: nil, clear: state.clearGlass)

            Tile(theme: .autodl) {
                TileHeader(title: L("服务器", "Servers"), detail: nil, theme: .autodl)
                ForEach($servers) { $server in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Field(placeholder: L("名字", "Name"), text: $server.name).frame(width: 110)
                            Picker("", selection: $server.provider) {
                                ForEach(Provider.allCases) { Text($0.title).tag($0) }
                            }
                            .labelsHidden()
                            .frame(width: 96)
                            Spacer()
                            Button(L("测试", "Test")) { test(server) }.buttonStyle(.plain)
                                .font(.system(size: 12, weight: .medium))
                            Button { servers.removeAll { $0.id == server.id } } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        Field(placeholder: "ssh -p 12345 root@connect.westb.seetacloud.com", text: $server.ssh, mono: true)
                        if let result = tests[server.id] {
                            Text(result).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
                Button {
                    servers.append(Server(name: L("新服务器", "New server"), provider: .autodl, ssh: ""))
                } label: {
                    Label(L("添加服务器", "Add server"), systemImage: "plus.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                Hint(L("粘贴控制台给的 SSH 登录命令。需要先配好 SSH 免密登录（把 Mac 的公钥加到平台的 SSH 公钥设置里），程序不保存服务器密码。",
                       "Paste the SSH command from the console. Key login must already work (add your Mac's public key to the provider); no server password is stored."))
            }

            Tile(theme: .accounts) {
                TileHeader(title: L("账户", "Accounts"), detail: nil, theme: .accounts)
                KeyField(title: L("AutoDL 开发者 Token", "AutoDL developer token"), text: $autodl)
                KeyField(title: "RunPod API Key", text: $runpod)
                KeyField(title: "Vast.ai API Key", text: $vast)
                Hint(L("用来查余额。AutoDL 的 Token 在 控制台 → 设置 → 开发者 Token。RunPod 和 Vast.ai 的机器填好 Key 后会自动出现，不用再加 SSH。只保存在这台 Mac 的钥匙串里。",
                       "Used for balances. AutoDL's token is under Console → Settings → Developer Token. RunPod and Vast.ai machines appear automatically, no SSH needed. Stored only in this Mac's Keychain."))
            }

            Tile(theme: .other) {
                TileHeader(title: L("通用", "General"), detail: nil, theme: .other)
                Line(L("刷新间隔", "Refresh every")) {
                    Picker("", selection: $state.refreshSeconds) {
                        ForEach([30, 60, 120, 300], id: \.self) { s in
                            Text(s < 60 ? L("\(s) 秒", "\(s) sec") : L("\(s / 60) 分钟", "\(s / 60) min")).tag(s)
                        }
                    }
                    .labelsHidden().frame(width: 110)
                }
                Line(L("空闲提醒", "Idle alert")) {
                    Picker("", selection: $state.idleAlertMinutes) {
                        Text(L("关闭", "Off")).tag(0)
                        ForEach([15, 30, 60], id: \.self) { Text(L("\($0) 分钟", "\($0) min")).tag($0) }
                    }
                    .labelsHidden().frame(width: 110)
                }
                Line(L("玻璃效果", "Glass")) {
                    Picker("", selection: $state.clearGlass) {
                        Text(L("标准", "Standard")).tag(false)
                        Text(L("通透", "Clear")).tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 120)
                }
                Line(L("语言", "Language")) {
                    Picker("", selection: $state.language) {
                        Text(L("跟随系统", "System")).tag(Language.system)
                        Text("中文").tag(Language.chinese)
                        Text("English").tag(Language.english)
                    }
                    .labelsHidden().frame(width: 110)
                }
                Line(L("开机自动启动", "Open at login")) {
                    Toggle("", isOn: Binding(get: { state.launchAtLogin }, set: { state.launchAtLogin = $0 }))
                        .toggleStyle(.switch).controlSize(.small).labelsHidden()
                }
            }
        }
        .onAppear { servers = state.servers }
    }

    private func test(_ server: Server) {
        tests[server.id] = L("正在连接…", "Connecting…")
        Task {
            let m = await SSHProbe.probe(server)
            switch m.state {
            case .online:
                tests[server.id] = L("连接成功：\(m.gpuSummary ?? "GPU")，利用率 \(Int(m.util))%",
                                     "Connected: \(m.gpuSummary ?? "GPU"), \(Int(m.util))% busy")
            case .offline(let reason):
                tests[server.id] = reason
            default:
                tests[server.id] = nil
            }
        }
    }

    private func save() {
        Keychain.set(.autodlToken, autodl)
        Keychain.set(.runpodKey, runpod)
        Keychain.set(.vastKey, vast)
        state.servers = servers.filter { !$0.ssh.trimmingCharacters(in: .whitespaces).isEmpty }
        state.showingSettings = false
    }
}

private struct Field: View {
    var placeholder: String
    @Binding var text: String
    var mono = false

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(mono ? .system(size: 12, design: .monospaced) : .system(size: 13))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
    }
}

private struct KeyField: View {
    var title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
            SecureField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
        }
    }
}

private struct Line<Control: View>: View {
    var title: String
    @ViewBuilder var control: Control
    init(_ title: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.control = control()
    }
    var body: some View {
        HStack {
            Text(title).font(.system(size: 13))
            Spacer()
            control
        }
    }
}

private struct Hint: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
