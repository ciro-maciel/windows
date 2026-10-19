# Notes for coding agents

Windows is a native macOS menu bar app in Swift, AppKit and SwiftUI that moves other apps' windows by shortcut and by drag. It is built by `scripts/build.sh` with `swiftc`, so there is no Xcode project and no Swift package.

## Layout

| Path | What it is |
| --- | --- |
| `Sources/Windows/App.swift` | Entry point, menu bar item and menu, command-line probes (`--selftest`, `--conflicts`) |
| `Sources/Windows/Actions.swift` | The fixed positions and their default shortcuts; the geometry of each |
| `Sources/Windows/Layouts.swift` | The person's own sizes and the three that ship |
| `Sources/Windows/WindowMover.swift` | The Accessibility side: the focused window, coordinates, moving, restore, next display |
| `Sources/Windows/Snapping.swift` | Drag to the edge: zones, the outline, the global mouse monitors |
| `Sources/Windows/HotKeys.swift`, `Shortcut.swift`, `Recorder.swift` | Carbon hot keys, the shortcut model, the shortcut recorder |
| `Sources/Windows/Conflicts.swift` | Who else uses a shortcut: macOS, open apps' menus, other window managers |
| `Sources/Windows/Config.swift` | What the person set, as JSON in user defaults (`WINDOWS_DEFAULTS` picks another suite) |
| `Sources/Windows/SettingsView.swift`, `LayoutEditor.swift`, `MacShell.swift`, `Theme.swift` | The Settings window; `Theme.swift` holds the design tokens |
| `Sources/Windows/SelfTest.swift` | `--selftest`: geometry, zones and shortcuts on made-up screens |
| `scripts/` | Build, local install, signing identity, end-to-end test, screenshots, asset regeneration |
| `scripts/release/` | Packing the `.dmg` and publishing it; used by `.github/workflows/release.yml` |

## Before you say it works

```bash
scripts/build.sh
dist/Windows.app/Contents/MacOS/Windows --selftest
scripts/e2e.sh
```

`scripts/e2e.sh` needs a terminal with Accessibility and takes over the mouse and keyboard for about 40 seconds. Ask the person before you run it.

## Rules that must hold

- No network code, anywhere: no `URLSession`, no sockets.
- Accessibility is the only permission. Read a window's position and size, never its contents.
- Coordinates: Accessibility uses a top-left origin, everything else is Cocoa (bottom left). The conversion lives in `WindowMover.swift` only.
- The bundle identifier (`click.ciromaciel.windows`) never changes: macOS ties Accessibility to it and to the signature.
- The interface text is in Portuguese; code, comments and file names are in English.
