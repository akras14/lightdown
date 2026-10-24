import AppKit

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
