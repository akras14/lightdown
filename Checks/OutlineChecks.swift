import AppKit
@testable import LightdownKit

@MainActor
func outlineChecks(_ t: Checker) {
    t.group("outline parsing") {
        let text = """
        # Title

        Intro **text**.

        ## Setup ##

        ```sh
        # not a heading
        ```

        Setext One
        ==========

        Setext *Two*
        ---

        - list item
        ---

        ### [Linked](https://x.com) `code`
        #hashtag
        """
        let headings = OutlineParser.headings(in: text)
        t.expect(headings.map(\.title), ["Title", "Setup", "Setext One", "Setext Two", "Linked code"])
        t.expect(headings.map(\.level), [1, 2, 1, 2, 3])
        t.expect(headings.map(\.line), [1, 5, 11, 14, 20])
    }

    t.group("outline sidebar") {
        let filler = (1...60).map { "Paragraph \($0)." }.joined(separator: "\n\n")
        let h = DocumentHarness("# One\n\n\(filler)\n\n## Two\n\n\(filler)\n\n## Three\n\n\(filler)\n")
        defer { h.close() }
        let editor = h.editor
        let outline = editor.outline
        t.expect(outline.headings.map(\.title), ["One", "Two", "Three"], "lists headings")

        editor.toggleOutline(nil)
        defer { editor.toggleOutline(nil) }   // restore the saved preference

        let two = outline.headings[1]
        outline.select(row: 1)
        t.expect(abs(editor.textView.topVisibleLine() - Double(two.line)) < 0.5, true,
                 "selecting a heading scrolls the editor (top \(editor.textView.topVisibleLine()), heading \(two.line))")
        t.expect(editor.textView.selectedRange().location, editor.textView.lineIndex.range(ofLine: two.line - 1).location,
                 "caret on the heading")

        editor.textView.scrollToLine(Double(outline.headings[2].line) + 10)
        t.expect(outline.selectedRow, 2, "scrolling highlights the current section")

        editor.textView.string += "\n## Four\n"
        editor.textView.didChangeText()
        t.expect(waitUntil { outline.headings.count == 4 }, true, "updates as you type")
    }
}
