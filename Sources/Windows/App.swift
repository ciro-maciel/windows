import AppKit
import SwiftUI

@main
enum Main {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--selftest") { exit(MainActor.assumeIsolated { SelfTest.run() }) }
        if let i = args.firstIndex(of: "--conflicts"), i + 1 < args.count {
            // `--conflicts ⌘N`-style probe of the conflict check, for the end-to-end test.
            MainActor.assumeIsolated { ConflictProbe.run(args[i + 1]) }
        }
        if let i = args.firstIndex(of: "--open-settings") {
            AppDelegate.openSettingsAtLaunch = i + 1 < args.count ? (Pane(rawValue: args[i + 1]) ?? .shortcuts) : .shortcuts
        }
        // `--open-editor new|<size name or id>`: the settings with the size editor open (scripts/screens.sh).
        if let i = args.firstIndex(of: "--open-editor"), i + 1 < args.count {
            AppDelegate.openSettingsAtLaunch = .shortcuts
            AppDelegate.editorAtLaunch = args[i + 1]
        }
        // One copy at a time: a second one would fight the first over every shortcut. The
        // end-to-end test (WINDOWS_LOG) and the screenshots (arguments) run their own copy.
        if args.count == 1, ProcessInfo.processInfo.environment["WINDOWS_LOG"] == nil, let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0.processIdentifier != getpid() }) {
            exit(0)
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

/// Lives in the menu bar: the status item menu, the shortcuts and the drag snapping.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var item: NSStatusItem!
    private var settings: NSWindow?
    private var trustTimer: Timer?
    private let state = AppState.shared
    /// `--open-settings [shortcuts|drag|general]`: opens the settings window at launch (scripts/screens.sh).
    nonisolated(unsafe) static var openSettingsAtLaunch: Pane?
    nonisolated(unsafe) static var editorAtLaunch: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Zen.registerFonts()
        HotKeys.shared.registerAll()
        Mover.shared.note("started; shortcuts refused: \(HotKeys.shared.failed.map(\.key).joined(separator: ","))")
        Snapping.shared.start(state.snapping)
        state.refresh()

        // When another window manager quits, take its shortcuts back right away.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            guard let id, AppState.rivals[id] != nil else { return }
            MainActor.assumeIsolated {
                HotKeys.shared.registerAll()
                AppState.shared.refresh()
                Mover.shared.note("rival quit: \(id); shortcuts registered again")
            }
        }

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // The app's square with the W cut out, 18 pt.
        if let img = Icon.image("menubar")?.copy() as? NSImage {
            img.size = NSSize(width: 18, height: 18)
            img.isTemplate = true
            item.button?.image = img
        }
        item.button?.toolTip = "Windows"
        item.button?.setAccessibilityLabel("Windows")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu

        if !state.trusted {
            // The system sheet that points to Accessibility, plus our own window explaining it.
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
            if ProcessInfo.processInfo.environment["WINDOWS_LOG"] == nil { openSettings(.shortcuts) }
            watchTrust()
        }
        if let pane = Self.openSettingsAtLaunch { openSettings(pane) }
    }

    /// Polls until Accessibility is granted (macOS sends no notification for it).
    private func watchTrust() {
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { return }
                if AXIsProcessTrusted() {
                    t.invalidate()
                    self.state.refresh()
                }
            }
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        state.refresh()
        menu.removeAllItems()
        if let rival = state.rival {
            let warn = entry(L("menu.rival", rival), icon: "alert-triangle", action: #selector(openSettingsFromMenu))
            menu.addItem(warn)
            menu.addItem(.separator())
        }
        if !state.trusted {
            menu.addItem(entry(L("menu.allowAccess"), icon: "lock", action: #selector(openAccessibility)))
            menu.addItem(.separator())
        }
        let config = Config.shared
        for (i, action) in WindowAction.keyboard.enumerated() {
            if i == 4 { menu.addItem(.separator()) }
            add(.action(action), title: action.title, to: menu)
        }
        if !config.layouts.isEmpty { menu.addItem(.separator()) }
        for layout in config.layouts { add(.layout(layout.id), title: layout.name, to: menu) }
        menu.addItem(.separator())
        let snap = entry(L("menu.snap"), icon: nil, action: #selector(toggleSnapping))
        snap.state = state.snapping ? .on : .off
        menu.addItem(snap)
        let login = entry(L("menu.openAtLogin"), icon: nil, action: #selector(toggleLogin))
        login.state = state.launchAtLogin ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        let prefs = entry(L("menu.settings"), icon: nil, action: #selector(openSettingsFromMenu))
        prefs.keyEquivalent = ","
        menu.addItem(prefs)
        let quit = entry(L("menu.quit"), icon: nil, action: #selector(quit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func add(_ command: Command, title: String, to menu: NSMenu) {
        let mi = entry(title, icon: nil, action: #selector(runCommand(_:)))
        mi.representedObject = command.key
        if let s = Config.shared.shortcut(command) {
            mi.keyEquivalent = s.menuKey
            mi.keyEquivalentModifierMask = s.modifiers
        }
        mi.isEnabled = state.trusted && (command != .action(.nextDisplay) || NSScreen.screens.count > 1)
        menu.addItem(mi)
    }

    private func entry(_ title: String, icon: String?, action: Selector) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
        mi.target = self
        if let icon, let img = Icon.image(icon)?.copy() as? NSImage {
            img.size = NSSize(width: 16, height: 16)
            img.isTemplate = true
            mi.image = img
        }
        return mi
    }

    @objc private func runCommand(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String,
              let command = Config.shared.commands.first(where: { $0.key == key }) else { return }
        // The menu does not activate this app, so the window in front is still the person's.
        Mover.shared.run(command, source: "menu")
    }

    @objc private func toggleSnapping() { state.snapping.toggle() }
    @objc private func toggleLogin() { state.setLaunchAtLogin(!state.launchAtLogin) }
    @objc private func openAccessibility() { AppState.openAccessibilitySettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc func openSettingsFromMenu() { openSettings(.shortcuts) }

    func openSettings(_ pane: Pane) {
        state.refresh()
        if settings == nil {
            let editing: CustomLayout? = Self.editorAtLaunch.map { name in
                Config.shared.layouts.first { $0.name == name || $0.id.uuidString == name } ?? CustomLayout(name: "", width: 70, height: 70, anchor: .center)
            }
            settings = MacShell.window(title: "Windows", size: SettingsView.size, minSize: SettingsView.minSize,
                                       autosave: "WindowsSettings",
                                       root: SettingsView(state: state, pane: pane, editing: editing))
        }
        NSApp.activate(ignoringOtherApps: true)
        settings?.makeKeyAndOrderFront(nil)
    }
}

/// `Windows --conflicts cmd+n`: prints who else uses a shortcut (system, open apps' menus).
@MainActor
enum ConflictProbe {
    static func run(_ spec: String) {
        var mods: NSEvent.ModifierFlags = []
        var key: UInt32?
        for part in spec.lowercased().split(separator: "+") {
            switch part {
            case "cmd": mods.insert(.command)
            case "opt": mods.insert(.option)
            case "ctrl": mods.insert(.control)
            case "shift": mods.insert(.shift)
            case "space": key = 49
            case "left": key = 123
            case "right": key = 124
            default:
                key = (0..<128).map(UInt32.init).first { Shortcut.character(for: $0)?.lowercased() == String(part) }
            }
        }
        guard let key else { print("tecla desconhecida"); exit(2) }
        let s = Shortcut(keyCode: key, modifiers: mods)
        Task {
            let list = await Conflicts.check(s, for: nil)
            print(s.text + ": " + (list.isEmpty ? "livre" : ""))
            list.forEach { print("  \($0.kind): \($0.text)") }
            exit(0)
        }
        RunLoop.main.run()
    }
}
