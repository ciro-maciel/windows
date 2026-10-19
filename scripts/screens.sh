#!/bin/bash
# Captures the real settings window, one PNG per pane, for visual review (window buttons included).
# The app runs in the given language (en or pt-BR; default: the Mac's) on a settings suite of
# its own, so the captures show the sizes that ship, named in that language.
#   scripts/screens.sh [dir] [en|pt-BR]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/.build/screens}"
LANG_ARGS=(); if [ -n "${2:-}" ]; then LANG_ARGS=(-AppleLanguages "($2)"); fi
export WINDOWS_DEFAULTS="click.ciromaciel.windows.screens"
mkdir -p "$OUT" "$ROOT/.build"
SDK="$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.*.sdk 2>/dev/null | sort -V | tail -1 || true)"
cat > "$ROOT/.build/winid.swift" <<'SWIFT'
import CoreGraphics
let pid = Int(CommandLine.arguments[1])!
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowOwnerPID as String] as? Int) == pid && (w[kCGWindowLayer as String] as? Int) == 0 {
    print(w[kCGWindowNumber as String]!); break
}
SWIFT
swiftc ${SDK:+-sdk "$SDK"} "$ROOT/.build/winid.swift" -o "$ROOT/.build/winid"
for PANE in shortcuts drag general editor-new editor-large; do
    case "$PANE" in
        editor-new) ARGS=(--open-editor new) ;;
        # The shipped "Large" size, by id: its name depends on the language.
        editor-large) ARGS=(--open-editor 6F0A1C2E-0002-4000-8000-000000000080) ;;
        *) ARGS=(--open-settings "$PANE") ;;
    esac
    "$ROOT/dist/Windows.app/Contents/MacOS/Windows" "${ARGS[@]}" ${LANG_ARGS[@]+"${LANG_ARGS[@]}"} &
    PID=$!
    sleep 2
    screencapture -x -o -l "$("$ROOT/.build/winid" "$PID")" "$OUT/$PANE.png"
    kill "$PID"
done
echo "$OUT"
