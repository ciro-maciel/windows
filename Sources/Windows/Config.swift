import AppKit

/// What the person set: shortcuts that differ from the defaults and the sizes they made.
/// Saved as JSON in the user defaults; WINDOWS_DEFAULTS picks another suite (the end-to-end test
/// uses its own, so it never touches the person's settings).
@MainActor
final class Config: ObservableObject {
    static let shared = Config()

    static let store: UserDefaults = ProcessInfo.processInfo.environment["WINDOWS_DEFAULTS"]
        .flatMap { UserDefaults(suiteName: $0) } ?? .standard

    private struct Saved: Codable {
        var shortcuts: [String: Shortcut?] = [:]
        var layouts: [CustomLayout] = CustomLayout.defaults
    }

    /// Shortcut per action key; a present nil means "the person removed it".
    @Published private(set) var overrides: [String: Shortcut?]
    @Published private(set) var layouts: [CustomLayout]

    init() {
        let saved = Self.store.data(forKey: "config").flatMap { try? JSONDecoder().decode(Saved.self, from: $0) } ?? Saved()
        overrides = saved.shortcuts
        layouts = saved.layouts
    }

    private func persist() {
        let data = try? JSONEncoder().encode(Saved(shortcuts: overrides, layouts: layouts))
        Self.store.set(data, forKey: "config")
        HotKeys.shared.registerAll()
    }

    // MARK: - Reading

    /// Every command that can carry a shortcut, in the order of the menu.
    var commands: [Command] { WindowAction.keyboard.map(Command.action) + layouts.map { .layout($0.id) } }

    func shortcut(_ command: Command) -> Shortcut? {
        switch command {
        case .action(let a): return overrides.keys.contains(command.key) ? overrides[command.key]! : a.defaultShortcut
        case .layout(let id): return layout(id)?.shortcut
        }
    }

    func layout(_ id: UUID) -> CustomLayout? { layouts.first { $0.id == id } }

    func title(_ command: Command) -> String {
        switch command {
        case .action(let a): return a.title
        case .layout(let id): return layout(id)?.name ?? "Tamanho"
        }
    }

    /// The command that already has this shortcut, other than `except`.
    func owner(of shortcut: Shortcut, except: Command?) -> Command? {
        commands.first { $0 != except && self.shortcut($0) == shortcut }
    }

    // MARK: - Writing

    func setShortcut(_ shortcut: Shortcut?, for command: Command) {
        switch command {
        case .action(let a):
            if shortcut == a.defaultShortcut { overrides[command.key] = nil } else { overrides[command.key] = .some(shortcut) }
        case .layout(let id):
            guard let i = layouts.firstIndex(where: { $0.id == id }) else { return }
            layouts[i].shortcut = shortcut
        }
        persist()
    }

    func save(_ layout: CustomLayout) {
        if let i = layouts.firstIndex(where: { $0.id == layout.id }) { layouts[i] = layout } else { layouts.append(layout) }
        persist()
    }

    func delete(_ id: UUID) {
        layouts.removeAll { $0.id == id }
        persist()
    }

    /// Back to the shortcuts the app ships with; the sizes stay.
    func resetShortcuts() {
        overrides = [:]
        for d in CustomLayout.defaults {
            if let i = layouts.firstIndex(where: { $0.id == d.id }) { layouts[i].shortcut = d.shortcut }
        }
        persist()
    }
}
