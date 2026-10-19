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

    /// "80% × 80%, em cima" for the list.
    var summary: String {
        let size = unit == .percent
            ? "\(Self.number(width))% × \(Self.number(height))%"
            : "\(Int(width)) × \(Int(height)) pt"
        var parts = [size, anchor.title.lowercased()]
        if display != .current { parts.append(display.title.lowercased()) }
        return parts.joined(separator: ", ")
    }

    static func number(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
    }

    /// The three sizes the app ships with; the person can edit or delete them.
    static let defaults: [CustomLayout] = [
        CustomLayout(id: UUID(uuidString: "6F0A1C2E-0001-4000-8000-000000000097")!, name: "Quase inteira",
                     width: 97.1, height: 97, anchor: .center, shortcut: .opt(kVK_ANSI_F)),
        CustomLayout(id: UUID(uuidString: "6F0A1C2E-0002-4000-8000-000000000080")!, name: "Grande",
                     width: 80, height: 80, anchor: .top, shortcut: .opt(kVK_ANSI_D)),
        CustomLayout(id: UUID(uuidString: "6F0A1C2E-0003-4000-8000-000000000060")!, name: "Média",
                     width: 60, height: 60, anchor: .top, shortcut: .opt(kVK_ANSI_S)),
    ]
}

extension CustomLayout.Anchor {
    var title: String {
        switch self {
        case .topLeft: return "Em cima à esquerda"
        case .top: return "Em cima"
        case .topRight: return "Em cima à direita"
        case .left: return "À esquerda"
        case .center: return "No centro"
        case .right: return "À direita"
        case .bottomLeft: return "Embaixo à esquerda"
        case .bottom: return "Embaixo"
        case .bottomRight: return "Embaixo à direita"
        }
    }
}

extension CustomLayout.Display {
    var title: String {
        switch self {
        case .current: return "Tela da janela"
        case .main: return "Tela principal"
        case .next: return "Próxima tela"
        }
    }
}
