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
        let editorPane = h.editor.splitViewItems[0].viewController.view
        let previewPane = h.editor.splitViewItems[1].viewController.view

        @MainActor func moveDivider(to x: CGFloat) -> CGFloat {
            split.setPosition(x, ofDividerAt: 0)
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

    // The status bar runs along the bottom of the whole window, under every pane.
    t.group("status bar spans the window") {
        let h = DocumentHarness("one two three\n")
        defer { h.close() }
        let window = h.editor.view.window!
        window.setFrame(NSRect(x: -5000, y: -5000, width: 1200, height: 760), display: true)
        let label = h.editor.wordCountLabel

        @MainActor func check(_ what: String) {
            window.contentView!.layoutSubtreeIfNeeded()
            let width = window.contentView!.bounds.width
            let frame = label.convert(label.bounds, to: nil)
            t.expect(abs(frame.minX - 12) < 4 && abs(frame.maxX - (width - 12)) < 4, true,
                     "\(what): label spans \(Int(frame.minX))…\(Int(frame.maxX)) of \(Int(width))")
            let split = h.editor.view.convert(h.editor.view.bounds, to: nil)
            t.expect(split.minY >= frame.maxY, true, "\(what): panes sit above the bar")
        }
        h.editor.splitView.setPosition(600, ofDividerAt: 0)
        check("both panes")
        h.editor.toggleOutline(nil)
        waitUntil(timeout: 0.5) { false }
        check("outline open")
        h.editor.toggleOutline(nil)
        h.editor.togglePreview(nil)
        waitUntil(timeout: 0.5) { false }
        check("preview hidden")
        h.editor.togglePreview(nil)
    }

    // Obsidian style: the outline opens on the right, taking its room from the preview.
    t.group("outline on the right") {
        let h = DocumentHarness("# One\n\ntext\n\n## Two\n")
        defer { h.close() }
        let window = h.editor.view.window!
        window.setFrame(NSRect(x: -5000, y: -5000, width: 1200, height: 760), display: true)
        let split = h.editor.splitView
        split.layoutSubtreeIfNeeded()
        @MainActor func frame(_ v: NSView) -> NSRect { v.convert(v.bounds, to: split) }
        let editor = h.editor.textView.enclosingScrollView!, preview = h.editor.webView!, outline = h.editor.outline.view
        let editorBefore = frame(editor)

        h.editor.toggleOutline(nil)
        defer { h.editor.toggleOutline(nil) }
        waitUntil(timeout: 0.6) { false }
        split.layoutSubtreeIfNeeded()
        t.expect(frame(editor).minX, 0, "editor still starts at the left edge")
        t.expect(abs(frame(outline).maxX - split.bounds.width) < 1, true, "outline ends at the right edge (\(frame(outline)))")
        t.expect(frame(outline).minX >= frame(preview).maxX, true, "outline is right of the preview")
        t.expect(abs(frame(editor).width - editorBefore.width) < 2, true,
                 "opening it doesn't squeeze the editor (\(Int(editorBefore.width)) → \(Int(frame(editor).width)))")
    }
}
