// End-to-end test of the built app, as a person uses it: opens its own window, presses the real
// shortcuts (system key events), drags the window to the edges with the mouse, clicks the menu bar
// menu, and checks where the window landed, with its own math, not the app's.
//
//   scripts/e2e.sh            (builds this and runs it against dist/Windows.app)
//
// Needs Accessibility for the terminal that runs it (to post events and press the menu).

import AppKit
import ApplicationServices
import Carbon.HIToolbox

let appPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dist/Windows.app"
let shotDir = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : NSTemporaryDirectory()
let logPath = NSTemporaryDirectory() + "windows-e2e-\(getpid()).log"
/// Settings of the app under test live in their own suite: the person's are never touched.
let suite = "click.ciromaciel.windows.e2e"

/// The configuration the test starts from: ⌃⌥J instead of ⌃⌥C to center (a letter, not an arrow:
/// with Fn, as the test sends arrows, ⌃+arrow is macOS's own tiling), the three
/// sizes that ship, and one more ("Teste", 50% × 50% at the bottom right, ⌃⌥K).
func seedConfig() {
    let ctrlOpt = 786432, opt = 524288
    func layout(_ id: String, _ name: String, _ w: Double, _ h: Double, _ anchor: String, _ key: Int, _ flags: Int) -> [String: Any] {
        ["id": id, "name": name, "width": w, "height": h, "unit": "percent", "anchor": anchor, "display": "current",
         "shortcut": ["keyCode": key, "flags": flags]]
    }
    let config: [String: Any] = [
        "shortcuts": ["action:center": ["keyCode": kVK_ANSI_J, "flags": ctrlOpt]],
        "layouts": [
            layout("6F0A1C2E-0001-4000-8000-000000000097", "Quase inteira", 97.1, 97, "center", kVK_ANSI_F, opt),
            layout("6F0A1C2E-0002-4000-8000-000000000080", "Grande", 80, 80, "top", kVK_ANSI_D, opt),
            layout("6F0A1C2E-0003-4000-8000-000000000060", "Média", 60, 60, "top", kVK_ANSI_S, opt),
            layout("E2E00000-0000-4000-8000-000000000050", "Teste", 50, 50, "bottomRight", kVK_ANSI_K, ctrlOpt),
        ],
    ]
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defaults.set(try! JSONSerialization.data(withJSONObject: config), forKey: "config")
    defaults.synchronize()
}

/// The configuration as the app saved it.
func savedConfig() -> [String: Any] {
    CFPreferencesAppSynchronize(suite as CFString)
    guard let data = UserDefaults(suiteName: suite)?.data(forKey: "config"),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return json
}

final class Runner {
    var window: NSWindow!
    var windowsApp: Process!
    var failures = 0
    var previousApp: NSRunningApplication?
    var previousMouse = CGPoint.zero

    var screen: NSScreen { NSScreen.screens[0] }
    var visible: CGRect { screen.visibleFrame }
    var pivot: CGFloat { NSScreen.screens[0].frame.maxY }

    func pause(_ s: Double) { Thread.sleep(forTimeInterval: s) }
    func main<T>(_ f: () -> T) -> T { DispatchQueue.main.sync(execute: f) }

    func check(_ name: String, want: CGRect, logged: String? = nil) {
        pause(0.5)
        let got = main { window.frame }
        var ok = abs(got.minX - want.minX) <= 2 && abs(got.minY - want.minY) <= 2
            && abs(got.width - want.width) <= 2 && abs(got.height - want.height) <= 2
        var why = ok ? "" : ": janela em \(got.integral), esperado \(want.integral)"
        if ok, let logged {
            let log = (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? ""
            if !log.split(separator: "\n").contains(where: { $0.hasPrefix(logged) }) {
                ok = false
                why = ": a janela foi para o lugar, mas o Windows não registrou \"\(logged)\" (outro app atendeu?)"
            }
        }
        if !ok {
            failures += 1
            let log = (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? ""
            why += "\n     log: " + log.replacingOccurrences(of: "\n", with: " | ")
            let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
            let others = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier).filter { $0.hasPrefix("com.knollsoft") }
            why += "\n     em primeiro plano: \(front); outros gerenciadores: \(others.isEmpty ? "nenhum" : others.joined(separator: ", "))"
        }
        print("\(ok ? "ok  " : "FAIL") \(name)\(why)")
    }

    func resetLog() { try? "".write(toFile: logPath, atomically: true, encoding: .utf8) }

    func place(_ r: CGRect) {
        main { window.setFrame(r, display: true); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil) }
        pause(0.3)
    }

