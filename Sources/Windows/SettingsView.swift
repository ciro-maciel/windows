import SwiftUI
import AppKit
import ServiceManagement

/// What the settings window and the menu show; one source for both.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var trusted = AXIsProcessTrusted()
    /// Who else uses each shortcut, by command key (Conflicts.check), filled when the settings open.
    @Published var conflicts: [String: [Conflict]] = [:]
    /// Another window manager running. macOS gives a shared shortcut to whoever registered it
    /// first and tells no one, so the only honest check is whether such an app is open.
    @Published var rival: String?

    static let rivals: [String: String] = [
        "com.knollsoft.Hookshot": "Rectangle Pro", "com.knollsoft.Rectangle": "Rectangle",
        "com.crowdcafe.windowmagnet": "Magnet", "com.manytricks.Moom": "Moom",
        "com.divisiblebyzero.Spectacle": "Spectacle", "com.hegenberg.BetterSnapTool": "BetterSnapTool",
        "com.sergey-gorbunov.Loop": "Loop", "com.lwouis.alt-tab-macos.divvy": "Divvy",
    ]

    static func runningRival() -> String? {
        NSWorkspace.shared.runningApplications.lazy.compactMap { $0.bundleIdentifier.flatMap { rivals[$0] } }.first
    }
    @Published var snapping: Bool = Config.store.object(forKey: "snapping") as? Bool ?? true {
        didSet {
            Config.store.set(snapping, forKey: "snapping")
            Snapping.shared.start(snapping)
        }
    }
    @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Windows: login item: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func refresh() {
        trusted = AXIsProcessTrusted()
        rival = Self.runningRival()
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Checks every shortcut against the system, the open apps and the other window managers.
    func scanConflicts() async {
        var found: [String: [Conflict]] = [:]
        let config = Config.shared
        for command in config.commands {
            guard let s = config.shortcut(command) else { continue }
            let list = await Conflicts.check(s, for: command).filter { $0.kind != .rival }
            if !list.isEmpty { found[command.key] = list }
        }
        conflicts = found
    }

    func scanConflicts(_ command: Command) async {
        guard let s = Config.shared.shortcut(command) else { conflicts[command.key] = nil; return }
        let list = await Conflicts.check(s, for: command).filter { $0.kind != .rival }
        conflicts[command.key] = list.isEmpty ? nil : list
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }
}

enum Pane: String, CaseIterable, Identifiable {
    case shortcuts, drag, general
    var id: String { rawValue }
    var title: String {
        L("pane.\(rawValue)")
    }
    var icon: String {
        switch self {
        case .shortcuts: return "keyboard"
        case .drag: return "drag-drop"
        case .general: return "settings"
        }
    }
    var subtitle: String {
        L("pane.\(rawValue).subtitle")
    }
}

