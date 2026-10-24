import AppKit
@testable import LightdownKit

@MainActor
func reloadChecks(_ t: Checker) {
    func replace(_ old: String, _ new: String, caret: Int) -> (String, Int) {
        let h = TextHarness(old)
        h.view.setSelectedRange(NSRange(location: caret, length: 0))
        h.view.textStorage!.replaceChangedRange(with: new)
        return (h.view.string, h.view.selectedRange().location)
    }

    t.group("minimal replace") {
        t.expect(replace("aaa\nbbb\nccc", "aaa\nBBB\nccc", caret: 10).1, 10, "caret after change stays")
        t.expect(replace("aaa\nbbb\nccc", "xx\naaa\nbbb\nccc", caret: 5).1, 8, "caret shifts by insertion")
        t.expect(replace("hello", "", caret: 0).0, "", "clear")
        t.expect(replace("", "new", caret: 0).0, "new", "from empty")
        t.expect(replace("a😀b", "a😃b", caret: 0).0, "a😃b", "emoji (surrogate pairs)")
        t.expect(replace("abab", "ab", caret: 0).0, "ab", "repeated text")
    }

    t.group("reload from disk") {
        let h = DocumentHarness("# Title\n\nfirst line\nsecond line\n")
        defer { h.close() }
        let doc = h.document, url = h.url
        let view = h.editor.textView!
        t.expect(view.string, "# Title\n\nfirst line\nsecond line\n", "opened")
        view.setSelectedRange(NSRange(location: 25, length: 0)) // inside "second line"

        // Another app rewrites the first line.
        try! "# New title\n\nfirst line\nsecond line\n".write(to: url, atomically: true, encoding: .utf8)
        try! FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: url.path)
        doc.reloadIfChangedOnDisk()
        t.expect(view.string, "# New title\n\nfirst line\nsecond line\n", "reloaded")
        t.expect(view.selectedRange().location, 29, "caret follows its text")
        t.expect(doc.isDocumentEdited, false, "not marked edited")

        // Unchanged modification date: nothing happens.
        view.string = "local"
        doc.reloadIfChangedOnDisk()
        t.expect(view.string, "local", "no reload without a newer file")
    }
}
