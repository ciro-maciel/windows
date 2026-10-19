#!/bin/bash
# End-to-end test: real shortcuts, real mouse drags and the menu bar menu against dist/Windows.app.
# Takes the keyboard and the mouse for about 30 seconds. Another window manager would answer the
# same shortcuts, so a running Rectangle or Rectangle Pro is closed for the test and opened again after.
#   scripts/e2e.sh [screenshot dir]            (WINDOWS_APP=/Applications/Windows.app to test the installed copy)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.*.sdk 2>/dev/null | sort -V | tail -1 || true)"
mkdir -p "$ROOT/.build"
swiftc ${SDK:+-sdk "$SDK"} -target arm64-apple-macosx14.0 -swift-version 5 "$ROOT/scripts/e2e.swift" -o "$ROOT/.build/e2e"

# Whoever already holds the shortcuts would answer them: another window manager, or the
# installed Windows itself. Each is closed for the test and opened again at the end.
REOPEN=()
for ID in com.knollsoft.Hookshot com.knollsoft.Rectangle click.ciromaciel.windows; do
    if osascript -e "application id \"$ID\" is running" 2>/dev/null | grep -q true; then
        osascript -e "tell application id \"$ID\" to quit" >/dev/null 2>&1 || true
        REOPEN+=("$ID")
    fi
done
reopen() { for ID in "${REOPEN[@]+"${REOPEN[@]}"}"; do open -b "$ID"; done; }
trap reopen EXIT
sleep 1
"$ROOT/.build/e2e" "${WINDOWS_APP:-$ROOT/dist/Windows.app}" "${1:-$ROOT/.build}"
