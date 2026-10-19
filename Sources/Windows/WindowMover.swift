import AppKit
import ApplicationServices

/// A window of another app, through the Accessibility API. AX speaks in global coordinates with
/// the origin at the top left of the main screen; everything else here is Cocoa (bottom left),
/// so the conversion lives in this file only.
struct AXWindow {
    let element: AXUIElement
    let pid: pid_t

    static func focused() -> AXWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value) == .success,
           let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
            return AXWindow(element: value as! AXUIElement, pid: app.processIdentifier)
        }
        // Some apps answer only for the main window.
        if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &value) == .success,
           let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
            return AXWindow(element: value as! AXUIElement, pid: app.processIdentifier)
        }
        return nil
    }

    /// The window under a point (Cocoa coordinates), if the point is on one.
    static func at(_ point: CGPoint) -> AXWindow? {
        let ax = Screens.toAX(point)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(ax.x), Float(ax.y), &hit) == .success,
              var element = hit else { return nil }
        // Walk up until the window.
        for _ in 0..<40 {
            if role(of: element) == kAXWindowRole as String {
                var pid: pid_t = 0
                AXUIElementGetPid(element, &pid)
                return AXWindow(element: element, pid: pid)
            }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent) == .success,
                  let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
            element = parent as! AXUIElement
        }
        return nil
    }

    private static func role(of e: AXUIElement) -> String? {
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(e, kAXRoleAttribute as CFString, &v)
        return v as? String
    }

    /// The frame in Cocoa coordinates.
    var frame: CGRect? {
        var pos: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &pos) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let pos, let size else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        AXValueGetValue(pos as! AXValue, .cgPoint, &p)
        AXValueGetValue(size as! AXValue, .cgSize, &s)
        return Screens.fromAX(CGRect(origin: p, size: s))
    }

    /// Size, position, size again: the second size lands when the first was clamped by the old
    /// screen. Apps with "enhanced user interface" on (set by VoiceOver-aware apps) animate every
    /// change and drift; it goes off for the move and back on after.
    func setFrame(_ cocoa: CGRect) {
        let ax = Screens.toAX(cocoa)
        let app = AXUIElementCreateApplication(pid)
        var enhanced: CFTypeRef?
        let hadEnhanced = AXUIElementCopyAttributeValue(app, "AXEnhancedUserInterface" as CFString, &enhanced) == .success
            && (enhanced as? Bool) == true
        if hadEnhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }
        var size = ax.size, origin = ax.origin
        let sizeValue = AXValueCreate(.cgSize, &size)!, posValue = AXValueCreate(.cgPoint, &origin)!
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, posValue)
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        if hadEnhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) }
    }
}

enum Screens {
    /// Height of the main screen: the pivot between AX (top left) and Cocoa (bottom left).
    static var pivot: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }

    static func toAX(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: pivot - p.y) }
    static func toAX(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: pivot - r.maxY, width: r.width, height: r.height) }
    static func fromAX(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: pivot - r.maxY, width: r.width, height: r.height) }

    /// The screen that holds most of the window.
    static func screen(for frame: CGRect) -> NSScreen? {
        NSScreen.screens.max { area($0.frame.intersection(frame)) < area($1.frame.intersection(frame)) }
            .flatMap { area($0.frame.intersection(frame)) > 0 ? $0 : nil } ?? NSScreen.main
    }

    /// Edges included: NSMouseInRect leaves the bottom row out, and the cursor sits there in a
    /// bottom corner.
    static func screen(containing p: CGPoint) -> NSScreen? {
        NSScreen.screens.first { p.x >= $0.frame.minX && p.x <= $0.frame.maxX && p.y >= $0.frame.minY && p.y <= $0.frame.maxY }
    }

    private static func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }
}

/// Runs an action on a window and remembers where it was, for "restore".
@MainActor
final class Mover {
    static let shared = Mover()

