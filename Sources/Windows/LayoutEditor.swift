import SwiftUI
import AppKit

/// Creates or edits one size: name, width and height (share of the screen or points), where it
/// sits, on which screen, a shortcut. With a live preview.
/// A modal; deleting is a 3 s hold (the target is this one size, never ambiguous).
struct LayoutEditor: View {
    @State var draft: CustomLayout
    let isNew: Bool
    let close: () -> Void

    @State private var conflicts: [Conflict] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(isNew ? "Novo tamanho" : "Editar tamanho").font(Zen.font(16, .extraBold)).foregroundStyle(Zen.gray9)
                Spacer()
                Button(action: close) {
                    Icon(name: "x", size: 18, color: Zen.gray6).frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Fechar sem salvar (esc)")
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("layout.close")
            }
            .padding(.bottom, 20)

            HStack {
                Spacer()
                LayoutThumb(layout: draft, width: 220)
                Spacer()
            }
            .padding(.bottom, 24)

            field("Nome") {
                TextField("Ex.: Leitura", text: $draft.name)
                    .modifier(ZenField())
                    .accessibilityIdentifier("layout.name")
            }

            HStack(alignment: .top, spacing: 12) {
                field("Largura") {
                    TextField("", value: $draft.width, format: .number.precision(.fractionLength(0...1)))
                        .modifier(ZenField()).accessibilityIdentifier("layout.width")
                }
                field("Altura") {
                    TextField("", value: $draft.height, format: .number.precision(.fractionLength(0...1)))
                        .modifier(ZenField()).accessibilityIdentifier("layout.height")
                }
                field("Medida") {
                    Segmented(options: [(CustomLayout.Unit.percent, "% da tela"), (.points, "Pontos")], selection: unitBinding)
                }
            }
            if let sizeProblem {
                Text(sizeProblem).font(Zen.font(11, .medium)).foregroundStyle(Zen.red7).padding(.top, -10).padding(.bottom, 14)
            }

            HStack(alignment: .top, spacing: 24) {
                field("Posição") {
                    HStack(alignment: .center, spacing: 12) {
                        AnchorGrid(selection: $draft.anchor)
                        Text(draft.anchor.title).font(Zen.font(13, .medium)).foregroundStyle(Zen.gray7)
                    }
                }
                field("Tela") {
                    Segmented(options: CustomLayout.Display.allCases.map { ($0, $0.title) }, selection: $draft.display)
                }
            }

            field("Atalho") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        KeyRecorder(command: .layout(draft.id), shortcut: draft.shortcut, identifier: "layout.shortcut") { s in
                            draft.shortcut = s
                            Task { await check() }
                        }
                        Spacer()
                    }
                    ForEach(conflicts.filter { !$0.blocks }, id: \.self) { c in
                        Text(c.text).font(Zen.font(11, .medium)).foregroundStyle(Zen.red7).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Rectangle().fill(Zen.gray2).frame(height: 1).padding(.top, 4).padding(.bottom, 20)
            HStack {
                if !isNew {
                    HoldButton(title: "Excluir") {
                        Config.shared.delete(draft.id)
                        close()
                    }
                    .accessibilityIdentifier("layout.delete")
                }
                Spacer()
                Button(isNew ? "Criar tamanho" : "Salvar") {
                    draft.name = draft.name.trimmingCharacters(in: .whitespaces)
                    Config.shared.save(draft)
                    close()
                }
                .buttonStyle(ZenButton())
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.45)
                .accessibilityIdentifier("layout.save")
            }
        }
        .padding(28)
        .frame(width: 560)
        .background(Zen.gray0)
        .task { await check() }
        // Opens with nothing focused: no name selected in the system's blue before a click.
        .onAppear { DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) } }
    }

    /// Switching the unit converts the numbers, so the preview does not jump.
    private var unitBinding: Binding<CustomLayout.Unit> {
        Binding(get: { draft.unit }, set: { unit in
            guard unit != draft.unit else { return }
            let screen = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1600, height: 1000)
            if unit == .points {
                draft.width = (screen.width * draft.width / 100).rounded()
                draft.height = (screen.height * draft.height / 100).rounded()
            } else {
                draft.width = min(100, (draft.width / screen.width * 1000).rounded() / 10)
                draft.height = min(100, (draft.height / screen.height * 1000).rounded() / 10)
            }
            draft.unit = unit
        })
    }

    private var sizeProblem: String? {
        switch draft.unit {
        case .percent:
            return (5...100).contains(draft.width) && (5...100).contains(draft.height) ? nil : "Largura e altura entre 5% e 100% da tela."
        case .points:
            return (100...10000).contains(draft.width) && (100...10000).contains(draft.height) ? nil : "Largura e altura entre 100 e 10.000 pontos."
        }
    }

    private var canSave: Bool { !draft.name.trimmingCharacters(in: .whitespaces).isEmpty && sizeProblem == nil }

    private func check() async {
        conflicts = draft.shortcut == nil ? [] : await Conflicts.check(draft.shortcut!, for: .layout(draft.id))
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).zenLabel(10, color: Zen.gray5)
            content()
        }
        .padding(.bottom, 18)
    }
}

