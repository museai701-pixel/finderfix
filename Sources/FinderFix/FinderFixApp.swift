import SwiftUI

/// FinderFix — menu-bar (LSUIElement) host app.
///
/// All Finder-facing work is split across two processes:
///  - This app: menu-bar UI, global hotkeys, folder bookmarks, AppleScript bridge to Finder.
///  - FinderFixSync (Finder Sync extension): the right-click menu inside Finder.
///
/// Shared state (bookmarks, cut state, templates) lives in FinderFixCore and is
/// exchanged through the App Group `group.com.icyigniter.finderfix`.
@main
struct FinderFixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // The app is LSUIElement (no Dock icon, no main menu bar). All windows are
        // managed manually by AppDelegate (settings, onboarding). This empty Settings
        // scene keeps SwiftUI happy without adding any visible UI.
        Settings {
            EmptyView()
        }
    }
}
