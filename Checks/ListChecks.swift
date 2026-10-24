@testable import LightdownKit

@MainActor
func listChecks(_ t: Checker) {
    func ret(_ marked: String) -> String {
        let h = TextHarness(marked)
        if !h.view.continueList() { h.view.insertNewline(nil) }
        return h.marked
    }
    func tab(_ marked: String, indent: Bool = true) -> String {
        let h = TextHarness(marked)
        if indent { h.view.insertTab(nil) } else { h.view.insertBacktab(nil) }
        return h.marked
    }

    t.group("return in lists") {
        t.expect(ret("- one|"), "- one\n- |", "bullet")
        t.expect(ret("  * one|"), "  * one\n  * |", "indented star")
        t.expect(ret("1. one|"), "1. one\n2. |", "numbered")
        t.expect(ret("1. one|\n2. two\n3. three"), "1. one\n2. |\n3. two\n4. three", "renumbers the rest")
        t.expect(ret("1. a\n1. b|\n1. c"), "1. a\n1. b\n1. |\n1. c", "lazy numbering kept")
        t.expect(ret("- [x] done|"), "- [x] done\n- [ ] |", "task")
        t.expect(ret("- |"), "|", "empty top-level item ends list")
        t.expect(ret("- a\n  - |"), "- a\n- |", "empty nested item outdents")
        t.expect(ret("plain|"), "plain\n|", "not a list")
        t.expect(ret("* * *|"), "* * *\n|", "thematic break")
        t.expect(ret("|- item"), "\n|- item", "caret before marker")
    }

    t.group("tab in lists") {
        t.expect(tab("- a\n- |b"), "- a\n  - |b", "indent bullet")
        t.expect(tab("1. a\n2. |b\n3. c"), "1. a\n   1. |b\n2. c", "indent numbered, both lists renumber")
        t.expect(tab("- a\n- |b\n  - b1\n- c"), "- a\n  - |b\n    - b1\n- c", "children come along")
        t.expect(tab("- a\n  - |b", indent: false), "- a\n- |b", "outdent")
        t.expect(tab("- a\n    - |b", indent: false), "- a\n- |b", "outdent to parent level")
        t.expect(tab("- |a", indent: false), "- |a", "top level stays")
        t.expect(tab("- «a\n- b»\n- c"), "  - «a\n  - b»\n- c", "selection")
        t.expect(tab("plain|"), "plain\t|", "plain text gets a tab")
    }

    t.group("renumber") {
        t.expect(ListEditing.renumber(["1. a", "5. b", "2. c"], around: 1), ["1. a", "2. b", "3. c"])
        t.expect(ListEditing.renumber(["3. a", "1. b"], around: 0), ["3. a", "4. b"], "starts from first number")
        t.expect(ListEditing.renumber(["1. a", "   - x", "1. b"], around: 0), ["1. a", "   - x", "2. b"], "skips children")
        t.expect(ListEditing.renumber(["1. a", "", "1. b"], around: 0), ["1. a", "", "1. b"], "blank line ends list")
    }

    t.group("list undo") {
        let h = TextHarness("- a\n- |b")
        h.act { h.view.insertTab(nil) }
        t.expect(h.view.undoManager?.undoActionName, "Indent")
        h.view.undoManager?.undo()
        t.expect(h.view.string, "- a\n- b")
    }
}
