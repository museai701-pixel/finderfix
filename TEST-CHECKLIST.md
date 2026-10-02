# TEST-CHECKLIST.md — mandatory QA before any distribution

> **STATUS: ❌ NOT YET TESTED**
>
> This checklist was written carefully from the source, but **nothing on it has been verified on a real Mac**. The author worked in a Linux sandbox with no Xcode. Every box below must be checked on a physical Mac (Apple Silicon, macOS Tahoe 26 or later recommended) with a **clean Release build signed with a real Team ID** before the app is distributed, notarized, or submitted.
>
> How to use: work top to bottom. A failure in group A–C blocks everything below. Log every failure with the macOS version, build number, and Console log lines (`[FinderFixSync]` / `[FinderFix]` prefixes are in the code for this).

## A. First launch & onboarding

- [ ] App launches from `/Applications` with no crash, no Dock icon (LSUIElement), menu-bar folder icon appears.
- [ ] First launch (no folder bookmarks yet) opens the 2-step onboarding window automatically.
- [ ] Relaunching does NOT re-show onboarding once `ff.hasLaunchedBefore` is set and folders are granted.
- [ ] "Grant Folder Access…" from the menu-bar icon opens onboarding at the folder-grant step.
- [ ] "How to Enable the Finder Extension" opens onboarding at the extension-enable guide step.
- [ ] Settings… opens a 560×520 window, reuses the same window on second open (no duplicates).
- [ ] Quit FinderFix from the menu-bar menu terminates cleanly (hotkeys unregistered — verify ⌃⌘X stops working after quit).

## B. Extension enablement

- [ ] With the extension toggle OFF in System Settings → General → Login Items & Extensions → Extensions → Finder, NO FinderFix items appear in Finder right-click menus.
- [ ] With the toggle ON, items appear (after a Finder window refresh — note whether a Finder relaunch is required; document it for users).
- [ ] `pluginkit -mAvvv -p com.apple.FinderSync` lists the extension with the correct bundle ID.
- [ ] Toggling the extension OFF and back ON does not duplicate menu items.
- [ ] Menus appear ONLY inside monitored directories (home folder + bookmarked folders) — verify they do NOT appear in a folder the user never granted (e.g. `/tmp` if ungranted).

## C. Right-click menu items

**Items menu (right-click on selected file(s)/folder(s)):**
- [ ] "Cut" appears on single-file selection, multi-file selection, and folder selection.
- [ ] "Copy POSIX Path" copies the absolute path(s), newline-separated for multiple.
- [ ] "Copy File Name" copies just the file name(s).
- [ ] Paths with spaces, unicode, and special characters round-trip correctly.
- [ ] No key equivalents are shown on any FinderFix menu item (by design — `keyEquivalent: ""`).

**Container menu (right-click on folder background, incl. Desktop):**
- [ ] "New File ▸" submenu lists all built-in templates (verify each: name + extension).
- [ ] Custom templates created in Settings appear in the submenu.
- [ ] "Paste" is DISABLED when no live cut exists, ENABLED after "Cut".
- [ ] "Paste Clipboard as File" is DISABLED with empty/unsupported clipboard, ENABLED with image or text.
- [ ] "Open in Terminal" appears; "Show/Hide Hidden Files" appears.
- [ ] Sidebar right-click shows NO FinderFix menu (excluded by design).

## D. Cut / Paste (move) — extension path

- [ ] Right-click Cut on files → right-click Paste in a bookmarked destination folder moves the files.
- [ ] Cross-folder move: source folder A → destination folder B (both bookmarked).
- [ ] Move into a subfolder of the bookmarked root works (longest-prefix bookmark matching).
- [ ] **Name collision**: pasting `photo.jpg` into a folder that already has `photo.jpg` — verify behavior (unique renaming vs error) and that no data is lost or overwritten.
- [ ] Moving a folder containing files preserves the whole tree.
- [ ] Cut items moved OUTSIDE the app (e.g. user drags them in Finder between Cut and Paste) — verify Paste fails gracefully (reveals host app / no crash).
- [ ] Cut expires after 1 hour: set a cut, wait (or manipulate clock), verify Paste is disabled afterward.
- [ ] Partial move failure (e.g. destination becomes unwritable mid-move): remaining items stay claimed so the user can retry — verify no silent data loss.
- [ ] Paste to a NON-bookmarked folder: host app is revealed so the user can grant access (never fails silently).

## E. Clipboard as file

- [ ] Copy an image (e.g. screenshot to clipboard) → "Paste Clipboard as File" creates a valid image file with the right extension.
- [ ] Copy plain text → creates a text file with the text content.
- [ ] Empty clipboard → menu item is disabled (verify it never creates a 0-byte mystery file).
- [ ] Filename uniqueness: repeat the action twice in the same folder → second file gets a uniquified name, first is untouched.
- [ ] The created file opens in its default app (extension calls `NSWorkspace.open`).

## F. Global hotkeys

