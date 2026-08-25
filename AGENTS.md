# Velox

Light, fast, native Spotlight replacement for macOS

## Goal

Distill the best of Raycast and native Spotlight into a tiny custom launcher

Keep Spotlight’s feel: floating panel, collapsed until you type, short result list, keyboard-first, activate-if-already-running

Steal from Raycast only when it makes the core features faster or more correct (ranking, calculator completeness, cheap currency parse). Do not pick up Raycast’s surface area

## v1 features

These three must be excellent and instant:

- App search (name, initials, fuzzy)
- Math
- Currency conversion

Everything else waits. No file search, clipboard history, snippets, extensions, or AI for v1

## Constraints

- Pure Swift + AppKit for chrome (`NSPanel`, blur, focus, spaces). SwiftUI is fine for the result list
- In-memory app index. Icons load only for visible rows, never during indexing
- Stay dependency-free unless a package clearly wins on speed or native feel
- Speed is the product. A few hundred apps should stay sub-millisecond once indexed. Do not hop actors or hit the network on a keystroke unless the query actually needs it

## Layout

Sources live at the repo root. `Models/`, `Services/`, `UI/`, and `Tests/` are file-synchronized Xcode groups, so new files in them are picked up automatically

```
Velox/
  main.swift
  AppDelegate.swift
  Info.plist
  Models/
  Services/
  UI/
  Tests/
  Icon.icon/
  .github/workflows/release.yml
  Velox.xcodeproj/
  README.md
  AGENTS.md
```

README is a short product page. Architecture and this layout tree belong here. Keep both files in sync when the product surface or folder layout changes

`Tests/` is a Swift Testing target hosted by Velox. One file per scope:

- `AppBundleTests`
- `AppIndexTests`
- `CurrencyServiceTests`
- `DocsTests`
- `FuzzyMatcherTests`
- `KeyShortcutTests`
- `LaunchAtLoginTests`
- `MathEngineTests`
- `PanelAlignmentTests`
- `SearchEngineTests`
- `SearchPanelSurfaceTests`
- `SettingsWindowTests`
- `SingleInstanceTests`
- `StatusItemTests`
- `ThemeTests`

Do not add a standalone Tools script that reimplements production code

## Runtime

- Accessory / `LSUIElement`. The signed bundle id is `ro.randusoft.velox`. Single-instance matching uses `Bundle.main.bundleIdentifier`. The show-handoff notification is `com.velox.launcher.show`. `Constants.App.bundleIdentifier` matches the signed id
- Not App Sandboxed. Hardened Runtime stays on. There is no App Sandbox capability on the Velox target
- `main.swift` posts that notification and exits when another Velox PID is already running. Dock reopen and the same notification re-show Settings if it is open, otherwise the panel
- Carbon hotkey comes from `Preferences.openShortcut` (default Option+Space) and is remappable. Suspend it while the Settings recorder is capturing
- `launchAtLogin` defaults on and registers `SMAppService.mainApp` at launch. The Settings Search header is a Start at login toggle. Test hosts skip the system login item
- Menu-bar left-click opens Settings. The status item icon stays a magnifying glass. Only the search-field icon morphs to a gear on hover
- Everyday Apple apps in `/System/Applications` and Cryptex (Safari, Notes, Mail) stay visible. Finder stays visible. CoreServices extras are indexed but hidden until `includeSystemApps` is on
- Bar theme and result highlight are separate. Default bar is Glass. Saved `spotlight` maps to Glass, `frost` to Snow, `graphite` to Midnight. Extra tints: Olive, Harbor, Orchid, Parchment. Light bars force light appearance so query text stays readable. Highlight is Accent, Soft, or Contrast. Theme, highlight, and radius apply live. Settings preview parks when Settings resigns key so it does not stay above other apps
- `PanelScreenPolicy` default is the screen with the mouse. `allScreens` keeps the key panel on the mouse screen and mirrors factory-positioned replicas on the others. Preview mode never clones
- Query order is math, then currency parse + convert, then apps. `mathEnabled` and `currencyEnabled` default on and skip that source when off. An empty query must not hop `AppIndex`. Currency must parse before any actor hop, and must not hit the network on a keystroke or when currency is off. Rates refresh on launch and every hour
- App scan roots are rebuilt every index pass. Include `/Applications` on local non-boot volumes only. Skip network volumes before touching disk. Missing folders are a no-op. Volume mount/unmount/rename triggers a rebuild. Directory watchers on user-writable Applications folders debounce a rebuild so App Store installs show up. Rebuilds single-flight and skip the icon cache wipe when the app set is unchanged. A 2-minute timer and a same-age stale check when the panel opens are fallbacks. Search drops `/Volumes/` hits whose files are gone so ejected disks do not linger
- A published GitHub release builds unsigned Release, signs and notarizes via `RanduSoft/macos-signing`, uploads `Velox-<version>.zip` plus `checksums.txt`, then dispatches `rursache/homebrew-tap` `update-formula.yml` for the `velox` cask

## After every change

These steps are required, not optional. A change, fix, or improvement is not done until all of them succeed

1. Add Swift Testing coverage for anything new (type, behavior, or edge case). Put it in the matching `Tests/` file, or add a new file for a new scope
2. Run the test target and do not continue until it is green:

```bash
xcodebuild test -project Velox.xcodeproj -scheme Velox -destination 'platform=macOS'
```

3. Commit the change and push it to `origin`
4. Kill any running Velox, then build and run the **Velox** scheme from `Velox.xcodeproj` (Xcode Run, or `xcodebuild -project Velox.xcodeproj -scheme Velox -destination 'platform=macOS' build`) and launch the Debug app so the user can verify. Do not use a custom DerivedData path or ad-hoc codesign override
