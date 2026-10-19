import AppKit
import Carbon.HIToolbox

/// A size the person makes with "+":
/// width and height (share of the screen or points), where it sits, on which screen, a shortcut.
struct CustomLayout: Codable, Identifiable, Hashable {
    enum Unit: String, Codable, CaseIterable { case percent, points }
    /// The nine places on a 3 × 3 grid.
    enum Anchor: String, Codable, CaseIterable {
        case topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight
    }
    enum Display: String, Codable, CaseIterable { case current, main, next }

    var id = UUID()
    var name: String
    var width: Double
    var height: Double
    var unit: Unit = .percent
    var anchor: Anchor = .center
    var display: Display = .current
    var shortcut: Shortcut?

    /// The frame inside a screen's visible area (Cocoa coordinates), never bigger than it.
    func frame(in v: CGRect) -> CGRect {
        let w = min(v.width, (unit == .percent ? v.width * width / 100 : width).rounded())
        let h = min(v.height, (unit == .percent ? v.height * height / 100 : height).rounded())
        let x: CGFloat
        switch anchor {
        case .topLeft, .left, .bottomLeft: x = v.minX
        case .top, .center, .bottom: x = (v.midX - w / 2).rounded()
        case .topRight, .right, .bottomRight: x = v.maxX - w
        }
        let y: CGFloat
        switch anchor {
        case .topLeft, .top, .topRight: y = v.maxY - h
        case .left, .center, .right: y = (v.midY - h / 2).rounded()
        case .bottomLeft, .bottom, .bottomRight: y = v.minY
        }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// "80% × 80%, top" for the list.
    var summary: String {
        let size = unit == .percent
            ? "\(Self.number(width))% × \(Self.number(height))%"
            : "\(Int(width)) × \(Int(height)) pt"
        var parts = [size, anchor.title.lowercased()]
        if display != .current { parts.append(display.title.lowercased()) }
        return parts.joined(separator: ", ")
    }

    static func number(_ v: Double) -> String {
        // In the Mac's number format, as the editor's fields show it: 97.1 or 97,1.
        v.formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
    }

    /// The three sizes the app ships with, named in the app's language; the person can edit or delete them.
    /// Once saved, a name stays as it was written.
    static let defaults: [CustomLayout] = [
        CustomLayout(id: UUID(uuidString: "6F0A1C2E-0001-4000-8000-000000000097")!, name: L("layout.default.almostFull"),
                     width: 97.1, height: 97, anchor: .center, shortcut: .opt(kVK_ANSI_F)),
        CustomLayout(id: UUID(uuidString: "6F0A1C2E-0002-4000-8000-000000000080")!, name: L("layout.default.large"),
                     width: 80, height: 80, anchor: .top, shortcut: .opt(kVK_ANSI_D)),
        CustomLayout(id: UUID(uuidString: "6F0A1C2E-0003-4000-8000-000000000060")!, name: L("layout.default.medium"),
                     width: 60, height: 60, anchor: .top, shortcut: .opt(kVK_ANSI_S)),
    ]
}

extension CustomLayout.Anchor {
    var title: String {
        L("anchor.\(rawValue)")
    }
}

extension CustomLayout.Display {
    var title: String {
        L("display.\(rawValue)")
    }
}