/// Text input of the panel theme: 36 high, 13 px, gray.3 rule, radius 0.
struct ZenField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(Zen.font(13, .medium))
            .foregroundStyle(Zen.gray9)
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(Zen.gray0)
            .zenBorder(Zen.gray3)
    }
}

/// Segmented control, 36 high to sit beside the inputs: the chosen one in ink.
struct Segmented<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, option in
                Button { selection = option.0 } label: {
                    Text(option.1)
                        .font(Zen.font(12, selection == option.0 ? .extraBold : .medium))
                        .foregroundStyle(selection == option.0 ? .white : Zen.gray7)
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(selection == option.0 ? Zen.gray9 : Zen.gray0)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if i < options.count - 1 { Rectangle().fill(Zen.gray3).frame(width: 1, height: 36) }
            }
        }
        .zenBorder(Zen.gray3)
    }
}

/// The nine places, as a 3 × 3 grid of squares; the chosen one in ink.
struct AnchorGrid: View {
    @Binding var selection: CustomLayout.Anchor

    var body: some View {
        let all = CustomLayout.Anchor.allCases
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { col in
                        let a = all[row * 3 + col]
                        Button { selection = a } label: {
                            Rectangle().fill(selection == a ? Zen.gray9 : Zen.gray1)
                                .frame(width: 18, height: 12)
                                .overlay(Rectangle().strokeBorder(selection == a ? Zen.gray9 : Zen.gray3, lineWidth: 1))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(a.title)
                        .accessibilityIdentifier("layout.anchor.\(a.rawValue)")
                    }
                }
            }
        }
    }
}

/// Nothing removes in one click. Hold for 3 s; letting go cancels. The countdown
/// is drawn per frame by a TimelineView (a Timer does not fire while the mouse is down).
struct HoldButton: View {
    let title: String
    var duration: Double = 3
    let action: () -> Void

    @State private var pressedAt: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: pressedAt == nil)) { context in
            let progress = pressedAt.map { min(1, context.date.timeIntervalSince($0) / duration) } ?? 0
            let left = max(1, Int(ceil(duration * (1 - progress))))
            HStack(spacing: 8) {
                Icon(name: "trash", size: 14, color: Zen.red7)
                Text(pressedAt == nil ? title : "Segure… \(left)")
            }
            .font(Zen.font(11, .extraBold)).tracking(1).textCase(.uppercase)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .foregroundStyle(Zen.red7)
            .background(Zen.gray0)
            .overlay(alignment: .bottomLeading) {
                GeometryReader { geo in
                    Rectangle().fill(Zen.red7).frame(width: geo.size.width * progress, height: 3)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .overlay(Rectangle().strokeBorder(Zen.red7, lineWidth: 1))
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: duration, maximumDistance: 60) {
            pressedAt = nil
            action()
        } onPressingChanged: { pressing in
            pressedAt = pressing ? Date() : nil
        }
        .help("Segure por \(Int(duration)) segundos para excluir. Solte para cancelar.")
    }
}
