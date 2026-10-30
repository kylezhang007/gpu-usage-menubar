import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.editMenu()
        let state = AppState()
        controller = StatusController(state: state)
        let args = CommandLine.arguments
        if args.contains("--open") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.controller?.open() }
        }
        // Debug aid: `GPUUsage --snapshot out.png` renders the panel with live data and exits.
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            Task {
                while state.lastUpdated == nil { try? await Task.sleep(nanoseconds: 200_000_000) }
                Self.snapshot(state: state, to: args[i + 1])
                NSApp.terminate(nil)
            }
        }
    }

    /// A menu bar app has no visible menu, but ⌘C / ⌘V / ⌘X / ⌘A / ⌘Z in text fields are
    /// looked up in the main menu; without one, copy and paste silently do nothing.
    private static func editMenu() -> NSMenu {
        let main = NSMenu()
        let edit = NSMenu(title: "Edit")
        let items: [(String, Selector, String, NSEvent.ModifierFlags)] = [
            ("Undo", Selector(("undo:")), "z", .command),
            ("Redo", Selector(("redo:")), "z", [.command, .shift]),
            ("Cut", #selector(NSText.cut(_:)), "x", .command),
            ("Copy", #selector(NSText.copy(_:)), "c", .command),
            ("Paste", #selector(NSText.paste(_:)), "v", .command),
            ("Select All", #selector(NSText.selectAll(_:)), "a", .command),
        ]
        for (title, action, key, mods) in items {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = mods
            edit.addItem(item)
        }
        let editItem = NSMenuItem()
        editItem.submenu = edit
        main.addItem(NSMenuItem())   // app menu slot
        main.addItem(editItem)
        return main
    }

    private static func snapshot(state: AppState, to path: String) {
        print("machines:", state.machines, "\naccounts:", state.accounts)
        let view = PanelView().environmentObject(state).environment(\.colorScheme, .light)
            .padding(30)
            .background(LinearGradient(colors: [Color(hex: 0xFFF4C2), Color(hex: 0xB5E4FF), Color(hex: 0xBDEFB2)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let cg = renderer.cgImage {
            let rep = NSBitmapImageRep(cgImage: cg)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
    }
}

@main
enum GPUUsageMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