    private struct Memory { var before: CGRect; var placed: CGRect }
    private var memory: [Int: Memory] = [:]   // CFHash of the AX element
    /// Last action handled, for the end-to-end test (WINDOWS_LOG).
    private let log = ProcessInfo.processInfo.environment["WINDOWS_LOG"]

    var trusted: Bool { AXIsProcessTrusted() }

    func run(_ action: WindowAction, on target: AXWindow? = nil, source: String = "key") {
        run(.action(action), on: target, source: source)
    }

    func run(_ command: Command, on target: AXWindow? = nil, source: String = "key") {
        let name: String
        switch command {
        case .action(let a): name = a.rawValue
        case .layout(let id): name = "layout:\(Config.shared.layout(id)?.name ?? id.uuidString)"
        }
        guard trusted, let window = target ?? AXWindow.focused(), let current = window.frame else {
            record("\(source) \(name) skipped")
            return
        }
        let key = Int(CFHash(window.element))
        let isRestore = command == .action(.restore)
        let destination: CGRect?
        switch command {
        case .action(.restore):
            destination = memory[key]?.before
        case .action(.nextDisplay):
            destination = nextDisplayFrame(for: current)
        case .action(let action):
            let screen = Screens.screen(for: current) ?? NSScreen.main
            destination = screen.flatMap { action.frame(in: $0.visibleFrame, current: current) }
        case .layout(let id):
            destination = Config.shared.layout(id).flatMap { layout in
                screen(for: layout.display, from: current).map { layout.frame(in: $0.visibleFrame) }
            }
        }
        guard let destination else {
            record("\(source) \(name) nothing")
            return
        }
        if isRestore {
            memory[key] = nil
        } else {
            // A window the person moved by hand since we placed it starts a new memory.
            let m = memory[key]
            let before = (m != nil && Self.close(m!.placed, current)) ? m!.before : current
            memory[key] = Memory(before: before, placed: destination)
        }
        window.setFrame(destination)
        // Read back what the app accepted (minimum sizes, terminals rounding to cells).
        if !isRestore, let landed = window.frame { memory[key]?.placed = landed }
        record("\(source) \(name) \(Int(destination.minX)),\(Int(destination.minY)),\(Int(destination.width)),\(Int(destination.height))")
    }

    /// The screen a custom size goes to.
    private func screen(for display: CustomLayout.Display, from current: CGRect) -> NSScreen? {
        let here = Screens.screen(for: current) ?? NSScreen.main
        switch display {
        case .current: return here
        case .main: return NSScreen.screens.first
        case .next:
            let all = NSScreen.screens
            guard let here, let i = all.firstIndex(of: here) else { return here }
            return all[(i + 1) % all.count]
        }
    }

    /// Same relative place and size on the next screen.
    private func nextDisplayFrame(for current: CGRect) -> CGRect? {
        let screens = NSScreen.screens
        guard screens.count > 1, let here = Screens.screen(for: current),
              let i = screens.firstIndex(of: here) else { return nil }
        let a = here.visibleFrame, b = screens[(i + 1) % screens.count].visibleFrame
        let sx = b.width / a.width, sy = b.height / a.height
        return CGRect(x: b.minX + (current.minX - a.minX) * sx, y: b.minY + (current.minY - a.minY) * sy,
                      width: min(current.width * sx, b.width), height: min(current.height * sy, b.height))
    }

    private static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 3 && abs(a.minY - b.minY) < 3 && abs(a.width - b.width) < 3 && abs(a.height - b.height) < 3
    }

    func note(_ line: String) { record(line) }

    private func record(_ line: String) {
        guard let log else { return }
        if let h = FileHandle(forWritingAtPath: log) {
            h.seekToEndOfFile(); h.write((line + "\n").data(using: .utf8)!); h.closeFile()
        } else {
            try? (line + "\n").write(toFile: log, atomically: true, encoding: .utf8)
        }
    }
}
