//
//  FinderSync.swift
//  FinderFixSync — Finder Sync extension for FinderFix
//
//  What this is:
//    The principal class of the Finder Sync app extension. It injects FinderFix's
//    right-click menu items into Finder: Cut / Copy POSIX Path / Copy File Name
//    on selections, and New File / Paste / Paste Clipboard as File / Open in
//    Terminal / Show-Hide Hidden Files on folder backgrounds.
//
//  Architecture (verified against the production MoreMenu recipe, 2026):
//    * The extension is a SEPARATE SANDBOXED PROCESS. It inherits neither
//      Finder's nor the host app's file access.
//    * All folder access flows through security-scoped bookmarks created by the
//      HOST app (NSOpenPanel) with `options: []` and shared via the App Group.
//      Never present open/save panels here; never use AppleScript here.
//    * Menus only appear inside directories registered in
//      FIFinderSyncController.directoryURLs (real home + bookmarked folders).
//    * The extension never touches Finder's preferences itself: "Show/Hide
//      Hidden Files" posts a distributed notification and the host app
//      performs the toggle.
//
//  Concurrency (Swift 6):
//    FIFinderSync's ObjC entry points (`init`, `menu(for:)`) are nonisolated.
//    Finder invokes `menu(for:)` on the extension's main thread, but we hop to
//    the MainActor explicitly rather than assuming it, and keep `menu(for:)`
//    fast and synchronous — all file I/O goes through the FinderFixCore helpers
//    (BookmarkStore / CutState / FileOperations), which are synchronous and local.

import AppKit
import FinderSync

/// Principal class of the Finder Sync extension.
/// The name MUST stay `FinderSync`: Info.plist binds NSExtensionPrincipalClass
/// to the literal string "FinderSync" via `@objc(FinderSync)`.
@objc(FinderSync)
final class FinderSync: FIFinderSync {

    // MARK: - Lifecycle

    override init() {
        super.init()

        registerMonitoredDirectories()

        // The host app posts this after the user adds/removes folders, so the
        // extension re-registers directoryURLs without a Finder relaunch.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(foldersChanged(_:)),
            name: AppGroup.foldersChangedNotification,
            object: nil
        )

        NSLog("[FinderFixSync] extension initialized")
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    // MARK: - Monitored directories

    /// Menus only appear inside these directories. The real home directory is
    /// resolved via getpwuid — `FileManager.homeDirectoryForCurrentUser` returns
    /// the sandbox *container* home inside an extension, which is wrong.
    private func registerMonitoredDirectories() {
        var urls: Set<URL> = [SystemInfo.realHomeDirectory()]
        for path in BookmarkStore.bookmarkedPaths() {
            urls.insert(URL(fileURLWithPath: path))
        }
        FIFinderSyncController.default().directoryURLs = urls
        NSLog("[FinderFixSync] monitoring %d directorie(s)", urls.count)
    }

    @objc private func foldersChanged(_ note: Notification) {
        registerMonitoredDirectories()
    }

    // MARK: - Menu construction

