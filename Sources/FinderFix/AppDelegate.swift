import AppKit
import SwiftUI

/// Draws the menu-bar icon in code: a simple folder glyph rendered as a template
/// image (no asset catalog needed). Template images are tinted by the system.
private func makeStatusIcon() -> NSImage {
    let size = NSSize(width: 18, height: 18)
    let image = NSImage(size: size)
    image.lockFocus()
    defer { image.unlockFocus() }

    NSColor.black.setFill()

    // Folder tab.
    let tab = NSBezierPath(roundedRect: NSRect(x: 2, y: 11, width: 7, height: 4), xRadius: 1.5, yRadius: 1.5)
    tab.fill()
    // Folder body.
    let body = NSBezierPath(roundedRect: NSRect(x: 2, y: 3, width: 14, height: 10), xRadius: 2, yRadius: 2)
    body.fill()

    image.isTemplate = true
    return image
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        HotKeyManager.shared.start()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleToggleHiddenFilesNotification(_:)),
            name: AppGroup.toggleHiddenFilesNotification,
            object: nil
        )

        // First-launch onboarding: show the 2-step window once, when the user
        // hasn't granted any folder access yet.
        let launchedKey = "ff.hasLaunchedBefore"
        if !UserDefaults.standard.bool(forKey: launchedKey) {
            UserDefaults.standard.set(true, forKey: launchedKey)
            if BookmarkStore.bookmarkedPaths().isEmpty {
                OnboardingWindow.show(initialStep: 0)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.stop()
        DistributedNotificationCenter.default().removeObserver(self)
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = makeStatusIcon()
        item.button?.toolTip = "FinderFix"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Grant Folder Access…", action: #selector(showFolderOnboarding), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "How to Enable the Finder Extension", action: #selector(showExtensionGuide), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit FinderFix", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        for menuItem in menu.items {
            if menuItem.action == #selector(NSApplication.terminate(_:)) {
                menuItem.target = NSApplication.shared
            } else {
                menuItem.target = self
            }
        }
        item.menu = menu
        statusItem = item
    }

    // MARK: - Menu actions

    @objc private func showSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "FinderFix Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 560, height: 520))
        window.center()
        window.isReleasedWhenClosed = false
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Opens the onboarding window directly at the folder-grant step.
    @objc private func showFolderOnboarding() {
        OnboardingWindow.show(initialStep: 1)
    }

    /// Opens the onboarding window at the extension-enable guide step.
    @objc private func showExtensionGuide() {
        OnboardingWindow.show(initialStep: 0)
    }

    // MARK: - Hidden-files toggle (from the Finder Sync extension)

    /// The Finder Sync extension cannot toggle hidden files itself (sandboxed
    /// extensions can't write Finder's defaults), so it posts a distributed
    /// notification and the host app performs the toggle via Apple Events.
    @objc private func handleToggleHiddenFilesNotification(_ notification: Notification) {
        let succeeded = FinderBridge.toggleHiddenFiles()
        if !succeeded {
            // Graceful fallback: show the guide with the manual instructions
            // instead of failing silently.
            OnboardingWindow.show(initialStep: 0, showHiddenFilesHelp: true)
        }
    }
}
