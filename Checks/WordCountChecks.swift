import AppKit
@testable import LightdownKit

@MainActor
func wordCountChecks(_ t: Checker) {
    t.group("word count") {
        t.expect(WordCount.count(in: "# Title\n\n- [ ] buy milk\n- **bold** move"), 5, "Markdown symbols ignored")
        t.expect(WordCount.count(in: "don't stop — it's fine"), 4, "contractions are one word")
        t.expect(WordCount.count(in: ""), 0)
        t.expect(WordCount.label(1), "1 word")
        t.expect(WordCount.label(1234), "1,234 words")
        t.expect(WordCount.label(3, of: 1234), "3 of 1,234 words")

        let h = DocumentHarness("one two three four\n")
        defer { h.close() }
        let label = h.editor.wordCountLabel
        t.expect(waitUntil { label.stringValue == "4 words" }, true, "status bar (got \(label.stringValue))")
        h.editor.textView.setSelectedRange(NSRange(location: 0, length: 7))
        t.expect(label.stringValue, "2 of 4 words", "selection")

        // Typing updates the count.
        h.editor.textView.setSelectedRange(NSRange(location: (h.text as NSString).length, length: 0))
        h.editor.textView.insertText("five six", replacementRange: h.editor.textView.selectedRange())
        t.expect(waitUntil { label.stringValue == "6 words" }, true, "typing updates it (got \(label.stringValue))")
    }
}