    /// Called by Finder to build the contextual menu. Must be fast and
    /// synchronous. Menu construction is main-thread-only AppKit, so hop to
    /// the MainActor explicitly (Finder calls this on the main thread; the
    /// fallback below keeps us safe even if that ever changes).
    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { buildMenu(for: menuKind) }
        }
        // Defensive: never build AppKit menus off the main thread.
        return DispatchQueue.main.sync { buildMenu(for: menuKind) }
    }

    private func buildMenu(for menuKind: FIMenuKind) -> NSMenu? {
        switch menuKind {
        case .contextualMenuForItems:
            return buildItemsMenu()
        case .contextualMenuForContainer:
            return buildContainerMenu()
        case .contextualMenuForSidebar:
            // Sidebar targets have no reliable destination directory — excluded
            // per the MoreMenu recipe.
            return nil
        @unknown default:
            return nil
        }
    }

    /// Right-click on one or more selected files/folders.
    private func buildItemsMenu() -> NSMenu? {
        guard let selection = selectedItemURLs(), !selection.isEmpty else {
            return nil
        }

        let menu = NSMenu()

        // "Cut" — records the selection in shared CutState; "Paste" (container
        // menu) claims it. No ⌘X key equivalent: hijacking ⌘X inside Finder's
        // contextual menu would also fire while renaming files in text fields.
        let cut = NSMenuItem(title: "Cut", action: #selector(cutItems(_:)), keyEquivalent: "")
        cut.target = self
        menu.addItem(cut)

        menu.addItem(.separator())

        let copyPath = NSMenuItem(title: "Copy POSIX Path", action: #selector(copyPOSIXPaths(_:)), keyEquivalent: "")
        copyPath.target = self
        menu.addItem(copyPath)

        let copyName = NSMenuItem(title: "Copy File Name", action: #selector(copyFileNames(_:)), keyEquivalent: "")
        copyName.target = self
        menu.addItem(copyName)

        return menu
    }

    /// Right-click on a folder background (including the Desktop).
    private func buildContainerMenu() -> NSMenu? {
        let menu = NSMenu()

        // "New File" submenu — one item per template (built-in + user-defined).
        let newFile = NSMenuItem(title: "New File", action: nil, keyEquivalent: "")
        let templatesMenu = NSMenu()
        for template in Templates.all() {
            let item = NSMenuItem(
                title: "\(template.name) (.\(template.ext))",
                action: #selector(newFileFromTemplate(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = template
            templatesMenu.addItem(item)
        }
        newFile.submenu = templatesMenu
        menu.addItem(newFile)

        // "Paste" — enabled only while a live cut exists.
        let paste = NSMenuItem(title: "Paste", action: #selector(pasteCutItems(_:)), keyEquivalent: "")
        paste.target = self
        paste.isEnabled = CutState.hasLiveCut
        menu.addItem(paste)

        // "Paste Clipboard as File" — disabled when the pasteboard holds
        // nothing usable (checked here so the menu never lies).
        let pasteClipboard = NSMenuItem(
            title: "Paste Clipboard as File",
            action: #selector(pasteClipboardAsFile(_:)),
            keyEquivalent: ""
        )
        pasteClipboard.target = self
        pasteClipboard.isEnabled = ClipboardReader.payload() != nil
        menu.addItem(pasteClipboard)

        menu.addItem(.separator())

        let terminal = NSMenuItem(title: "Open in Terminal", action: #selector(openInTerminal(_:)), keyEquivalent: "")
        terminal.target = self
        menu.addItem(terminal)

        let hiddenFiles = NSMenuItem(
            title: "Show/Hide Hidden Files",
            action: #selector(toggleHiddenFiles(_:)),
            keyEquivalent: ""
        )
        hiddenFiles.target = self
        menu.addItem(hiddenFiles)

        return menu
    }

    // MARK: - Target resolution

    /// The directory container actions should target. `targetedURL()` may point
    /// at a file rather than a folder; normalize to the parent directory.
    /// Returns nil when Finder gives us no target at all.
    private func containerDirectory() -> URL? {
        guard var url = targetedURL() else { return nil }
        // Cheap local metadata check. If it fails (e.g. sandbox), the URL is
        // kept as-is and the bookmark gate below makes the final decision —
        // we never proceed without a covering bookmark.
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == false {
            url = url.deletingLastPathComponent()
        }
        return url
    }

    // MARK: - Item actions

    @objc private func cutItems(_ sender: NSMenuItem) {
        guard let selection = selectedItemURLs(), !selection.isEmpty else { return }
        CutState.set(paths: selection.map { $0.path })
        NSLog("[FinderFixSync] cut %d item(s)", selection.count)
    }

    @objc private func copyPOSIXPaths(_ sender: NSMenuItem) {
        guard let selection = selectedItemURLs(), !selection.isEmpty else { return }
        FileOperations.copyPOSIXPaths(selection)
    }

    @objc private func copyFileNames(_ sender: NSMenuItem) {
        guard let selection = selectedItemURLs(), !selection.isEmpty else { return }
        FileOperations.copyFileNames(selection)
    }

    // MARK: - Container actions

    @objc private func newFileFromTemplate(_ sender: NSMenuItem) {
        guard let template = sender.representedObject as? FileTemplate else { return }
        guard let dir = containerDirectory() else { return }
        guard let scoped = BookmarkStore.scopedRoot(containing: dir) else {
            revealHostApp()
            return
        }
        defer { scoped.stopAccessingSecurityScopedResource() }

        do {
            let url = FileOperations.uniqueURL(
                in: dir,
                baseName: template.name,
                pathExtension: template.ext
            )
            try FileOperations.createFile(at: url, contents: Data(template.content.utf8))
            NSLog("[FinderFixSync] created file %@", url.path)
            // Verified working from the extension (MoreMenu recipe): opening the
            // new file reveals it in Finder and hands it to its default app.
            NSWorkspace.shared.open(url)
        } catch {
            NSLog("[FinderFixSync] create file failed: %@", String(describing: error))
            revealHostApp()
        }
    }

    @objc private func pasteCutItems(_ sender: NSMenuItem) {
        let paths = CutState.claimedPaths()
        guard !paths.isEmpty else { return }
        guard let dir = containerDirectory() else { return }

        let sources = paths.map { URL(fileURLWithPath: $0) }
        // A move needs access to BOTH the source folders and the destination,
        // so scope every distinct bookmarked root involved.
        guard let roots = beginScopedAccess(for: sources + [dir]) else {
            revealHostApp()
            return
        }
        defer { endScopedAccess(roots) }

        do {
            let moved = try FileOperations.moveItems(sources, to: dir)
            // Clear only on full success: on a partial move the remaining cut
            // items stay claimed so the user can retry elsewhere.
            CutState.clear()
            NSLog("[FinderFixSync] pasted %d item(s) into %@", moved.count, dir.path)
        } catch {
            NSLog("[FinderFixSync] paste failed: %@", String(describing: error))
            revealHostApp()
        }
    }

    @objc private func pasteClipboardAsFile(_ sender: NSMenuItem) {
        guard let payload = ClipboardReader.payload() else { return }
        guard let dir = containerDirectory() else { return }
        guard let scoped = BookmarkStore.scopedRoot(containing: dir) else {
            revealHostApp()
            return
        }
        defer { scoped.stopAccessingSecurityScopedResource() }

        do {
            let url = FileOperations.uniqueURL(
                in: dir,
                baseName: payload.baseName,
                pathExtension: payload.pathExtension
            )
            try FileOperations.createFile(at: url, contents: payload.data)
            NSLog("[FinderFixSync] pasted clipboard as %@", url.path)
            NSWorkspace.shared.open(url)
        } catch {
            NSLog("[FinderFixSync] paste-as-file failed: %@", String(describing: error))
            revealHostApp()
        }
    }

    @objc private func openInTerminal(_ sender: NSMenuItem) {
        guard let dir = containerDirectory() else { return }
        guard let terminalURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.Terminal"
        ) else {
            NSLog("[FinderFixSync] Terminal.app not found")
            return
        }
        // Opening a folder *with* Terminal.app opens a new window cd'd into it.
        NSWorkspace.shared.open(
            [dir],
            withApplicationAt: terminalURL,
            configuration: NSWorkspace.OpenConfiguration(),
            completionHandler: nil
        )
    }

    @objc private func toggleHiddenFiles(_ sender: NSMenuItem) {
        // The extension must not touch Finder's preferences itself (sandbox +
        // cfprefsd caching make it unreliable). The host app observes this
        // notification and performs the toggle.
        DistributedNotificationCenter.default().post(
            name: AppGroup.toggleHiddenFilesNotification,
            object: nil
        )
        NSLog("[FinderFixSync] requested hidden-files toggle")
    }

    // MARK: - Security-scoped access

    /// Starts security-scoped sessions for the distinct bookmarked roots
    /// covering every URL in `urls`.
    ///
    /// - Returns: the scoped root URLs, or nil when ANY url is not covered by a
    ///   bookmark. On nil, sessions already started are balanced before
    ///   returning — the caller must then `revealHostApp()`.
    /// - Important: the caller MUST pass the result to `endScopedAccess(_)`
    ///   (use `defer`).
    private func beginScopedAccess(for urls: [URL]) -> [URL]? {
        var roots: [URL] = []
        var seen = Set<String>()
        for url in urls {
            guard let scoped = BookmarkStore.scopedRoot(containing: url) else {
                endScopedAccess(roots)
                return nil
            }
            if seen.insert(scoped.path).inserted {
                roots.append(scoped)
            } else {
                // Same bookmark as an earlier URL: balance this extra session
                // immediately so stop-calls stay paired with start-calls.
                scoped.stopAccessingSecurityScopedResource()
            }
        }
        return roots
    }

    private func endScopedAccess(_ roots: [URL]) {
        for root in roots {
            root.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: - Host app fallback

    /// No bookmark covers the target: launch the host app so the user can
    /// grant folder access there. We never fail silently — a menu item that
    /// does nothing is worse than one that opens the app.
    private func revealHostApp() {
        NSLog("[FinderFixSync] no bookmark covers target; launching host app")
        if !NSWorkspace.shared.launchApplication("FinderFix") {
            NSLog("[FinderFixSync] failed to launch host app")
        }
    }
}