- [ ] Defaults work out of the box: ⌃⌘X cut, ⌃⌘V paste, ⌃⌘N new file.
- [ ] Hotkeys fire ONLY when Finder is frontmost — verify they do nothing in Safari, Terminal, TextEdit.
- [ ] ⌃⌘X records Finder's current selection as the cut (check via ⌃⌘V in another folder).
- [ ] ⌃⌘V with no live cut does nothing (no error dialog, no crash).
- [ ] ⌃⌘N creates a file from the default template in the frontmost Finder window's folder and reveals it.
- [ ] Hotkeys work with NO Finder window open where applicable (cut needs a selection; new file needs a window — verify graceful no-ops).
- [ ] **Remapping**: change each hotkey preset in Settings (⌥⌘, ⇧⌃⌘, ⌃⌥⌘) — old combo stops, new combo starts, no duplicate registrations.
- [ ] Persistence: remapped hotkeys survive app relaunch.
- [ ] **Conflicts**: verify the defaults don't collide with common system/app shortcuts on a stock macOS install; document any collision found.
- [ ] Rapid repeated hotkey presses don't deadlock or double-register (check Console for `RegisterEventHotKey failed` lines).

## G. Hidden-files toggle

- [ ] First use triggers the macOS **Automation consent prompt** ("FinderFix would like to control Finder") with the `NSAppleEventsUsageDescription` text.
- [ ] On Allow: "Show/Hide Hidden Files" toggles Finder's hidden files (verify with a dotfile in the test folder; Finder relaunches).
- [ ] Toggle is a true toggle: on → off → on works repeatedly.
- [ ] On Deny: the app shows the manual guide (⌘⇧. instructions) instead of failing silently — verify no crash, no hang.
- [ ] Deny → later Allow in System Settings → Privacy & Security → Automation: toggle starts working without reinstall.

## H. Sandbox prompts & permissions

- [ ] First NSOpenPanel folder grant produces the expected powerbox behavior; no extra scary prompts.
- [ ] Revoke folder access (remove in Settings) → extension actions targeting that folder reveal the host app for re-grant (never a silent no-op).
- [ ] App Group container is actually shared: grant a folder in the host app, then WITHOUT relaunching, use the extension menu in that folder (if the folders-changed distributed notification fails, menus won't appear — catch this here).
- [ ] Stale bookmarks: grant a folder, rename it in Finder, relaunch host — verify re-save path works and the extension recovers.

## I. Open in Terminal

- [ ] "Open in Terminal" on a folder background opens a new Terminal window `cd`'d into that folder.
- [ ] Works on Desktop background (target = ~/Desktop).
- [ ] Folder path with spaces works.
- [ ] Verify the unsandboxed fallback behavior is documented if LaunchServices mediation ever fails.

## J. Flagged-as-unverifiable items (from the technical build brief)

These are the items the research **could not verify** — each needs an explicit prototype test, not just a checkbox glance:

- [ ] **do-shell-script-inside-Finder-tell**: confirm `tell application "Finder" to do shell script "defaults write com.apple.finder …"` actually executes and `quit` relaunches Finder on Tahoe 26/27. (Community-derived; flagged unverified.)
- [ ] **NSAppleScript behavior**: confirm `NSAppleScript` still executes Finder scripts from a sandboxed host app on the Xcode 26 SDK (not deprecated/broken); test selection-path and frontmost-window scripts on macOS 27 GM.
- [ ] **Hotkey event proc conversion**: confirm the Swift function passed to `InstallEventHandler` (Carbon `EventHandlerUPP`) is invoked reliably under Swift 6 / Xcode 26 — no calling-convention breakage.
- [ ] **appex embedding**: confirm the built `FinderFix.app/Contents/PlugIns/` contains `FinderFixSync.appex` when generated via XcodeGen (`embed: true` on the dependency) — inspect the built product, don't assume.
- [ ] **Finder honors no keyEquivalent**: confirm none of the extension menu items show or respond to key equivalents in real Finder (widely reported ignored; verify, don't design around).
- [ ] **Terminal launch from sandboxed extension**: confirm `NSWorkspace.open(_:withApplicationAt:)` launching Terminal.app at a folder works from the *extension* process (no 2024–2026 MAS report found; the `.command`-file fallback is documented in the research if it fails).
- [ ] **Bookmark recipe**: confirm `options: []` bookmarks created by the host resolve in the extension process on a Team-ID-signed build (community-derived MoreMenu recipe, not Apple-documented — validate in YOUR prototype).
- [ ] **macOS 27 Finder Sync changes**: re-verify against the macOS 27 GM SDK before shipping (was in developer beta at research time).

## K. Release-candidate gates (do last)

- [ ] Full pass on a **clean macOS user account** (no dev tools, no prior grants) — the true first-run experience.
- [ ] Full pass on **macOS 26 AND macOS 27** if both are available.
- [ ] Console is free of `[FinderFixSync]` / `[FinderFix]` error lines during a normal session.
- [ ] `codesign --verify --deep --strict` passes on the Release build.
- [ ] Only after every box above is checked: proceed to `SIGNING.md`.
