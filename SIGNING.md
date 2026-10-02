# SIGNING.md — signing, notarization, App Store submission

This project cannot be installed on a Mac without warnings unless it is **properly signed** — and, for direct download, **notarized**. Unsigned or ad-hoc-signed builds will trigger Gatekeeper ("cannot be opened because the developer cannot be verified"). Follow this guide exactly.

> Note: these steps were compiled from 2025–2026 developer documentation and community runbooks. Apple changes portals and CLIs regularly — if a command below fails, check `xcrun notarytool --help` and the current App Store Connect docs before improvising.

## (a) Apple Developer Program enrollment

1. Enroll at [developer.apple.com/programs](https://developer.apple.com/programs/) — **$99/year** (individual or organization).
2. Note your **Team ID** (Membership details page). You need it for bundle IDs, the App Group (`group.<TeamID>.finderfix`), and provisioning.
3. In Xcode → Settings → Accounts, add your Apple ID and download your signing assets.

## (b) Developer ID path (direct download from your website)

Goal: a Gatekeeper-clean `.dmg` — no warnings, `spctl` reports **"Notarized Developer ID"**.

### 1. Certificate
- In Xcode: Settings → Accounts → your team → Manage Certificates → **+ → Developer ID Application**. (For `.pkg` installers you'd also need Developer ID Installer; we ship a DMG, so Application suffices.)
- Verify it's in your keychain:
  ```bash
  security find-identity -v -p codesigning
  ```

### 2. Signing settings
- Set `CODE_SIGN_STYLE` to **Manual** for the Release configuration (or keep Automatic but select your Developer ID identity explicitly for Release). Automatic is fine for Debug.
- **Hardened runtime ON for every target** — host app AND the `.appex`. In Xcode: target → Signing & Capabilities → "Hardened Runtime" (or build setting `ENABLE_HARDENED_RUNTIME=YES`). **Notarization fails without this.**
- **Secure timestamp** (`--timestamp`) on every signature. `xcodebuild archive` applies it automatically when hardened runtime is enabled; if you sign manually with `codesign`, always pass `--timestamp`.

### 3. Build Release and sign inside-out
- Product → Archive (Release configuration).
- **Sign inside-out**: the `.appex` and any nested binaries/frameworks **first**, the `.app` bundle **last**. Xcode's archive flow does this correctly if both targets use your Developer ID identity. If you re-sign manually:
  ```bash
  codesign --force --options runtime --timestamp --sign "Developer ID Application: <Your Name> (<TEAMID>)" FinderFixSync.appex
  codesign --force --options runtime --timestamp --entitlements <path> --sign "Developer ID Application: <Your Name> (<TEAMID>)" FinderFix.app
  ```
- Verify:
  ```bash
  codesign --verify --deep --strict FinderFix.app
  ```
  This **must** pass with no output. Re-sign anything ad-hoc-signed (bundled frameworks, updater bits).

### 4. Create the DMG
```bash
hdiutil create -volname FinderFix -srcfolder FinderFix.app -ov -format UDZO FinderFix-1.0.0.dmg
```
Notarize and staple the **DMG too** — Gatekeeper checks the disk image on download, not just the app inside.

### 5. Notarize with notarytool
Store credentials once (uses an app-specific password, not your Apple ID password):
```bash
xcrun notarytool store-credentials "finderfix-profile" \
  --apple-id <your-apple-id> --team-id <TEAMID> --password <app-specific-password>
```
Submit and wait:
```bash
xcrun notarytool submit FinderFix-1.0.0.dmg --keychain-profile "finderfix-profile" --wait
```
- First-ever submission can take **24–72 hours**; later ones are typically minutes to a few hours.
- On failure: `xcrun notarytool log <submission-id> --keychain-profile "finderfix-profile"` tells you exactly why.

**Common notarization rejections, 2025–2026:**
| Failure | Fix |
|---|---|
| Hardened runtime missing | `ENABLE_HARDENED_RUNTIME=YES` on **every** target, including the appex |
| Secure timestamp missing | Sign with `--timestamp` (or via `xcodebuild archive` with hardened runtime on) |
| Nested binary unsigned or ad-hoc signed | Sign inside-out; re-sign any pre-signed third-party binaries |
| Signed outside-in | Re-do inside-out — signing the outer bundle first invalidates everything and produces confusing late rejections |
| Missing entitlements on a target | Each target must carry its own entitlements file (we ship separate ones for host and extension) |

### 6. Staple and verify
```bash
xcrun stapler staple FinderFix.app
xcrun stapler staple FinderFix-1.0.0.dmg
xcrun stapler validate FinderFix-1.0.0.dmg
spctl -a -vvv -t install FinderFix.app
```
The last command **must** end with `source=Notarized Developer ID`. If it doesn't, do not distribute.

### 7. Real-download test
Upload the DMG somewhere, download it in a **fresh browser session** on a test Mac, and install. The quarantine flag (`com.apple.quarantine`) is only set by real downloads — a local copy never exercises the true Gatekeeper path. A stapled ticket survives certificate expiry (only revocation breaks old copies).

### Finder Sync specifics (Developer ID)
- The appex is built as a sidecar target and embedded in the app (XcodeGen: `embed: true` on the `FinderFixSync` dependency) — verify it lands at `FinderFix.app/Contents/PlugIns/FinderFixSync.appex`.
- App Groups require a **real Team ID** — ad-hoc signing grants no container access, so extension↔host communication silently breaks.
- Verify registration: `pluginkit -mAvvv -p com.apple.FinderSync`; force-enable for local testing: `pluginkit -e use -i <your-extension-bundle-id>` (Terminal/unsandboxed context only).

## (c) Mac App Store path

1. **Archive in Xcode**: Product → Archive with the Release configuration, both targets sandboxed (already configured) with hardened runtime on.
2. **Upload** via Xcode Organizer → Distribute App → App Store Connect. Bump `CFBundleVersion` (`CURRENT_PROJECT_VERSION`) for every upload — Apple rejects duplicate build numbers.
3. **Privacy manifests** are included: `PrivacyInfo.xcprivacy` in **both** bundles (app + appex), declaring UserDefaults (`CA92.1`) — required since May 2024, re-audited 2026.
4. **Usage descriptions** are present: `NSAppleEventsUsageDescription` in the host `Info.plist` (required by the `automation.apple-events` entitlement).
5. **Review notes are load-bearing — do not skip this.** The reviewer must *manually* enable the Finder Sync extension, and they will not know how. Paste this into the review notes, verbatim-ish:
   > FinderFix's right-click menu items live in a Finder Sync extension. To enable for review: open the app from /Applications, then System Settings → General → Login Items & Extensions → Extensions → Finder → toggle FinderFix ON. The in-app "How to Enable the Finder Extension" guide (menu-bar icon menu) walks through the same steps. Note: the global hotkeys (⌃⌘X cut, ⌃⌘V paste, ⌃⌘N new file) work without the extension — they act on the frontmost Finder window via the host app.
   
   **Attach a demo video unprompted** showing: granting folder access, enabling the extension, and each menu item working. Guideline **2.1(a)** ("Information Needed" / reviewer couldn't exercise the app) is the classic Finder-utility rejection — a 2026 case hit exactly this pattern.
6. **Guideline 4.3(b)** was tightened in June 2026 (low-quality / saturated categories; Apple may remove stale apps). Differentiate in the App Store description: this is a **bundle of 7 fixes** (New File, Cut/Paste, clipboard-as-file, copy path, copy name, Terminal, hidden files) with hotkeys, not a single-trick utility. Keep the app maintained post-launch.

### The automation.apple-events entitlement — fallback plan
The `com.apple.security.automation.apple-events` entitlement (hidden-files toggle + hotkeys reading the frontmost Finder window) carries **moderate App Review risk**: it triggers an Automation consent prompt, and reviewers scrutinize it. If review rejects it:
1. **Remove the key** from `FinderFix.entitlements` (keep everything else).
2. The app is **already designed for this**: every `FinderBridge` call returns nil/false on denied consent, and the UI falls back to guide mode (the onboarding window shows manual instructions, e.g. press ⌘⇧. for hidden files). Hotkey actions that need Finder info will route the user to grant folder access instead of failing silently.
3. Resubmit. The right-click Cut/Paste, New File, clipboard-as-file, copy path/name, and Open-in-Terminal features do not depend on Apple Events.

### No private API, no temporary exceptions
The build uses no private API and no `temporary-exception` entitlements. If a future feature tempts you toward either, treat that as a separate review-risk decision — do not bundle it into a routine update.