/// The macOS app window (the Zen app frame, as in Cleaner): the wordmark and the
/// menu in a white sidebar, the page on the right.
struct SettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var config = Config.shared
    @State var pane: Pane = .shortcuts
    @State var editing: CustomLayout?

    static let size = CGSize(width: 1040, height: 860)
    static let minSize = CGSize(width: 960, height: 640)

    var body: some View {
        MacShellView {
            MacSidebar(app: "Windows") {
                MacSidebarGroup(title: L("settings.group")) {
                    ForEach(Pane.allCases) { p in
                        MacSidebarItem(icon: p.icon, title: p.title, active: pane == p) { pane = p }
                    }
                }
            } status: {
                MacStatusLine(on: state.trusted, onText: L("status.accessibilityOn"), offText: L("status.accessibilityOff")) {
                    AppState.openAccessibilitySettings()
                }
            }
        } content: {
            MacPage { content }
        }
        // The modal of the Zen design system: the whole window
        // dimmed in ink at 45%, no blur, a square box with no shadow, centered. Not the native
        // sheet, whose rounded shape and gray scrim are the system's, not ours.
        .overlay {
            if let layout = editing {
                ZStack {
                    Zen.gray9.opacity(0.45)
                        .contentShape(Rectangle())
                        .onTapGesture { closeEditor() }
                    LayoutEditor(draft: layout, isNew: config.layout(layout.id) == nil) { closeEditor() }
                        .id(layout.id)
                }
                .ignoresSafeArea()
            }
        }
        .task { await state.scanConflicts() }
    }

    private func closeEditor() {
        editing = nil
        Task { await state.scanConflicts() }
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            MacPageHeader(crumb: "Windows", title: pane.title, subtitle: pane.subtitle)
            if !state.trusted { permission.padding(.bottom, 24) }
            if let rival = state.rival { rivalNote(rival).padding(.bottom, 24) }

            switch pane {
            case .shortcuts:
                Text(L("shortcuts.positions")).zenLabel(10, color: Zen.gray5).padding(.bottom, 10)
                VStack(spacing: 0) {
                    ForEach(Array(WindowAction.keyboard.enumerated()), id: \.offset) { i, action in
                        if i > 0 { Rectangle().fill(Zen.gray2).frame(height: 1) }
                        CommandRow(command: .action(action), icon: .named(action.icon), title: action.title, note: action.note,
                                   shortcut: config.shortcut(.action(action)), conflicts: state.conflicts[Command.action(action).key] ?? []) { s in
                            config.setShortcut(s, for: .action(action))
                            Task { await state.scanConflicts(.action(action)) }
                        }
                    }
                }
                .zenBorder()
                .padding(.bottom, 28)

                HStack(alignment: .bottom) {
                    Text(L("shortcuts.sizes")).zenLabel(10, color: Zen.gray5)
                    Spacer()
                    Button {
                        editing = CustomLayout(name: "", width: 70, height: 70, anchor: .center)
                    } label: {
                        HStack(spacing: 6) { Icon(name: "plus", size: 14, color: .white); Text(L("shortcuts.newSize")) }
                    }
                    .buttonStyle(ZenButton())
                    .accessibilityIdentifier("layouts.add")
                }
                .padding(.bottom, 10)
                VStack(spacing: 0) {
                    if config.layouts.isEmpty {
                        Text(L("shortcuts.empty"))
                            .zenNote().padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(Array(config.layouts.enumerated()), id: \.element.id) { i, layout in
                        if i > 0 { Rectangle().fill(Zen.gray2).frame(height: 1) }
                        CommandRow(command: .layout(layout.id), icon: .thumb(layout), title: layout.name, note: layout.summary,
                                   shortcut: layout.shortcut, conflicts: state.conflicts[Command.layout(layout.id).key] ?? [],
                                   open: { editing = layout }) { s in
                            config.setShortcut(s, for: .layout(layout.id))
                            Task { await state.scanConflicts(.layout(layout.id)) }
                        }
                    }
                }
                .zenBorder()

                VStack(alignment: .trailing, spacing: 8) {
                    Text(L("shortcuts.hint"))
                        .font(Zen.font(11, .medium)).foregroundStyle(Zen.gray5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(L("shortcuts.reset")) {
                        config.resetShortcuts()
                        Task { await state.scanConflicts() }
                    }
                    .buttonStyle(.plain)
                    .font(Zen.font(11, .bold)).foregroundStyle(Zen.gray6)
                    .accessibilityIdentifier("shortcuts.reset")
                }
                .padding(.top, 12)
            case .drag:
                ToggleRow(on: state.snapping, title: L("drag.toggle"),
                          note: L("drag.toggle.note")) {
                    state.snapping.toggle()
                }
                .padding(.bottom, 24)
                Text(L("drag.where")).zenLabel(10, color: Zen.gray5).padding(.bottom, 10)
                VStack(spacing: 0) {
                    ForEach(Array([("layout-sidebar", L("drag.leftEdge"), WindowAction.leftHalf.title),
                                   ("layout-sidebar-right", L("drag.rightEdge"), WindowAction.rightHalf.title),
                                   ("maximize", L("drag.topEdge"), WindowAction.maximize.title),
                                   ("layout-grid", L("drag.corner"), L("drag.quarter"))].enumerated()), id: \.offset) { i, row in
                        if i > 0 { Rectangle().fill(Zen.gray2).frame(height: 1) }
                        HStack(spacing: 12) {
                            Icon(name: row.0, size: 16, color: Zen.gray7)
                            Text(row.1).font(Zen.font(13, .medium)).foregroundStyle(Zen.gray9)
                            Spacer()
                            Text(row.2).font(Zen.font(13, .medium)).foregroundStyle(Zen.gray6)
                        }
                        .padding(.horizontal, 16).frame(height: 46)
                    }
                }
                .zenBorder()
            case .general:
                ToggleRow(on: state.launchAtLogin, title: L("general.login"),
                          note: L("general.login.note")) {
                    state.setLaunchAtLogin(!state.launchAtLogin)
                }
            }
        }
    }

    private var permission: some View {
        HStack(alignment: .top, spacing: 14) {
            Icon(name: "lock", size: 18, color: Zen.gray9).padding(.top, 2)
            VStack(alignment: .leading, spacing: 10) {
                Text(L("permission.title")).font(Zen.font(13, .bold)).foregroundStyle(Zen.gray9)
                Text(L("permission.body"))
                    .zenNote().fixedSize(horizontal: false, vertical: true)
                Button { AppState.openAccessibilitySettings() } label: {
                    HStack(spacing: 8) { Text(L("permission.open")); Icon(name: "external-link", size: 14, color: .white) }
                }
                .buttonStyle(ZenButton())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Zen.gray1)
        .zenBorder(Zen.gray3)
    }

    private func rivalNote(_ name: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Icon(name: "alert-triangle", size: 18, color: Zen.gray9).padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text(L("rival.title", name)).font(Zen.font(13, .bold)).foregroundStyle(Zen.gray9)
                Text(L("rival.body", name))
                    .zenNote().fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Zen.gray1)
        .zenBorder(Zen.gray3)
    }
}

