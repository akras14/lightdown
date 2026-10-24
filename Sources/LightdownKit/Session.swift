import AppKit

/// File > Open Recent, filled from NSDocumentController's recent documents each time it opens.
final class RecentDocumentsMenu: NSObject, NSMenuDelegate {
    static let shared = RecentDocumentsMenu()

    /// The URLs to list; tests substitute their own.
    var recentURLs: () -> [URL] = { NSDocumentController.shared.recentDocumentURLs }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let urls = recentURLs()
        let names = urls.map(\.lastPathComponent)
        for url in urls {
            // Same file name in two folders: add the folder so they can be told apart.
            let duplicate = names.filter { $0 == url.lastPathComponent }.count > 1
            let title = duplicate ? "\(url.lastPathComponent) — \(url.deletingLastPathComponent().lastPathComponent)"
                                  : url.lastPathComponent
            let item = NSMenuItem(title: title, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.toolTip = url.path
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }
        if !urls.isEmpty { menu.addItem(.separator()) }
        let clear = NSMenuItem(title: "Clear Menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)),
                               keyEquivalent: "")
        menu.addItem(clear)
    }

    @objc func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
    }
}

/// Reopens the documents that were open when Lightdown quit. macOS only restores windows when
/// "Close windows when quitting an application" is off (it's on by default), so Lightdown keeps
/// its own list. It's saved whenever documents open or close rather than only at quit, since a
/// logout can end the app without a quit; once quitting starts it's frozen, because the windows
/// closing during quit would otherwise empty it.
enum Session {
    private static let key = "openDocuments"
    static var isTerminating = false

    static func saveOpenDocuments() {
        guard !isTerminating else { return }
        let paths = NSDocumentController.shared.documents.compactMap { $0.fileURL?.path }
        UserDefaults.standard.set(paths, forKey: key)
    }

    /// Saved documents that still exist on disk.
    static func documentsToRestore() -> [URL] {
        (UserDefaults.standard.stringArray(forKey: key) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    /// Reopens the saved documents. Returns how many it's reopening.
    @discardableResult
    static func restoreOpenDocuments() -> Int {
        let urls = documentsToRestore()
        for url in urls {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        }
        return urls.count
    }
}
