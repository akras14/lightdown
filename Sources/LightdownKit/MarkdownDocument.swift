import AppKit

@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {
    var text = ""

    private var editorController: EditorSplitViewController? {
        windowControllers.first?.contentViewController as? EditorSplitViewController
    }

    override class var autosavesInPlace: Bool { true }

    /// The editor's text if a window is open, else the last loaded text.
    var currentText: String { editorController?.currentText ?? text }

    override func makeWindowControllers() {
        let controller = EditorSplitViewController(document: self)
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 1200, height: 800))
        window.minSize = NSSize(width: 480, height: 300)
        window.tabbingMode = .preferred
        window.delegate = controller
        window.center()

        let windowController = NSWindowController(window: window)
        windowController.shouldCascadeWindows = true
        addWindowController(windowController)
    }

    override func data(ofType typeName: String) throws -> Data {
        if let editor = editorController { text = editor.currentText }
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
            guard response == .OK, let url = panel.url, let self else { return }
            let body = MarkdownRenderer.html(from: self.currentText)
            do {
                try Self.standaloneHTML(title: self.displayName, body: body).write(to: url, atomically: true, encoding: .utf8)
            } catch {
                self.presentError(error)
            }
        }
    }

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
        mermaid.initialize({ startOnLoad: false, theme: matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'default' });
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
        <script>document.querySelectorAll('pre code:not(.language-mermaid)').forEach(el => hljs.highlightElement(el));</script>
        \(mermaid)
        </body>
        </html>
        """
    }
}
