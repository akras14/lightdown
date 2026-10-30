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

    // The real path: keystrokes, saves, and another process changing the file (like `echo >>`).
    @MainActor func session(_ text: String, _ body: (DocumentHarness, NSWindow) -> Void) {
        let h = DocumentHarness(text)
        defer { h.close() }
        let window = h.editor.view.window!
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(h.editor.textView)
        h.editor.textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        body(h, window)
        if let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .alertSecondButtonReturn) }
        window.orderOut(nil)
    }
    @MainActor func save(_ h: DocumentHarness) -> Bool {
        var done = false
        h.document.autosave(withImplicitCancellability: false) { _ in done = true }
        return waitUntil { done } && !h.document.isDocumentEdited
    }
    @MainActor func shell(_ command: String, in h: DocumentHarness) {
        // A different modification time even within the same second as our own save.
        Thread.sleep(forTimeInterval: 1.1)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", command]
        p.currentDirectoryURL = h.directory
        try! p.run(); p.waitUntilExit()
    }
    @MainActor func disk(_ h: DocumentHarness) -> String { (try? String(contentsOf: h.url, encoding: .utf8)) ?? "" }
    @MainActor func alertButton(_ title: String, in window: NSWindow) -> NSButton? {
        func find(_ v: NSView) -> NSButton? {
            if let b = v as? NSButton, b.title == title { return b }
            return v.subviews.lazy.compactMap(find).first
        }
        return window.attachedSheet?.contentView.flatMap(find)
    }

    // Regression: typing that continued a word right after a save wasn't counted as a change, so a
    // reload from disk silently dropped it (and quitting wouldn't save it).
    t.group("typing right after a save is unsaved") {
        session("# Notes\n") { h, window in
            type("abc", in: window)
            t.expect(save(h), true, "saved")
            type("yy", in: window)
            t.expect(h.document.isDocumentEdited, true, "edited after typing on")
            t.expect(save(h), true, "saved again")
            t.expect(disk(h), "# Notes\nabcyy", "both saves reach the disk")
        }
    }

    t.group("change from another app") {
        // Conflicts need unsaved edits when the change lands, so hold off the quick save.
        MarkdownDocument.saveDelay = 60
        defer { MarkdownDocument.saveDelay = 1 }
        // No unsaved edits: reload quietly.
        session("# Notes\n") { h, window in
            shell("echo '- added' >> note.md", in: h)
            t.expect(waitUntil { h.text == "# Notes\n- added\n" }, true, "reloaded (got \(h.text.debugDescription))")
            t.expect(window.attachedSheet == nil, true, "without asking")
        }
        // Unsaved edits: ask, and keep them until the user chooses.
        session("# Notes\n") { h, window in
            type("mine", in: window)
            shell("echo '- added' >> note.md", in: h)
            t.expect(waitUntil { alertButton("Keep My Version", in: window) != nil }, true, "asks")
            t.expect(h.text, "# Notes\nmine", "your edits stay while it asks")
            alertButton("Keep My Version", in: window)?.performClick(nil)
            t.expect(waitUntil { disk(h) == "# Notes\nmine" }, true, "keep: your version is saved (disk \(disk(h).debugDescription))")
        }
        session("# Notes\n") { h, window in
            type("mine", in: window)
            shell("echo '- added' >> note.md", in: h)
            t.expect(waitUntil { alertButton("Reload from Disk", in: window) != nil }, true, "asks")
            alertButton("Reload from Disk", in: window)?.performClick(nil)
            t.expect(waitUntil { h.text == "# Notes\n- added\n" }, true, "reload: shows the disk version")
            t.expect(h.document.isDocumentEdited, false, "reload: nothing unsaved")
        }
        // Typing on right after a save, then a change arrives: ask rather than drop the typing.
        session("# Notes\n") { h, window in
            type("abc", in: window)
            t.expect(save(h), true, "saved")
            type("yy", in: window)
            shell("echo '- added' >> note.md", in: h)
            t.expect(waitUntil(timeout: 4) { alertButton("Keep My Version", in: window) != nil }, true, "asks after typing on")
            t.expect(h.text, "# Notes\nabcyy", "typing kept (got \(h.text.debugDescription))")
        }
    }

    // Saving a moment after typing stops (rather than macOS's ~15 s) keeps the file current for
    // other tools and makes conflicts rare.
    t.group("quick save") {
        session("# Notes\n") { h, window in
            type("abc", in: window)
            t.expect(disk(h), "# Notes\n", "not saved mid-typing")
            t.expect(waitUntil(timeout: 3) { disk(h) == "# Notes\nabc" }, true, "saved soon after typing stops")
            t.expect(h.document.isDocumentEdited, false, "clean after the save")

            // Typing nonstop holds the save off until the pause.
            let start = Date()
            while Date().timeIntervalSince(start) < 2 { type("x", in: window) }
            t.expect(disk(h), "# Notes\nabc", "no save while typing nonstop")
            t.expect(waitUntil(timeout: 3) { disk(h).hasSuffix("x") }, true, "saved after the pause")
        }
        // Switching to another app (to run git or Claude Code) saves right away.
        MarkdownDocument.saveDelay = 60
        defer { MarkdownDocument.saveDelay = 1 }
        session("# Notes\n") { h, window in
            type("abc", in: window)
            NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
            t.expect(waitUntil(timeout: 1) { disk(h) == "# Notes\nabc" }, true, "saved on switching apps")
        }
        // Untitled documents are left to macOS (there's no file to save to).
        MarkdownDocument.saveDelay = 1
        let doc = MarkdownDocument()
        doc.makeWindowControllers()
        defer { doc.close() }
        let content = doc.windowControllers.first!.contentViewController as! DocumentViewController
        content.editor.textView.insertText("draft", replacementRange: NSRange(location: 0, length: 0))
        t.expect(waitUntil { doc.isDocumentEdited }, true, "marked edited")
        doc.saveNow()   // what the delayed save runs
        t.expect(doc.fileURL, nil, "untitled stays untitled")
        t.expect(doc.isDocumentEdited, true, "still unsaved")
    }
}
