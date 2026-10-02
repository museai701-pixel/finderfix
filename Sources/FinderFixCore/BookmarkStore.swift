import Foundation

/// Per-folder security-scoped bookmarks granted via NSOpenPanel in the host app,
/// shared with the Finder Sync extension through the App Group.
///
/// CRITICAL (verified against the production MoreMenu recipe, 2026):
/// bookmarks MUST be created with `options: []` (implicit security scope).
/// Using `[.withSecurityScope]` produces bookmarks the extension process cannot resolve.
enum BookmarkStore {

    // MARK: - Host app side

    /// Save access to a folder the user chose. Call from the host app only
    /// (never present open panels inside the extension).
    @discardableResult
    static func saveBookmark(for folderURL: URL) -> Bool {
        do {
            let data = try folderURL.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            var map = storedBookmarks()
            map[folderURL.path] = data
            persist(map)
            return true
        } catch {
            NSLog("[FinderFixCore] bookmark save failed for %@: %@", folderURL.path, String(describing: error))
            return false
        }
    }

    static func removeBookmark(forPath path: String) {
        var map = storedBookmarks()
        map.removeValue(forKey: path)
        persist(map)
    }

    static func bookmarkedPaths() -> [String] {
        Array(storedBookmarks().keys).sorted()
    }

    // MARK: - Extension side

    /// Resolve the bookmark whose path is the longest prefix of `target`,
    /// and start a security-scoped session on it (access covers the whole subtree).
    ///
    /// - Returns: The bookmarked root URL with an active security scope, or nil.
    /// - Important: the caller MUST call `stopAccessingSecurityScopedResource()`
    ///   on the returned URL when finished (use `defer`).
    static func scopedRoot(containing target: URL) -> URL? {
        let targetPath = (target.path as NSString).standardizingPath
        let map = storedBookmarks()
        let bestKey = map.keys
            .map { ($0, ($0 as NSString).standardizingPath) }
            .filter { targetPath == $1 || targetPath.hasPrefix($1 + "/") }
            .max(by: { $0.1.count < $1.1.count })?.0
        guard let key = bestKey, let data = map[key] else { return nil }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            // A stale bookmark still resolves; the host app re-saves it lazily
            // on next launch. The extension just proceeds.
            return url.startAccessingSecurityScopedResource() ? url : nil
        } catch {
            NSLog("[FinderFixCore] bookmark resolve failed: %@", String(describing: error))
            return nil
        }
    }

    // MARK: - Private

    private static func storedBookmarks() -> [String: Data] {
        guard let defaults = AppGroup.defaults,
              let raw = defaults.dictionary(forKey: AppGroup.Keys.folderBookmarks) else {
            return [:]
        }
        var map: [String: Data] = [:]
        for (key, value) in raw {
            if let data = value as? Data { map[key] = data }
        }
        return map
    }

    private static func persist(_ map: [String: Data]) {
        AppGroup.defaults?.set(map, forKey: AppGroup.Keys.folderBookmarks)
    }
}

/// System helpers that behave correctly inside the extension sandbox.
enum SystemInfo {
    /// The real home directory. `FileManager.default.homeDirectoryForCurrentUser`
    /// returns the *container* home inside a sandboxed extension — wrong.
    static func realHomeDirectory() -> URL {
        if let pw = getpwuid(getuid()) {
            return URL(fileURLWithPath: String(cString: pw.pointee.pw_dir))
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}