/// One line of the shortcuts: what it does, who else uses the shortcut, the recorder.
private struct CommandRow: View {
    enum Leading { case named(String), thumb(CustomLayout) }
    let command: Command
    let icon: Leading
    let title: String
    let note: String
    let shortcut: Shortcut?
    let conflicts: [Conflict]
    var open: (() -> Void)? = nil
    let onChange: (Shortcut?) -> Void
    @State private var hover = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 12) {
                switch icon {
                case .named(let name): Icon(name: name, size: 16, color: Zen.gray7).frame(width: 28)
                case .thumb(let layout): LayoutThumb(layout: layout, width: 28)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title).font(Zen.font(13, .medium)).foregroundStyle(Zen.gray9)
                        if open != nil && hover { Icon(name: "pencil", size: 12, color: Zen.gray5) }
                    }
                    if let first = conflicts.first {
                        Text(conflicts.count > 1 ? L("shortcuts.andMore", first.text, conflicts.count - 1) : first.text)
                            .font(Zen.font(11, .medium)).foregroundStyle(Zen.red7)
                            .fixedSize(horizontal: false, vertical: true)
                            .help(conflicts.map(\.text).joined(separator: "\n"))
                    } else if !note.isEmpty {
                        Text(note).font(Zen.font(11, .medium)).foregroundStyle(Zen.gray5)
                    }
                }
                Spacer(minLength: 12)
            }
            .contentShape(Rectangle())
            .onTapGesture { open?() }
            .accessibilityIdentifier(open == nil ? "" : "layout.row.\(title)")
            KeyRecorder(command: command, shortcut: shortcut, identifier: "shortcut.\(command.key)", onChange: onChange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 50)
        .background(hover && open != nil ? Zen.gray1 : Color.clear)
        .onHover { hover = $0 }
    }
}

private struct ToggleRow: View {
    let on: Bool
    let title: String
    let note: String
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 12) {
                Icon(name: on ? "square-check" : "square", size: 18, color: on ? Zen.gray9 : Zen.gray4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Zen.font(13, .medium)).foregroundStyle(Zen.gray9)
                    Text(note).font(Zen.font(11, .medium)).foregroundStyle(Zen.gray5)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .zenBorder()
    }
}

/// Compact primary button for tools: 32 px, letter 11 / 800 / uppercase, black rectangle.
struct ZenButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Zen.font(11, .extraBold)).tracking(1).textCase(.uppercase)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .foregroundStyle(.white)
            .background(Zen.gray9)
            .brightness(configuration.isPressed ? 0.08 : 0)
            .contentShape(Rectangle())
    }
}
