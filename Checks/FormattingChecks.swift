import AppKit
@testable import LightdownKit

@MainActor
func formattingChecks(_ t: Checker) {
    func format(_ marked: String, _ style: InlineStyle) -> String {
        let h = TextHarness(marked)
        h.view.toggle(style)
        return h.marked
    }

    t.group("bold") {
        t.expect(format("say «hello» there", .bold), "say **«hello»** there", "wrap selection")
        t.expect(format("say **«hello»** there", .bold), "say «hello» there", "unwrap, markers outside")
        t.expect(format("say «**hello**» there", .bold), "say «hello» there", "unwrap, markers inside")
        t.expect(format("say hel|lo there", .bold), "say **hel|lo** there", "word at caret")
        t.expect(format("say **hel|lo** there", .bold), "say hel|lo there", "unwrap word at caret")
        t.expect(format("a | b", .bold), "a **|** b", "empty pair")
        t.expect(format("a **|** b", .bold), "a | b", "remove empty pair")
        t.expect(format("«hello »world", .bold), "**«hello»** world", "trailing space stays outside")
    }

    t.group("italic and combinations") {
        t.expect(format("«x»", .italic), "*«x»*")
        t.expect(format("*«x»*", .italic), "«x»", "unwrap")
        t.expect(format("**«x»**", .italic), "***«x»***", "italic on bold")
        t.expect(format("***«x»***", .italic), "**«x»**", "italic off bold+italic")
        t.expect(format("***«x»***", .bold), "*«x»*", "bold off bold+italic")
        t.expect(format("*«x»*", .bold), "***«x»***", "bold on italic")
    }

    t.group("code and strikethrough") {
        t.expect(format("run «ls» now", .code), "run `«ls»` now")
        t.expect(format("run `l|s` now", .code), "run l|s now", "unwrap at caret")
        t.expect(format("«gone»", .strikethrough), "~~«gone»~~")
        t.expect(format("~~«gone»~~", .strikethrough), "«gone»")
    }

    t.group("link") {
        @MainActor func link(_ marked: String, clipboard: String? = nil) -> String {
            let pasteboard = NSPasteboard(name: .init("LightdownChecks"))
            pasteboard.clearContents()
            if let clipboard { pasteboard.setString(clipboard, forType: .string) }
            EditorTextView.linkPasteboard = pasteboard
            defer { EditorTextView.linkPasteboard = .general; pasteboard.releaseGlobally() }
            let h = TextHarness(marked)
            h.view.formatLink(nil)
            return h.marked
        }
        t.expect(link("see «docs» here"), "see [docs](|) here", "text")
        t.expect(link("«https://x.com»"), "[|](https://x.com)", "url")
        t.expect(link("a | b"), "a [|]() b", "empty")
        t.expect(link("see «docs»", clipboard: "https://example.com"), "see [docs](https://example.com)|", "copied url")
    }

    t.group("format undo") {
        let h = TextHarness("«word»")
        h.act { h.view.toggle(.bold) }
        t.expect(h.view.undoManager?.undoActionName, "Bold")
        h.view.undoManager?.undo()
        t.expect(h.view.string, "word")
    }
}