    func press(_ key: Int, _ flags: CGEventFlags, focusTest: Bool = true) {
        resetLog()
        // Shortcuts act on the window in front; another app may have come forward meanwhile.
        if focusTest {
            main { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil) }
            pause(0.15)
        }
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(key), keyDown: down)!
            // A real keyboard marks arrows and Return with these; Carbon matches on them too.
            let arrows = [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow].contains(key)
            e.flags = arrows ? flags.union([.maskNumericPad, .maskSecondaryFn]) : flags
            e.post(tap: .cghidEventTap)
            pause(0.03)
        }
    }

    func mouse(_ type: CGEventType, _ p: CGPoint) {
        let ax = CGPoint(x: p.x, y: pivot - p.y)
        CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: type, mouseCursorPosition: ax, mouseButton: .left)!
            .post(tap: .cghidEventTap)
    }

    /// Grabs the title bar and drags to `to` (Cocoa coordinates) in small steps.
    func drag(to: CGPoint, screenshot: String? = nil) {
        resetLog()
        let f = main { window.frame }
        let from = CGPoint(x: f.midX, y: f.maxY - 14)
        mouse(.mouseMoved, from); pause(0.15)
        mouse(.leftMouseDown, from); pause(0.15)
        let steps = 30
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            mouse(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
            pause(0.015)
        }
        pause(0.3)
        if let screenshot {
            let task = Process()
            task.launchPath = "/usr/sbin/screencapture"
            task.arguments = ["-x", "-C", "\(shotDir)/\(screenshot).png"]
            try? task.run(); task.waitUntilExit()
        }
        mouse(.leftMouseUp, to)
        pause(0.2)
    }

    /// Opens the status item menu through Accessibility and presses an item by title.
    func menu(_ title: String) -> Bool {
        resetLog()
        let app = AXUIElementCreateApplication(windowsApp.processIdentifier)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &bar) == .success, let bar else { return false }
        var items: CFTypeRef?
        AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &items)
        guard let status = (items as? [AXUIElement])?.first else { return false }
        AXUIElementPerformAction(status, kAXPressAction as CFString)
        pause(0.4)
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(status, kAXChildrenAttribute as CFString, &children)
        guard let menu = (children as? [AXUIElement])?.first else { return false }
        var entries: CFTypeRef?
        AXUIElementCopyAttributeValue(menu, kAXChildrenAttribute as CFString, &entries)
        for e in (entries as? [AXUIElement]) ?? [] {
            var t: CFTypeRef?
            AXUIElementCopyAttributeValue(e, kAXTitleAttribute as CFString, &t)
            if (t as? String) == title {
                AXUIElementPerformAction(e, kAXPressAction as CFString)
                return true
            }
        }
        AXUIElementPerformAction(menu, kAXCancelAction as CFString)
        return false
    }

    func run() {
        let v = visible
        let halfW = (v.width / 2).rounded(.down), halfH = (v.height / 2).rounded(.down)
        let start = CGRect(x: v.minX + 200, y: v.minY + 200, width: 720, height: 480)
        let ctrlOpt: CGEventFlags = [.maskControl, .maskAlternate]

        print("Tela: \(Int(screen.frame.width))×\(Int(screen.frame.height)), área útil \(v.integral)\n")
        print("Atalhos")
        place(start); press(kVK_LeftArrow, ctrlOpt)
        check("⌃⌥← metade esquerda", want: CGRect(x: v.minX, y: v.minY, width: halfW, height: v.height), logged: "key leftHalf")
        press(kVK_RightArrow, ctrlOpt)
        check("⌃⌥→ metade direita", want: CGRect(x: v.minX + halfW, y: v.minY, width: v.width - halfW, height: v.height), logged: "key rightHalf")
        press(kVK_UpArrow, ctrlOpt)
        check("⌃⌥↑ metade de cima", want: CGRect(x: v.minX, y: v.minY + halfH, width: v.width, height: v.height - halfH), logged: "key topHalf")
        press(kVK_DownArrow, ctrlOpt)
        check("⌃⌥↓ metade de baixo", want: CGRect(x: v.minX, y: v.minY, width: v.width, height: halfH), logged: "key bottomHalf")
        press(kVK_Return, ctrlOpt)
        check("⌃⌥↩ tela inteira", want: v, logged: "key maximize")
        func sized(_ fw: CGFloat, _ fh: CGFloat, top: Bool) -> CGRect {
            let w = (v.width * fw).rounded(), h = (v.height * fh).rounded()
            return CGRect(x: (v.midX - w / 2).rounded(), y: top ? v.maxY - h : (v.midY - h / 2).rounded(), width: w, height: h)
        }
        press(kVK_ANSI_F, .maskAlternate)
        check("⌥F quase inteira (97%)", want: sized(0.971, 0.970, top: false), logged: "key layout:Quase inteira")
        press(kVK_ANSI_D, .maskAlternate)
        check("⌥D grande (80%, em cima)", want: sized(0.80, 0.80, top: true), logged: "key layout:Grande")
        press(kVK_ANSI_S, .maskAlternate)
        check("⌥S média (60%, em cima)", want: sized(0.60, 0.60, top: true), logged: "key layout:Média")

        press(kVK_ANSI_K, ctrlOpt)
        check("⌃⌥K tamanho próprio (50%, embaixo à direita)", want: CGRect(x: v.maxX - (v.width * 0.5).rounded(), y: v.minY,
                                                                        width: (v.width * 0.5).rounded(), height: (v.height * 0.5).rounded()),
              logged: "key layout:Teste")
        place(start); press(kVK_ANSI_C, ctrlOpt)
        check("⌃⌥C trocado por ⌃⌥J: não faz mais nada", want: start)
        press(kVK_ANSI_J, ctrlOpt)
        check("⌃⌥J centralizar (atalho trocado)", want: CGRect(x: (v.midX - 360).rounded(), y: (v.midY - 240).rounded(), width: 720, height: 480), logged: "key center")
        place(start); press(kVK_Return, ctrlOpt)
        check("⌃⌥↩ tela inteira (antes de voltar)", want: v, logged: "key maximize")
        press(kVK_Delete, ctrlOpt)
        check("⌃⌥⌫ volta ao tamanho de antes", want: start, logged: "key restore")

        print("\nMenu da barra")
        place(start)
        let pressed = menu("Metade direita")
        if !pressed { failures += 1; print("FAIL menu: item \"Metade direita\" não encontrado") }
        else { check("menu → Metade direita", want: CGRect(x: v.minX + halfW, y: v.minY, width: v.width - halfW, height: v.height), logged: "menu rightHalf") }

        print("\nArrastar")
        let f = screen.frame
        place(start); drag(to: CGPoint(x: f.minX, y: f.midY), screenshot: "arrastar-esquerda")
        check("borda esquerda → metade esquerda", want: CGRect(x: v.minX, y: v.minY, width: halfW, height: v.height), logged: "drag leftHalf")
        place(start); drag(to: CGPoint(x: f.maxX - 1, y: f.midY))
        check("borda direita → metade direita", want: CGRect(x: v.minX + halfW, y: v.minY, width: v.width - halfW, height: v.height), logged: "drag rightHalf")
        place(start); drag(to: CGPoint(x: f.midX, y: f.maxY - 1), screenshot: "arrastar-topo")
        check("borda de cima → tela inteira", want: v, logged: "drag maximize")
        place(start); drag(to: CGPoint(x: f.minX, y: f.maxY - 1))
        check("canto de cima à esquerda → um quarto", want: CGRect(x: v.minX, y: v.minY + halfH, width: halfW, height: v.height - halfH), logged: "drag topLeft")
        place(start); drag(to: CGPoint(x: f.maxX - 1, y: f.minY))
        check("canto de baixo à direita → um quarto", want: CGRect(x: v.minX + halfW, y: v.minY, width: v.width - halfW, height: halfH), logged: "drag bottomRight")
        place(start); drag(to: CGPoint(x: f.midX, y: f.midY))
        pause(0.5)
        let after = main { window.frame }
        let logAfter = (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? ""
        let snapped = logAfter.split(separator: "\n").contains { $0.hasPrefix("drag ") && !$0.hasPrefix("drag up") }
        let ok = after.size == start.size && !snapped
        if !ok { failures += 1 }
        print("\(ok ? "ok  " : "FAIL") meio da tela → não encaixa\(ok ? "" : ": \(after.integral)")")

        print("\nAjustes: gravar atalho")
        if press(id: "shortcut.action:rightHalf") {
            pause(0.4); press(kVK_ANSI_L, ctrlOpt, focusTest: false); pause(0.6)
            let saved = ((savedConfig()["shortcuts"] as? [String: Any])?["action:rightHalf"] as? [String: Any])?["keyCode"] as? Int
            report("gravador: ⌃⌥L salvo para Metade direita", saved == kVK_ANSI_L, "salvo: \(String(describing: saved))")
            place(start); press(kVK_ANSI_L, ctrlOpt)
            check("⌃⌥L metade direita (gravado na tela)", want: CGRect(x: v.minX + halfW, y: v.minY, width: v.width - halfW, height: v.height), logged: "key rightHalf")
        }
        if press(id: "shortcut.action:topHalf") {
            pause(0.4); press(kVK_ANSI_F, .maskAlternate, focusTest: false); pause(0.6)
            let taken = (savedConfig()["shortcuts"] as? [String: Any])?["action:topHalf"] == nil
            var text: CFTypeRef?
            if let m = find("shortcut.action:topHalf.message") { AXUIElementCopyAttributeValue(m, kAXValueAttribute as CFString, &text) }
            let said = (text as? String) ?? ""
            report("gravador: ⌥F recusado com aviso (\(said))", taken && said.contains("Quase inteira"),
                   taken ? "sem a mensagem de recusa na tela" : "o atalho foi aceito")
            press(kVK_Escape, [], focusTest: false)
        }

        print("\nAjustes: novo tamanho")
        if press(id: "layouts.add") {
            pause(0.8)
            if focus(id: "layout.name") { type("Canto E2E") }
            _ = press(id: "layout.anchor.topRight")
            if press(id: "layout.shortcut") { pause(0.4); press(kVK_ANSI_P, ctrlOpt, focusTest: false); pause(0.6) }
            _ = press(id: "layout.save")
            pause(0.8)
            let made = (savedConfig()["layouts"] as? [[String: Any]])?.first { $0["name"] as? String == "Canto E2E" }
            let okLayout = made?["anchor"] as? String == "topRight" && (made?["shortcut"] as? [String: Any])?["keyCode"] as? Int == kVK_ANSI_P
            report("+ cria “Canto E2E”: 70% × 70%, em cima à direita, ⌃⌥P", okLayout, "salvo: \(String(describing: made))")
            place(start); press(kVK_ANSI_P, ctrlOpt)
            let w7 = (v.width * 0.7).rounded(), h7 = (v.height * 0.7).rounded()
            check("⌃⌥P leva ao tamanho novo", want: CGRect(x: v.maxX - w7, y: v.maxY - h7, width: w7, height: h7), logged: "key layout:Canto E2E")
        }

        print("\nConflitos")
        let spotlight = probe("cmd+space")
        report("⌘Espaço: o macOS usa (Spotlight)", spotlight.contains("system:"), spotlight)
        let finder = probe("cmd+n")
        report("⌘N: o Finder usa no menu", finder.contains("Finder"), finder)
        let mine = probe("ctrl+opt+k")
        report("⌃⌥K: já é de um tamanho do Windows", mine.contains("own:") || mine.contains("livre"), mine)
    }

    func report(_ name: String, _ ok: Bool, _ why: String) {
        if !ok { failures += 1 }
        print("\(ok ? "ok  " : "FAIL") \(name)\(ok ? "" : ": \(why)")")
    }

    /// `Windows --conflicts <spec>` against the default settings of a separate suite.
    func probe(_ spec: String) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "\(appPath)/Contents/MacOS/Windows")
        task.arguments = ["--conflicts", spec]
        task.environment = ProcessInfo.processInfo.environment.merging(["WINDOWS_DEFAULTS": suite]) { $1 }
        let out = Pipe()
        task.standardOutput = out
        try? task.run()
        task.waitUntilExit()
        return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    // MARK: - Driving the settings window through Accessibility

    func find(_ id: String) -> AXUIElement? {
        let app = AXUIElementCreateApplication(windowsApp.processIdentifier)
        var windows: CFTypeRef?
        AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows)
        func search(_ e: AXUIElement, _ depth: Int) -> AXUIElement? {
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(e, kAXIdentifierAttribute as CFString, &value)
            if value as? String == id { return e }
            guard depth < 30 else { return nil }
            var children: CFTypeRef?
            AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &children)
            for c in (children as? [AXUIElement]) ?? [] { if let hit = search(c, depth + 1) { return hit } }
            return nil
        }
        for w in (windows as? [AXUIElement]) ?? [] { if let hit = search(w, 0) { return hit } }
        return nil
    }

    /// Brings the Windows app forward (its window must be key to record) and presses an element.
    func press(id: String) -> Bool {
        NSRunningApplication(processIdentifier: windowsApp.processIdentifier)?.activate()
        pause(0.3)
        guard let e = find(id) else { report("achar \(id) na tela de Ajustes", false, "não encontrado"); return false }
        AXUIElementPerformAction(e, kAXPressAction as CFString)
        return true
    }

    func focus(id: String) -> Bool {
        guard let e = find(id) else { report("achar \(id) na tela de Ajustes", false, "não encontrado"); return false }
        AXUIElementSetAttributeValue(e, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        pause(0.2)
        return true
    }

    func type(_ text: String) {
        let src = CGEventSource(stateID: .hidSystemState)
        for ch in text.utf16 {
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down)!
                var c = ch
                e.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
                e.post(tap: .cghidEventTap)
            }
            pause(0.02)
        }
        pause(0.2)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let runner = Runner()
