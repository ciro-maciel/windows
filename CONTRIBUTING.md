# Contributing

Thanks for helping. Windows sits in the menu bar of people's Macs and moves their windows, so the bar is "fast, quiet and never surprising".

## Code

```bash
scripts/build.sh
dist/Windows.app/Contents/MacOS/Windows --selftest
scripts/e2e.sh
```

The self test and the end-to-end test must pass on your Mac before you open the pull request. Run `scripts/e2e.sh` from a terminal that has Accessibility; it takes over the mouse and keyboard for about 40 seconds and uses its own settings suite. If your change touches the Settings window, attach a capture from `scripts/screens.sh` (`scripts/screens.sh .build/screens en`, and `pt-BR` for the other language).

House rules:

- Swift, AppKit and SwiftUI only, built by `swiftc`. No Xcode project, no package manager, no dependencies.
- No network code. Windows never talks to the internet, and that is a promise in the README.
- Small on purpose. A new feature has to be something people use every day; the README lists what is left out and why.
- Every user-facing string exists in English and Brazilian Portuguese (`Resources/en.lproj` and `Resources/pt-BR.lproj`, read through `L("key")`); a change that adds text adds both.
- Global shortcuts go through Carbon's `RegisterEventHotKey`. Moving windows goes through the Accessibility API, and nothing else needs a permission.

## Reporting a bug

Say which macOS version, which Mac, how many displays, which app's window misbehaved and what you expected. Some apps answer Accessibility differently; the app name matters.

For anything that could expose someone's data, read [SECURITY.md](SECURITY.md) first.
