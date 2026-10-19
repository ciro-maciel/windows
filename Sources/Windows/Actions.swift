import AppKit
import Carbon.HIToolbox

/// The fixed places a window can go. The sizes the person makes (CustomLayout) live in
/// Layouts.swift; the corners are reached by dragging only.
enum WindowAction: String, CaseIterable, Codable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case maximize, center, restore, nextDisplay
    // Reached by dragging to a corner only.
    case topLeft, topRight, bottomLeft, bottomRight

    static let keyboard: [WindowAction] = [
        .leftHalf, .rightHalf, .topHalf, .bottomHalf, .maximize, .center, .restore, .nextDisplay,
    ]

    var title: String { L("action.\(rawValue)") }

    /// What the action means, in one line for the settings window.
    var note: String {
        switch self {
        case .maximize, .center, .nextDisplay: return L("action.\(rawValue).note")
        default: return ""
        }
    }

    var icon: String {
        switch self {
        case .leftHalf, .topLeft, .bottomLeft: return "layout-sidebar"
        case .rightHalf, .topRight, .bottomRight: return "layout-sidebar-right"
        case .topHalf: return "layout-navbar"
        case .bottomHalf: return "layout-bottombar"
        case .maximize: return "maximize"
        case .center: return "focus-centered"
        case .restore: return "arrow-back-up"
        case .nextDisplay: return "device-desktop"
        }
    }

    /// The shortcut before the person changes it (Rectangle's defaults).
    var defaultShortcut: Shortcut? {
        switch self {
        case .leftHalf: return .ctrlOpt(kVK_LeftArrow)
        case .rightHalf: return .ctrlOpt(kVK_RightArrow)
        case .topHalf: return .ctrlOpt(kVK_UpArrow)
        case .bottomHalf: return .ctrlOpt(kVK_DownArrow)
        case .maximize: return .ctrlOpt(kVK_Return)
        case .center: return .ctrlOpt(kVK_ANSI_C)
        case .restore: return .ctrlOpt(kVK_Delete)
        case .nextDisplay: return Shortcut(keyCode: UInt32(kVK_RightArrow), modifiers: [.control, .option, .command])
        default: return nil
        }
    }

    /// Where the window goes, in Cocoa coordinates (origin bottom left). `visible` is the
    /// screen minus menu bar and Dock; `current` is the window now. Nil for actions that do not
    /// depend on one screen (restore, next display).
    func frame(in visible: CGRect, current: CGRect) -> CGRect? {
        let v = visible
        // Left and bottom take the floor, right and top the rest: no pixel lost on odd sizes.
        let halfW = (v.width / 2).rounded(.down), halfH = (v.height / 2).rounded(.down)
        let restW = v.width - halfW, restH = v.height - halfH
        switch self {
        case .leftHalf: return CGRect(x: v.minX, y: v.minY, width: halfW, height: v.height)
        case .rightHalf: return CGRect(x: v.minX + halfW, y: v.minY, width: restW, height: v.height)
        case .topHalf: return CGRect(x: v.minX, y: v.minY + halfH, width: v.width, height: restH)
        case .bottomHalf: return CGRect(x: v.minX, y: v.minY, width: v.width, height: halfH)
        case .topLeft: return CGRect(x: v.minX, y: v.minY + halfH, width: halfW, height: restH)
        case .topRight: return CGRect(x: v.minX + halfW, y: v.minY + halfH, width: restW, height: restH)
        case .bottomLeft: return CGRect(x: v.minX, y: v.minY, width: halfW, height: halfH)
        case .bottomRight: return CGRect(x: v.minX + halfW, y: v.minY, width: restW, height: halfH)
        case .maximize: return v
        case .center:
            let w = min(current.width, v.width), h = min(current.height, v.height)
            return CGRect(x: (v.midX - w / 2).rounded(), y: (v.midY - h / 2).rounded(), width: w, height: h)
        case .restore, .nextDisplay: return nil
        }
    }
}

/// Anything a shortcut or a menu item can run: a fixed action or one of the person's sizes.
enum Command: Hashable {
    case action(WindowAction)
    case layout(UUID)

    /// Stable key for the settings, the hot key table and the log.
    var key: String {
        switch self {
        case .action(let a): return "action:\(a.rawValue)"
        case .layout(let id): return "layout:\(id.uuidString)"
        }
    }
}