runner.previousApp = NSWorkspace.shared.frontmostApplication
runner.previousMouse = CGEvent(source: nil)?.location ?? .zero

guard AXIsProcessTrusted() else { print("Este terminal precisa de Acessibilidade para o teste."); exit(2) }

let p = Process()
p.executableURL = URL(fileURLWithPath: "\(appPath)/Contents/MacOS/Windows")
seedConfig()
p.arguments = ["--open-settings", "shortcuts"]
p.environment = ProcessInfo.processInfo.environment.merging(["WINDOWS_LOG": logPath, "WINDOWS_DEFAULTS": suite]) { $1 }
try! p.run()
runner.windowsApp = p

let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 480), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
w.title = "Teste do Windows"
let label = NSTextField(labelWithString: "Teste do Windows: não mexa no mouse nem no teclado por ~1 min.")
label.frame = NSRect(x: 24, y: 220, width: 680, height: 24)
w.contentView?.addSubview(label)
runner.window = w

Thread.detachNewThread {
    Thread.sleep(forTimeInterval: 1.5)
    runner.run()
    p.terminate()
    DispatchQueue.main.sync {
        w.orderOut(nil)
        runner.previousApp?.activate()
    }
    CGWarpMouseCursorPosition(runner.previousMouse)
    print(runner.failures == 0 ? "\nTudo certo: atalhos, tamanhos, menu, arrastos, gravador, novo tamanho e conflitos." : "\n\(runner.failures) falha(s).")
    try? FileManager.default.removeItem(atPath: logPath)
    UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    exit(runner.failures == 0 ? 0 : 1)
}
app.run()
