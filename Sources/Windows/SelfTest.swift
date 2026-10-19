import AppKit

/// `Windows --selftest`: the geometry and the drag zones, on made-up screens. No window moves.
enum SelfTest {
    @MainActor
    static func run() -> Int32 {
        var failures = 0
        func check(_ name: String, _ got: CGRect?, _ want: CGRect) {
            let ok = got.map { $0.integral == want.integral } ?? false
            if !ok { failures += 1 }
            print("\(ok ? "ok  " : "FAIL") \(name)\(ok ? "" : ": got \(String(describing: got)), want \(want)")")
        }
        func check(_ name: String, _ got: WindowAction?, _ want: WindowAction?) {
            let ok = got == want
            if !ok { failures += 1 }
            print("\(ok ? "ok  " : "FAIL") \(name)\(ok ? "" : ": got \(String(describing: got)), want \(String(describing: want))")")
        }

        // A 2560 × 1440 screen with a 25 pt menu bar and a 70 pt Dock below.
        let v = CGRect(x: 0, y: 70, width: 2560, height: 1345)
        let win = CGRect(x: 300, y: 300, width: 800, height: 600)
        check("metade esquerda", WindowAction.leftHalf.frame(in: v, current: win), CGRect(x: 0, y: 70, width: 1280, height: 1345))
        check("metade direita", WindowAction.rightHalf.frame(in: v, current: win), CGRect(x: 1280, y: 70, width: 1280, height: 1345))
        check("metade de cima", WindowAction.topHalf.frame(in: v, current: win), CGRect(x: 0, y: 742, width: 2560, height: 673))
        check("metade de baixo", WindowAction.bottomHalf.frame(in: v, current: win), CGRect(x: 0, y: 70, width: 2560, height: 672))
        check("tela inteira", WindowAction.maximize.frame(in: v, current: win), v)
        let d = CustomLayout.defaults
        check("tamanho: quase inteira 97%", d[0].frame(in: v), CGRect(x: 37, y: 90, width: 2486, height: 1305))
        check("tamanho: grande 80% em cima", d[1].frame(in: v), CGRect(x: 256, y: 339, width: 2048, height: 1076))
        check("tamanho: média 60% em cima", d[2].frame(in: v), CGRect(x: 512, y: 608, width: 1536, height: 807))
        var px = CustomLayout(name: "pontos", width: 1200, height: 800, unit: .points, anchor: .bottomRight)
        check("tamanho: 1200 × 800 pt embaixo à direita", px.frame(in: v), CGRect(x: 1360, y: 70, width: 1200, height: 800))
        px.width = 5000
        check("tamanho: maior que a tela fica na tela", px.frame(in: v), CGRect(x: 0, y: 70, width: 2560, height: 800))
        let left = CustomLayout(name: "esquerda", width: 30, height: 100, anchor: .left)
        check("tamanho: 30% à esquerda", left.frame(in: v), CGRect(x: 0, y: 70, width: 768, height: 1345))
        let corner = CustomLayout(name: "canto", width: 50, height: 50, anchor: .topRight)
        check("tamanho: 50% em cima à direita", corner.frame(in: v), CGRect(x: 1280, y: 742, width: 1280, height: 673))
        check("centralizar", WindowAction.center.frame(in: v, current: win), CGRect(x: 880, y: 443, width: 800, height: 600))
        check("canto de cima à esquerda", WindowAction.topLeft.frame(in: v, current: win), CGRect(x: 0, y: 742, width: 1280, height: 673))
        check("canto de baixo à direita", WindowAction.bottomRight.frame(in: v, current: win), CGRect(x: 1280, y: 70, width: 1280, height: 672))
        // Second screen to the left, with an odd width.
        let v2 = CGRect(x: -1921, y: 0, width: 1921, height: 1055)
        check("metade esquerda, tela 2", WindowAction.leftHalf.frame(in: v2, current: win), CGRect(x: -1921, y: 0, width: 960, height: 1055))
        check("metade direita, tela 2", WindowAction.rightHalf.frame(in: v2, current: win), CGRect(x: -961, y: 0, width: 961, height: 1055))

        let f = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        check("zona: borda esquerda", Snapping.zone(for: CGPoint(x: 0, y: 700), in: f), .leftHalf)
        check("zona: borda direita", Snapping.zone(for: CGPoint(x: 2559, y: 700), in: f), .rightHalf)
        check("zona: em cima", Snapping.zone(for: CGPoint(x: 1200, y: 1439), in: f), .maximize)
        check("zona: canto de cima à esquerda", Snapping.zone(for: CGPoint(x: 0, y: 1430), in: f), .topLeft)
        check("zona: canto de cima à direita", Snapping.zone(for: CGPoint(x: 2550, y: 1439), in: f), .topRight)
        check("zona: canto de baixo à esquerda", Snapping.zone(for: CGPoint(x: 0, y: 5), in: f), .bottomLeft)
        check("zona: embaixo, no meio, nada", Snapping.zone(for: CGPoint(x: 1200, y: 0), in: f), nil)
        check("zona: meio da tela, nada", Snapping.zone(for: CGPoint(x: 1200, y: 700), in: f), nil)
        check("zona: a 10 px da borda, nada", Snapping.zone(for: CGPoint(x: 10, y: 700), in: f), nil)

        // The shipped shortcuts: one per command, none repeated.
        let keys = WindowAction.keyboard.compactMap(\.defaultShortcut) + d.compactMap(\.shortcut)
        let unique = Set(keys).count == keys.count && keys.count == WindowAction.keyboard.count + d.count
        if !unique { failures += 1 }
        print("\(unique ? "ok  " : "FAIL") \(keys.count) atalhos de fábrica, nenhum repetido")

        // A shortcut survives the trip through the settings JSON.
        let s = Shortcut(keyCode: 38, modifiers: [.control, .option, .shift])
        let back = (try? JSONEncoder().encode(s)).flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }
        if back != s { failures += 1 }
        print("\(back == s ? "ok  " : "FAIL") atalho salvo e lido de volta (\(s.text))")
        let needs = !Shortcut(keyCode: 3, modifiers: [.shift]).isUsable && Shortcut(keyCode: 96, modifiers: []).isUsable
        if !needs { failures += 1 }
        print("\(needs ? "ok  " : "FAIL") letra só com ⇧ é recusada; F5 sozinha vale")

        print(failures == 0 ? "\nTudo certo." : "\n\(failures) falha(s).")
        return failures == 0 ? 0 : 1
    }
}
