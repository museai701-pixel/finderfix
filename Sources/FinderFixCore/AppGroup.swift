import Foundation

/// Shared constants for the App Group connecting the main app and the Finder Sync extension.
enum AppGroup {
    /// App Group identifier. Replace with your own (e.g. group.<TeamID>.finderfix) when
    /// signing with your Apple Developer team.
    static let identifier = "group.com.icyigniter.finderfix"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }

    enum Keys {
        /// [String: Data] — absolute folder path → bookmark data (created with `options: []`).
        static let folderBookmarks = "ff.folderBookmarks.v1"
        /// [String] — absolute paths of the currently "cut" items.
        static let cutItemPaths = "ff.cutItemPaths.v1"
        /// Date the cut was claimed; cuts older than `CutState.expiry` are ignored.
        static let cutClaimDate = "ff.cutClaimDate.v1"
        /// [[String: String]] — custom New-File templates ({name, ext, content}).
        static let customTemplates = "ff.customTemplates.v1"
    }

    /// Host app bundle identifier (used by the extension to launch the app).
    static let hostBundleIdentifier = "com.icyigniter.finderfix"

    /// Distributed notification posted by the extension when the user picks
    /// "Show/Hide Hidden Files" (the extension cannot toggle it itself).
    static let toggleHiddenFilesNotification = Notification.Name("com.icyigniter.finderfix.toggleHiddenFiles")

    /// Distributed notification posted by the host app after folder bookmarks change,
    /// so the extension re-registers `FIFinderSyncController.directoryURLs`.
    static let foldersChangedNotification = Notification.Name("com.icyigniter.finderfix.foldersChanged")
}
