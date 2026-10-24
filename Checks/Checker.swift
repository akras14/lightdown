import AppKit
import WebKit
@testable import LightdownKit

/// Minimal test runner: groups of named checks, failures reported with file and line.
@MainActor
final class Checker {
    private(set) var failures = 0
    private(set) var count = 0
    private var group = ""

    func group(_ name: String, _ body: @MainActor () -> Void) {
        group = name
        body()
    }

    func expect<T: Equatable>(_ actual: T, _ expected: T, _ label: String = "",
                              file: StaticString = #fileID, line: UInt = #line) {
        count += 1
        guard actual != expected else { return }
        failures += 1
        print("✘ \(group)\(label.isEmpty ? "" : " — \(label)") (\(file):\(line))")
        print("    got:      \(String(reflecting: actual))")
        print("    expected: \(String(reflecting: expected))")
    }
}

/// Text view in a window (so it has an undo manager). In the marked strings, `|` is the
/// caret and `«…»` is the selection.
@MainActor
final class TextHarness {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                          styleMask: [.titled], backing: .buffered, defer: true)
    let view = EditorTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))

    init(_ marked: String) {
        window.contentView = view
        view.allowsUndo = true
        set(marked)
    }

    /// Runs `body` as its own undo step, like a separate key press in the app:
    /// the undo manager closes its group when the run loop turns.
    func act(_ body: () -> Void) {
        body()
        RunLoop.current.run(mode: .default, before: Date())
    }

    func set(_ marked: String) {
        var text = marked
        var selection = NSRange(location: 0, length: 0)
        if let caret = text.range(of: "|") {
            selection.location = text.utf16.distance(from: text.startIndex, to: caret.lowerBound)
            text.removeSubrange(caret)
        } else if let open = text.range(of: "«"), let close = text.range(of: "»") {
            let start = text.utf16.distance(from: text.startIndex, to: open.lowerBound)
            let end = text.utf16.distance(from: text.startIndex, to: close.lowerBound) - 1
            text.removeSubrange(close)
            text.removeSubrange(open)
            selection = NSRange(location: start, length: end - start)
        }
        view.string = text
        view.setSelectedRange(selection)
    }

    var marked: String {
        let ns = view.string as NSString
        let r = view.selectedRange()
        if r.length == 0 { return ns.replacingCharacters(in: r, with: "|") }
        return ns.replacingCharacters(in: r, with: "«" + ns.substring(with: r) + "»")
    }
}

/// Spins the run loop until `condition` holds or the timeout passes.
@MainActor
@discardableResult
func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    return condition()
}

/// Runs JavaScript in the preview and waits for the result.
@MainActor
func evaluate(_ js: String, in webView: WKWebView) -> Any? {
    var result: Any?
    var done = false
    webView.evaluateJavaScript(js) { value, _ in result = value; done = true }
    waitUntil { done }
    return result
}

/// An open document with its editor and live preview, using the repo's preview page.
@MainActor
final class DocumentHarness {
    let directory: URL
    let url: URL
    let document: MarkdownDocument
    let editor: EditorSplitViewController

    init(_ text: String, name: String = "note.md") {
        let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources")
        AppResources.directory = resources

        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(name)
        try! text.write(to: url, atomically: true, encoding: .utf8)
        document = try! MarkdownDocument(contentsOf: url, ofType: "net.daringfireball.markdown")
        document.makeWindowControllers()
        editor = document.windowControllers.first!.contentViewController as! EditorSplitViewController
        editor.view.window?.setFrame(NSRect(x: 0, y: 0, width: 1000, height: 700), display: false)
    }

    var text: String { editor.textView.string }
    var webView: WKWebView { editor.webView }

    /// Waits for the preview to load and render the current text.
    func waitForPreview() -> Bool {
        waitUntil { self.editor.previewReady } &&
            waitUntil { (evaluate("document.getElementById('content').childElementCount", in: self.webView) as? Int ?? 0) > 0 }
    }

    func close() {
        document.close()
        try? FileManager.default.removeItem(at: directory)
    }
}
