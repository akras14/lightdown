import AppKit

@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {
    var text = ""

    private var editorController: EditorSplitViewController? {
        windowControllers.first?.contentViewController as? EditorSplitViewController
    }

    override class var autosavesInPlace: Bool { true }

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

    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        guard let editor = editorController else { throw CocoaError(.featureUnsupported) }
        return editor.previewPrintOperation(printInfo: printInfo)
    }

    @IBAction func exportHTML(_ sender: Any?) {
        guard let window = windowControllers.first?.window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = (displayName as NSString).deletingPathExtension + ".html"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            let body = MarkdownRenderer.html(from: self.editorController?.currentText ?? self.text)
            do {
                try Self.standaloneHTML(title: self.displayName, body: body).write(to: url, atomically: true, encoding: .utf8)
            } catch {
                self.presentError(error)
            }
        }
    }

    static func standaloneHTML(title: String, body: String) -> String {
        func resource(_ name: String) -> String {
            guard let url = Bundle.main.url(forResource: name, withExtension: nil) else { return "" }
            return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        let escapedTitle = title
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escapedTitle)</title>
        <style>\(resource("preview.css"))</style>
        <style media="(prefers-color-scheme: light)">\(resource("hljs-light.css"))</style>
        <style media="(prefers-color-scheme: dark)">\(resource("hljs-dark.css"))</style>
        <script>\(resource("highlight.min.js"))</script>
        </head>
        <body>
        <article class="markdown-body">
        \(body)
        </article>
        <script>document.querySelectorAll('pre code').forEach(el => hljs.highlightElement(el));</script>
        </body>
        </html>
        """
    }
}
