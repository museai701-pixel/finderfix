# From source to installable DMG — the full path

You have complete source code. This guide gets you to a double-click-installable,
warning-free DMG. Three things only you can do are marked 👤.

## Path A — I just want to try it on my Mac (10 minutes, free)

1. Install Xcode 26+ from the App Store and run `brew install xcodegen`.
2. Unzip the source, `cd` in, run `xcodegen generate`, open `FinderFix.xcodeproj`.
3. Press ⌘R. On first run: grant folder access in the onboarding window, then
   enable the Finder extension in System Settings → General → Login Items &
   Extensions → Extensions → Finder toggle.
4. Work through TEST-CHECKLIST.md and report anything broken.

No signing needed for your own testing — Xcode signs it for local development.

## Path B — cloud build on every push (15 minutes, free)

So the project compiles in the cloud without your Mac:

1. 👤 Create a GitHub repo, push the contents of this folder to `main`
   (the folder IS the repo root — `project.yml` sits at the top level).
2. The `build.yml` workflow runs automatically: installs XcodeGen, generates the
   project, compiles app + extension unsigned, and uploads the `.app` as an
   artifact you can download from the Actions tab.
3. Send any red build log to your developer — compile errors get fixed fast
   once they're visible.

The unsigned `.app` installs with one manual Gatekeeper bypass (right-click →
Open, once). Fine for testing, NOT for customers.

## Path C — the warning-free DMG for customers (needs Apple Developer, $99/yr)

1. 👤 Enroll in the Apple Developer Program.
2. 👤 In Xcode → Settings → Accounts, add your Apple ID; Xcode manages the
   "Developer ID Application" certificate. Export it as .p12 from Keychain Access.
3. 👤 In the GitHub repo → Settings → Secrets and variables → Actions, add the
   five secrets listed at the top of `.github/workflows/release.yml`.
4. Actions tab → "Release (signed DMG)" → Run workflow.
5. Download `FinderFix-signed-dmg` — install it on a fresh user account and
   confirm zero warnings. `spctl -a -vvv -t install` must say "Notarized Developer ID".

Full certificate/notarization/App Store submission detail lives in SIGNING.md.

## About "animations and professional feel"

FinderFix is a menu-bar utility + Finder right-click menus — its surface is
small by design, and it uses native SwiftUI/AppKit throughout, which is what
gives Mac apps their smooth, native feel (no custom animation framework needed).
The visual polish pass (icon, onboarding flow, Settings refinement) is scheduled
right after the first green cloud build, so polish iterates against a project
that provably compiles instead of risking blind breakage.
