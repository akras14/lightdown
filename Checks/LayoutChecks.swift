import AppKit
@testable import LightdownKit

/// Regression: the status bar's label pinned the editor to its minimum width, so the divider
/// between editor and preview couldn't be dragged.
@MainActor
func layoutChecks(_ t: Checker) {
    t.group("editor / preview divider") {
        let h = DocumentHarness("one two three\n")
        defer { h.close() }
        let split = h.editor.splitView
        h.editor.view.window!.setFrame(NSRect(x: -5000, y: -5000, width: 1200, height: 760), display: true)
        split.layoutSubtreeIfNeeded()
        let editorPane = h.editor.splitViewItems[1].viewController.view
        let previewPane = h.editor.splitViewItems[2].viewController.view

        @MainActor func moveDivider(to x: CGFloat) -> CGFloat {
            split.setPosition(x, ofDividerAt: 1)
            split.layoutSubtreeIfNeeded()
            return editorPane.convert(editorPane.bounds, to: split).maxX
        }
        t.expect(editorPane.frame.width > 250, true, "editor isn't squeezed to its minimum (\(editorPane.frame.width))")
        t.expect(abs(moveDivider(to: 300) - 300) < 2, true, "divider moves left")
        t.expect(abs(moveDivider(to: 800) - 800) < 2, true, "divider moves right")
        t.expect(previewPane.frame.width > 300, true, "preview takes the rest")

        // A longer word count doesn't push the divider.
        h.editor.textView.insertText(String(repeating: "word ", count: 5000), replacementRange: NSRange(location: 0, length: 0))
        t.expect(waitUntil { h.editor.wordCountLabel.stringValue.hasPrefix("5,003") }, true, "count updated")
        split.layoutSubtreeIfNeeded()
        t.expect(abs(editorPane.convert(editorPane.bounds, to: split).maxX - 800) < 2, true, "divider stays put")

        // Same with the outline open.
        h.editor.toggleOutline(nil)
        defer { h.editor.toggleOutline(nil) }
        waitUntil(timeout: 0.5) { false }
        split.layoutSubtreeIfNeeded()
        t.expect(abs(moveDivider(to: 700) - 700) < 2, true, "divider moves with the outline open")
    }
}
