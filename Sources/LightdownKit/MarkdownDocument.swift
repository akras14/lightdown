import AppKit

@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {
    var text = ""

    private var editorController: EditorSplitViewController? {
        (windowControllers.first?.contentViewController as? DocumentViewController)?.editor
    }

    override class var autosavesInPlace: Bool { true }

    /// Save this long after typing stops. Left to itself, macOS autosaves about 15 s after the first
    /// edit, so tools reading the file (git, Claude Code) saw stale text and their edits often
    /// collided with unsaved ones. Raise it to make the reload-or-keep prompt easy to trigger by hand.
    static var saveDelay: TimeInterval = 1
    private var saveWorkItem: DispatchWorkItem?

    /// Called on every edit: saves once typing pauses.
    func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDelay, execute: item)
    }

    /// Saves pending edits to the file. Untitled documents are left to macOS, and nothing is written
    /// while asking about a change from another app.
    @objc func saveNow() {
        saveWorkItem?.cancel()
        guard fileURL != nil, isDocumentEdited, !isAskingAboutExternalChange else { return }
        autosave(withImplicitCancellability: false) { _ in }
    }

    /// The editor's text if a window is open, else the last loaded text.
    var currentText: String { editorController?.currentText ?? text }

    override func makeWindowControllers() {
        let content = DocumentViewController(document: self)
        let window = NSWindow(contentViewController: content)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 1200, height: 800))
        window.minSize = NSSize(width: 480, height: 300)
        window.tabbingMode = .preferred
        window.delegate = content.editor
        window.center()

        let windowController = NSWindowController(window: window)
        windowController.shouldCascadeWindows = true
        addWindowController(windowController)
        // Switching apps, usually to run git or Claude Code on this file, saves right away.
        NotificationCenter.default.addObserver(self, selector: #selector(saveNow),
                                               name: NSApplication.didResignActiveNotification, object: nil)
        DispatchQueue.main.async { Session.saveOpenDocuments() }   // after the controller registers it
    }

    /// A blank Untitled document nobody has typed into: safe to close without asking.
    var isEmptyUntitled: Bool {
        fileURL == nil && currentText.isEmpty
    }

    override func close() {
        super.close()
        Session.saveOpenDocuments()
    }

    override func data(ofType typeName: String) throws -> Data {
        if let editor = editorController {
            // Typing coalesces into one undo step, and the document counts changes by undo steps:
            // without a break, typing that continues a word after a save wouldn't mark it edited.
            editor.textView.breakUndoCoalescing()
            text = editor.currentText
        }
        return Data(text.utf8)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        text = String(decoding: data, as: UTF8.self)
        editorController?.reloadFromDocument()
    }

    // MARK: External changes

    override func presentedItemDidChange() {
        super.presentedItemDidChange()
        DispatchQueue.main.async { self.reloadIfChangedOnDisk() }
    }

    /// Picks up edits made by other apps (git, Claude Code, another editor).
    /// Reloads silently unless there are unsaved changes here too, in which case it asks.
    func reloadIfChangedOnDisk() {
        guard let url = fileURL, let type = fileType,
              // Read fresh attributes: URL resource values are cached and would hide the change.
              let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
              modified > (fileModificationDate ?? .distantPast),
              !isAskingAboutExternalChange else { return }

        guard isDocumentEdited, let window = windowControllers.first?.window else {
            do { try revert(toContentsOf: url, ofType: type) } catch { NSLog("Lightdown: reload failed: \(error)") }
            return
        }

        isAskingAboutExternalChange = true
        let alert = NSAlert()
        alert.messageText = "“\(displayName ?? url.lastPathComponent)” was changed by another app."
        alert.informativeText = "You also have unsaved changes here. Reload the version on disk, or keep yours and overwrite it?"
        alert.addButton(withTitle: "Reload from Disk")
        alert.addButton(withTitle: "Keep My Version")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.isAskingAboutExternalChange = false
            if response == .alertFirstButtonReturn {
                try? self.revert(toContentsOf: url, ofType: type)
            } else {
                // Treat the disk version as seen so the next save overwrites it without another warning.
                self.fileModificationDate = modified
                self.autosave(withImplicitCancellability: false) { _ in }
            }
        }
    }

    private var isAskingAboutExternalChange = false
    var printCompletion: ((Bool) -> Void)?

    @IBAction func exportHTML(_ sender: Any?) {
        guard let window = windowControllers.first?.window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = (displayName as NSString).deletingPathExtension + ".html"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.exportHTML(to: url)
        }
    }

    func exportHTML(to url: URL) {
        let body = MarkdownRenderer.html(from: currentText)
        do {
            try Self.standaloneHTML(title: displayName, body: body).write(to: url, atomically: true, encoding: .utf8)
            Self.revealInFinder(url)
        } catch {
            presentErrorSheet(error)
        }
    }

    /// On the document's window when it has one, so it doesn't block other documents.
    private func presentErrorSheet(_ error: Error) {
        if let window = windowControllers.first?.window {
            presentError(error, modalFor: window, delegate: nil, didPresent: nil, contextInfo: nil)
        } else {
            presentError(error)
        }
    }

    // MARK: Move To…

    /// On macOS 26 the system Move To… popover fails to start in apps that aren't sandboxed
    /// ("Cannot display the move panel", ViewBridge error 14), so pick the new place with a save
    /// panel, like Export does, and move the file from there.
    override func move(_ sender: Any?) {
        guard let current = fileURL, let window = windowControllers.first?.window else {
            return saveAs(sender)   // never saved: choosing a place is saving
        }
        let panel = NSSavePanel()
        panel.title = "Move To"
        panel.prompt = "Move"
        panel.nameFieldStringValue = current.lastPathComponent
        panel.directoryURL = current.deletingLastPathComponent()
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.moveFile(to: url)
        }
    }

    /// Moves the file to `url`, replacing a file already there (the save panel has asked by then).
    func moveFile(to url: URL, completion: @escaping () -> Void = {}) {
        guard let current = fileURL, url.standardizedFileURL != current.standardizedFileURL else { return completion() }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            presentErrorSheet(error)
            return completion()
        }
        move(to: url) { [weak self] error in
            if let error { self?.presentErrorSheet(error) }
            completion()
        }
    }

    /// Moves and renames (including from the title bar) change the path to reopen next launch.
    override var fileURL: URL? {
        didSet { if oldValue != nil, oldValue != fileURL { Session.saveOpenDocuments() } }
    }

    /// Shows an exported file in Finder. Replaceable so the checks don't open Finder windows.
    static var revealInFinder: (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }

    /// A self-contained HTML page with the preview's styles. `baseURL` resolves relative image paths.
    static func standaloneHTML(title: String, body: String, baseURL: URL? = nil) -> String {
        func resource(_ name: String) -> String { AppResources.text(name) }
        let base = baseURL.map { "<base href=\"\($0.absoluteString)\">" } ?? ""
        let escapedTitle = title
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
        // Only embed Mermaid (~2.7 MB) when the document actually has a diagram.
        let mermaid = body.contains("class=\"language-mermaid\"") ? """
        <script>\(resource("mermaid.min.js"))</script>
        <script>
        mermaid.initialize({ startOnLoad: false, theme: matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'default',
                             flowchart: { diagramPadding: 48 } });
        document.querySelectorAll('pre > code.language-mermaid').forEach(code => {
          const div = document.createElement('div');
          div.className = 'mermaid';
          div.textContent = code.textContent;
          code.parentElement.replaceWith(div);
        });
        mermaid.run();
        </script>
        """ : ""
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escapedTitle)</title>
        \(base)
        <style>\(resource("preview.css"))</style>
        <style media="(prefers-color-scheme: light)">\(resource("hljs-light.css"))</style>
        <style media="(prefers-color-scheme: dark)">\(resource("hljs-dark.css"))</style>
        <script>\(resource("highlight.min.js"))</script>
        </head>
        <body>
        <article class="markdown-body">
        \(body)
        </article>
        <script>\(resource("headings.js"))</script>
        <script>
        ldAddHeadingIds(document.body);
        document.querySelectorAll('pre code:not(.language-mermaid)').forEach(el => hljs.highlightElement(el));
        </script>
        \(mermaid)
        </body>
        </html>
        """
    }
}
