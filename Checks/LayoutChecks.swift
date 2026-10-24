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
        let editorBefore = frame(editor), previewBefore = frame(preview)

        h.editor.toggleOutline(nil)
        defer { h.editor.toggleOutline(nil) }
        waitUntil(timeout: 0.6) { false }
        split.layoutSubtreeIfNeeded()
        t.expect(frame(editor).minX, 0, "editor still starts at the left edge")
        t.expect(abs(frame(outline).maxX - split.bounds.width) < 1, true, "outline ends at the right edge (\(frame(outline)))")
        t.expect(frame(outline).minX >= frame(preview).maxX, true, "outline is right of the preview")
        let shareBefore = editorBefore.width / (editorBefore.width + previewBefore.width)
        let shareOpen = frame(editor).width / (frame(editor).width + frame(preview).width)
        t.expect(abs(shareOpen - shareBefore) < 0.01, true, "editor keeps its share of the space (\(shareBefore) → \(shareOpen))")
    }

    // Regression: opening and closing the outline left the preview narrower each time.
    t.group("outline round trip keeps the panes") {
        let h = DocumentHarness("# One\n")
        defer { h.close() }
        h.editor.view.window!.setFrame(NSRect(x: -5000, y: -5000, width: 1200, height: 760), display: true)
        let split = h.editor.splitView
        split.setPosition(500, ofDividerAt: 0)
        split.layoutSubtreeIfNeeded()
        let editor = h.editor.splitViewItems[0].viewController.view, preview = h.editor.splitViewItems[1].viewController.view
        let before = (editor.frame.width, preview.frame.width)
        for round in 1...3 {
            h.editor.toggleOutline(nil); waitUntil(timeout: 0.6) { false }
            h.editor.toggleOutline(nil); waitUntil(timeout: 0.6) { false }
            split.layoutSubtreeIfNeeded()
            t.expect(abs(editor.frame.width - before.0) < 2 && abs(preview.frame.width - before.1) < 2, true,
                     "round \(round): editor \(Int(before.0)) → \(Int(editor.frame.width)), preview \(Int(before.1)) → \(Int(preview.frame.width))")
        }
        // With the preview hidden, closing the outline gives the editor its room back.
        h.editor.togglePreview(nil); waitUntil(timeout: 0.6) { false }
        h.editor.toggleOutline(nil); waitUntil(timeout: 0.6) { false }
        h.editor.toggleOutline(nil); waitUntil(timeout: 0.6) { false }
        split.layoutSubtreeIfNeeded()
        t.expect(abs(split.arrangedSubviews[0].frame.width - split.bounds.width) < 2, true,
                 "preview hidden: editor fills the window (\(Int(split.arrangedSubviews[0].frame.width)))")
        h.editor.togglePreview(nil); waitUntil(timeout: 0.6) { false }
    }

    t.group("split evenly") {
        let h = DocumentHarness("# One\n")
        defer { h.close() }
        h.editor.view.window!.setFrame(NSRect(x: -5000, y: -5000, width: 1200, height: 760), display: true)
        let split = h.editor.splitView
        let editor = h.editor.splitViewItems[0].viewController.view, preview = h.editor.splitViewItems[1].viewController.view
        @MainActor func even(_ what: String) {
            waitUntil(timeout: 0.6) { false }
            split.layoutSubtreeIfNeeded()
            t.expect(abs(editor.frame.width - preview.frame.width) < 2, true,
                     "\(what): \(Int(editor.frame.width)) / \(Int(preview.frame.width))")
        }
        split.setPosition(300, ofDividerAt: 0)
        NSApp.sendAction(#selector(EditorSplitViewController.splitEvenly(_:)), to: h.editor, from: nil)
        even("menu command")
        split.setPosition(850, ofDividerAt: 0)
        h.editor.toggleOutline(nil)
        waitUntil(timeout: 0.6) { false }
        h.editor.splitEvenly(nil)
        even("with the outline open")
        h.editor.toggleOutline(nil)
        h.editor.togglePreview(nil)
        waitUntil(timeout: 0.6) { false }
        h.editor.splitEvenly(nil)
        t.expect(h.editor.splitViewItems[1].isCollapsed, false, "brings a hidden preview back")
        even("after hiding the preview")
        // Double-clicking the divider does the same (AppKit asks before collapsing on double-click).
        split.setPosition(300, ofDividerAt: 0)
        _ = h.editor.splitView(split, shouldCollapseSubview: editor, forDoubleClickOnDividerAt: 0)
        even("double-click on the divider")
        let item = MainMenu.build().items.lazy.compactMap { $0.submenu?.item(withTitle: "Split Evenly") }.first
        t.expect(item?.keyEquivalent, "0", "Split Evenly is ⌥⌘0")
        t.expect(item?.keyEquivalentModifierMask, [.command, .option])
    }

    // Regression: after Split Evenly, opening or closing the outline left the split uneven.
    t.group("outline keeps the editor / preview proportions") {
        let h = DocumentHarness("# One\n")
        defer { h.close() }
        let window = h.editor.view.window!
        window.setFrame(NSRect(x: -5000, y: -5000, width: 1400, height: 760), display: true)
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        let split = h.editor.splitView
        @MainActor func share() -> CGFloat {
            split.layoutSubtreeIfNeeded()
            let e = split.arrangedSubviews[0].frame.width, p = split.arrangedSubviews[1].frame.width
            return e / (e + p)
        }
        @MainActor func pct(_ x: CGFloat) -> String { "\(Int((x * 100).rounded()))%" }
        for start in [nil, 400.0, 900.0] as [CGFloat?] {
            if let start { split.setPosition(start, ofDividerAt: 0) } else { h.editor.splitEvenly(nil) }
            let before = share()
            h.editor.toggleOutline(nil); waitUntil(timeout: 0.3) { false }
            let open = share()
            h.editor.splitEvenly(nil)
            let evenOpen = share()
            h.editor.toggleOutline(nil); waitUntil(timeout: 0.3) { false }
            let closed = share()
            t.expect(abs(open - before) < 0.01, true, "\(start.map { "from \(Int($0))" } ?? "from even"): opening \(pct(before)) → \(pct(open))")
            t.expect(abs(closed - evenOpen) < 0.01 && abs(evenOpen - 0.5) < 0.01, true,
                     "\(start.map { "from \(Int($0))" } ?? "from even"): even with the outline open, then closing: \(pct(evenOpen)) → \(pct(closed))")
        }
    }
}
