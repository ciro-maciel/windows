#!/bin/bash
# Captures the real settings window, one PNG per pane, for visual review (window buttons included).
#   scripts/screens.sh [dir]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/.build/screens}"
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
for PANE in shortcuts drag general editor-new editor-grande; do
    case "$PANE" in
        editor-new) ARGS=(--open-editor new) ;;
        editor-grande) ARGS=(--open-editor Grande) ;;
        *) ARGS=(--open-settings "$PANE") ;;
    esac
    "$ROOT/dist/Windows.app/Contents/MacOS/Windows" "${ARGS[@]}" &
    PID=$!
    sleep 2
    screencapture -x -o -l "$("$ROOT/.build/winid" "$PID")" "$OUT/$PANE.png"
    kill "$PID"
done
echo "$OUT"
