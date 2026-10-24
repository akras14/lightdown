import AppKit
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
