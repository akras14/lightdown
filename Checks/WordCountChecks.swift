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
        let window = h.editor.view.window!
        t.expect(waitUntil { window.subtitle == "4 words" }, true, "window subtitle (got \(window.subtitle))")
        h.editor.textView.setSelectedRange(NSRange(location: 0, length: 7))
        t.expect(window.subtitle, "2 of 4 words", "selection")
    }
}
