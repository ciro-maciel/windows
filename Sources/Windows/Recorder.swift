import SwiftUI
import AppKit
import Carbon.HIToolbox

/// The key caps of a shortcut; click to record a new one. While recording, the next key press
/// with ⌃, ⌥ or ⌘ becomes the shortcut; ⌫ alone removes it; esc cancels. Global shortcuts are
/// paused meanwhile, so pressing one that exists does not move a window.
struct KeyRecorder: View {
    /// The command being edited; nil for a size not saved yet.
    let command: Command?
    let shortcut: Shortcut?
    let identifier: String
    /// Called with the new shortcut (nil = removed). Own clashes never get here.
    let onChange: (Shortcut?) -> Void

    @State private var recording = false
    @State private var monitor: Any?
    @State private var message: String?
    @State private var hover = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button(action: toggle) {
                Group {
                    if recording {
                        Text(L("recorder.recording")).font(Zen.font(11, .bold)).foregroundStyle(Zen.gray9)
                            .padding(.horizontal, 10).frame(height: 24)
                            .background(Zen.gray0)
                            .overlay(Rectangle().strokeBorder(Zen.gray9, lineWidth: 1.5))
                    } else if let shortcut {
                        Caps(shortcut: shortcut)
                    } else {
                        Text(L("recorder.none")).font(Zen.font(11, .bold)).foregroundStyle(Zen.gray4)
                            .padding(.horizontal, 10).frame(height: 24)
                            .overlay(Rectangle().strokeBorder(Zen.gray3, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                    }
                }
                .padding(2)
                .background(hover && !recording ? Zen.gray2 : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
            .help(recording ? L("recorder.help.recording") : L("recorder.help.idle"))
            .accessibilityIdentifier(identifier)
            if let message {
                Text(message).font(Zen.font(11, .medium)).foregroundStyle(Zen.red7)
                    .accessibilityIdentifier("\(identifier).message")
                    .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 260, alignment: .trailing)
            } else if recording {
                // A combination another app holds as a global shortcut never reaches this window:
                // the only sign macOS gives is that nothing happens.
                Text(L("recorder.tip"))
                    .font(Zen.font(11, .medium)).foregroundStyle(Zen.gray5)
                    .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear { stop() }
    }

    private func toggle() { recording ? stop() : start() }

    private func start() {
        message = nil
        recording = true
        HotKeys.shared.pause(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { handle(event) }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { HotKeys.shared.pause(false) }
        recording = false
    }

    private func handle(_ event: NSEvent) {
        let mods = event.modifierFlags.intersection(Shortcut.relevant)
        if Int(event.keyCode) == kVK_Escape && mods.isEmpty { stop(); return }
        if (Int(event.keyCode) == kVK_Delete || Int(event.keyCode) == kVK_ForwardDelete) && mods.isEmpty {
            stop()
            onChange(nil)
            return
        }
        let s = Shortcut(keyCode: UInt32(event.keyCode), modifiers: mods)
        guard s.isUsable else {
            message = L("recorder.needsModifier")
            return
        }
        stop()
        if let owner = Config.shared.owner(of: s, except: command) {
            message = L("recorder.taken", s.text, Config.shared.title(owner))
            return
        }
        onChange(s)
    }
}

/// The caps: Tabler icons for modifiers and special keys, the letter otherwise.
struct Caps: View {
    let shortcut: Shortcut
    var muted = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(shortcut.caps.enumerated()), id: \.offset) { _, cap in
                Group {
                    if cap.hasPrefix("icon:") {
                        Icon(name: String(cap.dropFirst(5)), size: 12, color: muted ? Zen.gray4 : Zen.gray7)
                    } else {
                        Text(cap).font(Zen.font(11, .bold)).foregroundStyle(muted ? Zen.gray4 : Zen.gray7)
                            .padding(.horizontal, cap.count > 1 ? 6 : 0)
                    }
                }
                .frame(minWidth: 22, minHeight: 22)
                .background(Zen.gray1)
                .zenBorder(Zen.gray3)
            }
        }
    }
}

/// Where a size sits on the screen, drawn small: the screen in gray.1, the window in ink.
struct LayoutThumb: View {
    let layout: CustomLayout
    var width: CGFloat = 36

    var body: some View {
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let height = (width * screen.height / screen.width).rounded()
        let f = layout.frame(in: screen)
        let sx = width / screen.width, sy = height / screen.height
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Zen.gray1)
            Rectangle().fill(Zen.gray9.opacity(0.18))
                .overlay(Rectangle().strokeBorder(Zen.gray9, lineWidth: width > 100 ? 2 : 1))
                .frame(width: max(2, f.width * sx), height: max(2, f.height * sy))
                .offset(x: (f.minX - screen.minX) * sx, y: (screen.maxY - f.maxY) * sy)
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipped()
        .zenBorder(Zen.gray3)
    }
}
