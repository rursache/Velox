# Velox

Ultra-fast Spotlight-style launcher for macOS

## Why Swift

For a Spotlight replacement that must look and feel native, **pure Swift + AppKit** is the right stack

- App search over a few hundred apps is already sub-millisecond in Swift once indexed in memory
- Spotlight chrome (`NSPanel`, `NSVisualEffectView`, keyboard focus, spaces) is AppKit-native
- Rust would help for huge file indexes later, not for apps + calc + currency
- Objective-C adds no speed win over modern Swift here

## Features

- Instant app search across `/Applications`, `~/Applications`, `/System/Applications`, cryptex system apps, and `/Applications` on attached external disks
- Fuzzy ranking (exact, prefix, word-boundary acronyms like `gc` → Google Chrome, subsequence)
- Spotlight-like floating panel, collapsed until you type, grows downward from a pinned top edge
- Drag the bar to park it; it snaps back to the factory Spotlight slot when you get close
- Calculator (`12*8+4`, `2^10`, percentages)
- Currency conversion (`100 USD to EUR`) via Frankfurter with on-disk cache, refreshed on launch and every hour
- Settings: max app results (default **8**), include extra Apple system apps (**off** by default), show paths, math and currency conversion (**on** by default)
- Remappable global hotkey (default **⌥Space**)
- Bar themes: Glass, Clear, Midnight, Snow, Olive, Harbor, Orchid, Parchment, plus a separate result highlight and live corner radius
- Show on the screen with the mouse (default), the active window, or **Show on all screens**
- Menu bar: left-click opens Settings (the icon stays a magnifying glass), right-click for Show / Settings / Rebuild index / Quit
- Search-field magnifying glass becomes a Settings button on hover
- Opening Settings shows a live, display-only preview of the bar so theme and radius apply without a restart
- A second launch shows the already-running instance instead of starting another process

## Build & run

Open `Velox.xcodeproj` in Xcode and run the **Velox** scheme (⌘R)

Requires macOS 15. Signing is already set to the RanduSoft SRL team on the project

To pass launch args (show the panel, prefill a query), use **Product → Scheme → Edit Scheme → Run → Arguments**

## Tests

In Xcode: **Product → Test**, or:

```bash
xcodebuild test -project Velox.xcodeproj -scheme Velox -destination 'platform=macOS'
```

## Usage

| Action | How |
|--------|-----|
| Open | Remappable hotkey (default ⌥Space) or menu bar → Show Velox |
| Search apps | Type name or initials |
| Calculate | Type an expression, ⏎ copies result |
| Convert currency | `100 usd to eur`, ⏎ copies result |
| Launch | ↑/↓ then ⏎, or click |
| Move | Drag the bar |
| Close | Esc |
| Settings | Hover the search icon, left-click the menu bar, or ⌘, |

To use **⌘Space**, disable Spotlight’s shortcut in System Settings → Keyboard → Keyboard Shortcuts → Spotlight, then click the keys in Velox Settings and press ⌘Space. Option+Space stays the default so both can coexist.

The GitHub build is notarization-ready (Hardened Runtime, team-signed) and is not App Sandboxed, so it can index the real `~/Applications` and `/Applications` on attached disks. A Mac App Store build would have to drop those roots or ask the user to pick folders.

## License

MIT. See `LICENSE`.
