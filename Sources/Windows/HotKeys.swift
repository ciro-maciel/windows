import AppKit
import Carbon.HIToolbox

/// Global shortcuts through Carbon's RegisterEventHotKey: no permission needed to listen, and
/// the key never reaches the app in front. The table comes from Config.
@MainActor
final class HotKeys {
    static let shared = HotKeys()

    private var refs: [EventHotKeyRef] = []
    private var commands: [UInt32: Command] = [:]
    private var handler: EventHandlerRef?
    private var paused = false
    /// Shortcuts the system refused (RegisterEventHotKey only reports clashes inside this app).
    private(set) var failed: [Command] = []

    func registerAll() {
        unregisterAll()
        guard !paused else { return }
        installHandler()
        let config = Config.shared
        for (i, command) in config.commands.enumerated() {
            guard let s = config.shortcut(command) else { continue }
            let id = UInt32(i + 1)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(s.keyCode, s.carbonModifiers, EventHotKeyID(signature: OSType(0x5749_4E44), id: id),
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
                commands[id] = command
            } else {
                failed.append(command)
            }
        }
    }

    /// While a shortcut is being recorded, pressing an existing one must not move a window.
    func pause(_ on: Bool) {
        paused = on
        registerAll()
    }

    func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        commands = [:]
        failed = []
    }

    fileprivate func fire(_ id: UInt32) {
        guard let command = commands[id] else { return }
        Mover.shared.run(command, source: "key")
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let value = id.id
            MainActor.assumeIsolated { HotKeys.shared.fire(value) }
            return noErr
        }, 1, &spec, nil, &handler)
    }
}
