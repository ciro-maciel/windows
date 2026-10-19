import AppKit
import Carbon.HIToolbox

/// Who else uses a shortcut. macOS has no API for "is this combination taken": a global hot key
/// registered by another app is invisible, so the check covers what can be seen:
/// this app's own table, the system shortcuts (System Settings > Keyboard > Keyboard Shortcuts), another window
/// manager running, and the menus of every open app.
struct Conflict: Hashable {
    enum Kind: Hashable { case own, system, rival, app }
    let kind: Kind
    let text: String

    /// Own clashes are refused; the others are warnings the person may accept.
    var blocks: Bool { kind == .own }
}

enum Conflicts {
    /// System shortcuts that are on, from HIToolbox (the same list the keyboard settings show).
    static func system(_ s: Shortcut) -> String? {
        var array: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&array) == noErr, let list = array?.takeRetainedValue() as? [[String: Any]] else { return nil }
        let wanted = s.carbonModifiers
        for entry in list {
            guard (entry["kHISymbolicHotKeyEnabled"] as? Bool) == true,
                  let code = entry["kHISymbolicHotKeyCode"] as? Int, code == Int(s.keyCode),
                  let mods = entry["kHISymbolicHotKeyModifiers"] as? Int,
                  UInt32(mods) & UInt32(cmdKey | shiftKey | optionKey | controlKey) == wanted else { continue }
            return knownSystem[s].map { L($0) } ?? L("system.generic")
        }
        return nil
    }

    /// The best known system shortcuts, by string key (the HIToolbox list carries no names).
    private static let knownSystem: [Shortcut: String] = {
        func k(_ key: Int, _ m: NSEvent.ModifierFlags) -> Shortcut { Shortcut(keyCode: UInt32(key), modifiers: m) }
        return [
            k(kVK_Space, .command): "system.spotlight",
            k(kVK_Space, [.option, .command]): "system.finderSearch",
            k(kVK_Space, .control): "system.previousInput",
            k(kVK_Space, [.control, .option]): "system.nextInput",
            k(kVK_ANSI_3, [.shift, .command]): "system.screenshot",
            k(kVK_ANSI_4, [.shift, .command]): "system.screenshotPart",
            k(kVK_ANSI_5, [.shift, .command]): "system.screenshotApp",
            k(kVK_ANSI_3, [.control, .shift, .command]): "system.copyScreen",
            k(kVK_ANSI_4, [.control, .shift, .command]): "system.copyPart",
            k(kVK_UpArrow, .control): "system.missionControl",
            k(kVK_DownArrow, .control): "system.appWindows",
            k(kVK_LeftArrow, .control): "system.spaceLeft",
            k(kVK_RightArrow, .control): "system.spaceRight",
            k(kVK_ANSI_D, [.option, .command]): "system.dock",
            k(kVK_Tab, .command): "system.switchApps",
            k(kVK_ANSI_Grave, .command): "system.switchWindows",
            k(kVK_Escape, [.option, .command]): "system.forceQuit",
            k(kVK_F11, []): "system.showDesktop",
        ]
    }()

    @MainActor static func rival() -> String? { AppState.runningRival() }

    /// Menu items of the open apps with this shortcut: (app, item). A global shortcut wins
    /// over a menu, so the app loses it while this one is set. Runs off the main thread; each app
    /// gets a short Accessibility timeout so a busy app cannot stall the check.
    nonisolated static func apps(_ s: Shortcut, character: String?) -> [(app: String, item: String)] {
        let me = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != me
        }
        var found: [(app: String, item: String)] = []
        for app in apps {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.3)
            var bar: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXMenuBarAttribute as CFString, &bar) == .success, let bar else { continue }
            if let title = search(bar as! AXUIElement, s, character: character, depth: 0) {
                found.append((app.localizedName ?? L("conflict.anApp"), title))
            }
        }
        return found
    }

    private static let attributes = [kAXTitleAttribute, kAXMenuItemCmdCharAttribute, kAXMenuItemCmdModifiersAttribute,
                                     kAXMenuItemCmdVirtualKeyAttribute, kAXMenuItemCmdGlyphAttribute, kAXChildrenAttribute] as CFArray

    /// Menu glyph codes (Carbon) for the special keys a shortcut can use.
    private static let glyphKeys: [Int: Int] = [
        0x64: kVK_LeftArrow, 0x65: kVK_RightArrow, 0x68: kVK_UpArrow, 0x6A: kVK_DownArrow,
        0x0B: kVK_Return, 0x17: kVK_Delete, 0x09: kVK_Space, 0x02: kVK_Tab, 0x1B: kVK_Escape,
    ]

    private static func search(_ element: AXUIElement, _ s: Shortcut, character: String?, depth: Int) -> String? {
        guard depth < 5 else { return nil }
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, attributes, AXCopyMultipleAttributeOptions(rawValue: 0), &values) == .success,
              let list = values as? [Any], list.count == 6 else { return nil }
        let title = list[0] as? String
        if let mods = list[2] as? Int, matches(mods: mods, char: list[1] as? String, virtualKey: list[3] as? Int,
                                                glyph: list[4] as? Int, s, character: character) {
            return title ?? L("conflict.aMenuItem")
        }
        for child in (list[5] as? [AXUIElement]) ?? [] {
            if let hit = search(child, s, character: character, depth: depth + 1) { return hit }
        }
        return nil
    }

    /// AX menu modifiers: bit 0 shift, 1 option, 2 control, 3 "no command"; 0 means ⌘ alone.
    private static func matches(mods: Int, char: String?, virtualKey: Int?, glyph: Int?, _ s: Shortcut, character: String?) -> Bool {
        var flags: NSEvent.ModifierFlags = []
        if mods & 1 != 0 { flags.insert(.shift) }
        if mods & 2 != 0 { flags.insert(.option) }
        if mods & 4 != 0 { flags.insert(.control) }
        if mods & 8 == 0 { flags.insert(.command) }
        guard flags == s.modifiers else { return false }
        if let virtualKey, virtualKey != 0 || char == nil { return virtualKey == Int(s.keyCode) }
        if let glyph, let key = glyphKeys[glyph] { return key == Int(s.keyCode) }
        if let char, !char.isEmpty, let character { return char.uppercased() == character.uppercased() }
        return false
    }

    /// Everything known about a shortcut for a command, own clash first.
    @MainActor
    static func check(_ s: Shortcut, for command: Command?) async -> [Conflict] {
        var result: [Conflict] = []
        if let owner = Config.shared.owner(of: s, except: command) {
            result.append(Conflict(kind: .own, text: L("conflict.own", Config.shared.title(owner))))
        }
        if let name = system(s) { result.append(Conflict(kind: .system, text: L("conflict.system", s.text, name))) }
        if let rival = rival() { result.append(Conflict(kind: .rival, text: L("conflict.rival", rival, s.text))) }
        let character = Shortcut.character(for: s.keyCode)
        let hits = await Task.detached { apps(s, character: character) }.value
        for hit in hits.prefix(3) {
            result.append(Conflict(kind: .app, text: L("conflict.app", hit.app, s.text, hit.item)))
        }
        return result
    }
}
