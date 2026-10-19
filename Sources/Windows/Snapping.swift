import AppKit

/// Drag a window to an edge and let go: left or right edge, half; top edge, the whole screen;
/// a corner, a quarter. While the cursor is in a zone, a footprint shows where it will land.
@MainActor
final class Snapping {
    static let shared = Snapping()

    /// 5 px edges, 20 px corners.
    nonisolated static let edge: CGFloat = 5
    nonisolated static let corner: CGFloat = 20

    private var monitors: [Any] = []
    private var window: AXWindow?
    private var start: CGRect?
    private var moving = false
    private var zone: WindowAction?
    private let footprint = Footprint()

    var enabled: Bool { monitors.isEmpty == false }

    func start(_ on: Bool) {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        guard on else { return }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { _ in
            MainActor.assumeIsolated { Snapping.shared.down() }
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: { _ in
            MainActor.assumeIsolated { Snapping.shared.dragged() }
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { _ in
            MainActor.assumeIsolated { Snapping.shared.up() }
        }) { monitors.append(m) }
    }

    /// The zone for a cursor position, or nil away from the edges. Pure, for the self test.
    nonisolated static func zone(for p: CGPoint, in f: CGRect) -> WindowAction? {
        let left = p.x <= f.minX + edge, right = p.x >= f.maxX - edge - 1
        let top = p.y >= f.maxY - edge - 1, bottom = p.y <= f.minY + edge
        let nearTop = p.y >= f.maxY - corner - 1, nearBottom = p.y <= f.minY + corner
        let nearLeft = p.x <= f.minX + corner, nearRight = p.x >= f.maxX - corner - 1
        if (left && nearTop) || (top && nearLeft) { return .topLeft }
        if (right && nearTop) || (top && nearRight) { return .topRight }
        if (left && nearBottom) || (bottom && nearLeft) { return .bottomLeft }
        if (right && nearBottom) || (bottom && nearRight) { return .bottomRight }
        if left { return .leftHalf }
        if right { return .rightHalf }
        if top { return .maximize }
        return nil
    }

    private func down() {
        reset()
        guard Mover.shared.trusted else { return }
        window = AXWindow.at(NSEvent.mouseLocation)
        start = window?.frame
    }

    private func dragged() {
        guard let window, let start else { return }
        if !moving {
            // Moving, not resizing nor selecting: the origin changed and the size did not.
            guard let now = window.frame, now.size == start.size, now.origin != start.origin else { return }
            moving = true
        }
        let p = NSEvent.mouseLocation
        guard let screen = Screens.screen(containing: p) else { return }
        let z = Self.zone(for: p, in: screen.frame)
        if z != zone {
            zone = z
            if let z, let target = z.frame(in: screen.visibleFrame, current: start) {
                footprint.show(target)
            } else {
                footprint.hide()
            }
        }
    }

    private func up() {
        footprint.hide()
        defer { reset() }
        guard moving, let window else { return }
        // The zone where the button went up: near the Dock the last drag event may not come.
        let p = NSEvent.mouseLocation
        let final = Screens.screen(containing: p).flatMap { Self.zone(for: p, in: $0.frame) }
        Mover.shared.note("drag up at \(p) zone \(final?.rawValue ?? "none")")
        guard let final else { return }
        // Let the app finish its own move first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            Mover.shared.run(final, on: window, source: "drag")
        }
    }

    private func reset() {
        window = nil; start = nil; moving = false; zone = nil
    }
}

/// The footprint: gray.9 at 20% with a 2 px gray.9 rule and a 1 px white one inside, so it
/// reads on light and dark wallpapers. Square, no shadow.
@MainActor
final class Footprint {
    private lazy var panel: NSPanel = {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(srgbRed: 0x11 / 255, green: 0x18 / 255, blue: 0x1C / 255, alpha: 0.2).cgColor
        v.layer?.borderColor = NSColor(srgbRed: 0x11 / 255, green: 0x18 / 255, blue: 0x1C / 255, alpha: 1).cgColor
        v.layer?.borderWidth = 2
        let inner = NSView()
        inner.wantsLayer = true
        inner.layer?.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
        inner.layer?.borderWidth = 1
        inner.autoresizingMask = [.width, .height]
        v.addSubview(inner)
        p.contentView = v
        return p
    }()

    func show(_ frame: CGRect) {
        panel.setFrame(frame, display: true)
        if let inner = panel.contentView?.subviews.first {
            inner.frame = panel.contentView!.bounds.insetBy(dx: 2, dy: 2)
        }
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil) }
}
