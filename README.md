# FinderFix v1 — source

> **⚠️ HONEST DISCLAIMER — READ FIRST**
>
> This code was **written carefully but NEVER compiled or run**. The author worked in a Linux sandbox with no Xcode, no macOS, and no Apple Developer account. Every Swift file is hand-reviewed against Apple's documented APIs and current (2026) community recipes, but **zero runtime verification exists**.
>
> **Do not ship, sign, or submit anything until you have worked through [`TEST-CHECKLIST.md`](TEST-CHECKLIST.md) on a real Mac.** The checklist is mandatory, not optional — it is the entire QA process for this project.

## What FinderFix is

FinderFix is a one-time-purchase ($7.99) Mac utility that fixes the Finder papercuts Apple never fixed. It adds to Finder's right-click menu (and to global hotkeys):

| Feature | Right-click menu | Hotkey (default) |
|---|---|---|
| New File here (txt/md + custom templates) | ✓ submenu | ⌃⌘N |
| Cut / Paste files (move between folders) | ✓ | ⌃⌘X / ⌃⌘V |
| Paste Clipboard as File (image or text) | ✓ | — |
| Copy POSIX Path of selection | ✓ | — |
| Copy File Name of selection | ✓ | — |
| Open in Terminal at folder | ✓ | — |
| Show/Hide Hidden Files | ✓ (routes through host app) | — |

Deliberately **not** included: true bare ⌘X interception. That requires an Accessibility-trusting event tap, which sandboxed App Store apps can never obtain. See "Design decisions" below.

## Architecture

Two processes, one shared module:

```
FinderFix.app  (host — LSUIElement menu-bar app, sandboxed)
├── menu-bar icon (folder glyph drawn in code, template image)
├── OnboardingWindow — 2 steps: (1) grant folder access via NSOpenPanel,
│                        (2) guide to enable the Finder Sync extension
├── SettingsView — hotkey preset pickers, template editor, folder list
├── HotKeyManager — Carbon RegisterEventHotKey; fires ONLY while Finder is frontmost
├── FinderBridge — NSAppleScript calls to Finder (selection paths, frontmost
│                   window target, hidden-files toggle). Needs the
│                   automation.apple-events entitlement → user consent prompt.
└── FinderFixSync.appex (Finder Sync extension, sandboxed)
    └── FinderSync.swift — principal class (@objc(FinderSync))
        ├── items menu (file/folder selection): Cut · Copy POSIX Path · Copy File Name
        └── container menu (folder background/Desktop): New File ▸ · Paste ·
            Paste Clipboard as File · Open in Terminal · Show/Hide Hidden Files

FinderFixCore (shared by both targets)
├── AppGroup.swift      — App Group id + shared UserDefaults keys + notification names
├── BookmarkStore.swift — security-scoped bookmarks (options:[] — see below)
├── CutState.swift      — pending-cut record, 1-hour expiry
└── FileOperations.swift— uniqueURL, createFile, moveItems, ClipboardReader payload
```

**Communication:** the host app and extension share state through the App Group
`group.com.icyigniter.finderfix` (UserDefaults suite): folder bookmarks, cut state, custom templates. The extension posts a `DistributedNotification` when the user picks "Show/Hide Hidden Files"; the host app performs the toggle (the extension cannot write Finder's preferences from its sandbox).

**Permission architecture** (verified against the production MoreMenu recipe, 2026):
1. Host app asks for folder access via `NSOpenPanel` (powerbox grant).
2. Host creates a security-scoped bookmark with **`options: []`** (implicit security scope). **Do NOT use `[.withSecurityScope]`** — the extension process cannot resolve those.
3. Bookmark data is stored in the App Group.
4. The extension resolves the bookmark, calls `startAccessingSecurityScopedResource()`, does the file op, calls `stopAccessingSecurityScopedResource()`.
5. Extension menus only appear inside folders registered in `FIFinderSyncController.directoryURLs` (real home via `getpwuid` + bookmarked folders — `FileManager.homeDirectoryForCurrentUser` returns the *container* home inside the extension sandbox, which is wrong).

## Build steps

Requirements: **a Mac with Xcode 26+** (Swift 6; never ship a beta-SDK build), and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
cd FinderFix
brew install xcodegen
xcodegen generate        # generates FinderFix.xcodeproj from project.yml
open FinderFix.xcodeproj
```

Then, inside Xcode:

1. **Set your Team** — select the `FinderFix` target → Signing & Capabilities → Team. Do the same for `FinderFixSync`. (Or set `DEVELOPMENT_TEAM` in `project.yml` and re-generate.)
2. **Replace placeholder identifiers** with your own. Find-and-replace everywhere (source + plists + entitlements):
   - `com.icyigniter.finderfix` → `com.<you>.finderfix`
   - `com.icyigniter.finderfix.sync` → `com.<you>.finderfix.sync`
   - `group.com.icyigniter.finderfix` → `group.<TeamID-or-you>.finderfix` (must be registered under your Team ID in the developer portal — ad-hoc signing grants no App Group container access)
   - Notification names in `AppGroup.swift` (`com.icyigniter.finderfix.*`) — update to match.
3. Build & run the `FinderFix` scheme (Debug).
4. **Run from /Applications for extension registration.** Drag the built `FinderFix.app` into `/Applications` and launch it from there at least once — Finder Sync extensions register reliably only when the host lives in /Applications. Then follow the in-app guide: System Settings → General → Login Items & Extensions → Extensions → Finder → toggle FinderFix on.
5. Verify registration in Terminal: `pluginkit -mAvvv -p com.apple.FinderSync` should list the extension. (Local testing only; don't ship with manual pluginkit enabling.)

For distribution (signing, notarization, App Store submission), see [`SIGNING.md`](SIGNING.md). For the full behavior-verification pass, see [`TEST-CHECKLIST.md`](TEST-CHECKLIST.md).

## Design decisions (read before changing anything)

- **No bare ⌘X.** True system-wide ⌘X-for-files needs a CGEventTap rewriting ⌘X→⌘C / ⌘V→⌥⌘V, which needs Accessibility trust — unavailable to sandboxed apps. Instead: right-click Cut/Paste in the Finder Sync menu + ⌃⌘X/⌃⌘V hotkeys (gated to Finder being frontmost) that drive the app's own `FileManager.moveItem` implementation. It is not ⌘X; the marketing copy must not claim otherwise.
- **No key equivalents on Finder Sync menu items.** Widely reported as ignored by Finder; the code sets `keyEquivalent: ""` everywhere on purpose.
- **Hidden files toggle goes through Apple Events** (`tell application "Finder" to do shell script "defaults write …"`, then `quit` to relaunch Finder). This needs the `automation.apple-events` entitlement → a user consent prompt → App Review scrutiny. The code already degrades gracefully on denial (shows the manual ⌘⇧. guide). If App Review rejects the entitlement, remove the key — the fallback paths are already implemented. See `SIGNING.md`.
- **Carbon `RegisterEventHotKey`** for global hotkeys. It is *not* deprecated for this purpose — Apple never shipped a replacement, it works fully sandboxed with no permission dialogs, and it is what KeyboardShortcuts/Dato/Lungo ship. Media keys are not supported in sandboxed apps.
- **Hotkeys are presets, not a free-form recorder** (⌃⌘, ⌥⌘, ⇧⌃⌘, ⌃⌥⌘). Presets can't collide with typing and are localizable.
- **Cut state expires after 1 hour** and lives in the App Group so the extension and host app share it. The extension clears the cut only on full move success; a partial move leaves remaining items claimed so the user can retry.
- **Swift 6 strictness:** `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; the FIFinderSync ObjC entry points are nonisolated, so `menu(for:)` hops explicitly and all file I/O stays off the main actor. Do not "simplify" this — it will compile-fail or beachball Finder.

## File map

| Path | Contents |
|---|---|
| `project.yml` | XcodeGen project definition (targets, bundle IDs, entitlements refs) |
| `Sources/FinderFix/` | Host app: `FinderFixApp.swift`, `AppDelegate.swift` (menu bar), `HotKeyManager.swift`, `FinderBridge.swift`, `OnboardingWindow.swift`, `SettingsView.swift`, `Info.plist` (LSUIElement, `NSAppleEventsUsageDescription`), `FinderFix.entitlements`, `PrivacyInfo.xcprivacy` (UserDefaults CA92.1) |
| `Sources/FinderFixSync/` | Extension: `FinderSync.swift`, `Info.plist` (`CFBundlePackageType=XPC!`, `NSExtensionPointIdentifier=com.apple.FinderSync`, principal class `FinderSync`), `FinderFixSync.entitlements`, `PrivacyInfo.xcprivacy` |
| `Sources/FinderFixCore/` | Shared: `AppGroup.swift`, `BookmarkStore.swift`, `CutState.swift`, `FileOperations.swift` |
| `SIGNING.md` | Developer ID + Mac App Store signing/submission guide |
| `TEST-CHECKLIST.md` | Mandatory QA checklist — **the app is NOT tested until this is done** |
