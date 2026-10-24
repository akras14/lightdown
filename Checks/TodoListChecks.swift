@testable import LightdownKit

@MainActor
func todoListChecks(_ t: Checker) {
    t.group("todo toggle") {
        let cases = [
            ("buy milk", "- [ ] buy milk"),
            ("- [ ] buy milk", "- [x] buy milk"),
            ("- [X] buy milk", "- [ ] buy milk"),
            ("  * item", "  * [ ] item"),
            ("3. item", "3. [ ] item"),
            ("", "- [ ] "),
            ("- [ ]", "- [x] "),
            ("- [x]text", "- [ ] [x]text"),
            ("1.5 apples", "- [ ] 1.5 apples"),
        ]
        for (input, expected) in cases {
            t.expect(TodoList.toggle([input]), [expected], input)
        }
        t.expect(TodoList.toggle(["a", "", "- [x] b", "- [ ] c"]), ["- [ ] a", "", "- [ ] b", "- [ ] c"])
        t.expect(TodoList.toggle(["- [ ] a", "b", "- [x] c"]), ["- [x] a", "- [x] b", "- [x] c"])
    }

    t.group("todo editing") {
        let h = TextHarness("hello\nwo|rld\n")
        h.act { h.view.toggleTodo(nil) }
        t.expect(h.marked, "hello\n- [ ] wo|rld\n")
        h.act { h.view.toggleTodo(nil) }
        t.expect(h.marked, "hello\n- [x] wo|rld\n")
        h.view.undoManager?.undo()
        t.expect(h.view.string, "hello\n- [ ] world\n", "undo")

        h.set("«a\nb\n»c")
        h.view.toggleTodo(nil)
        t.expect(h.view.string, "- [ ] a\n- [ ] b\nc", "selection ending at line start")

        h.set("|")
        h.view.toggleTodo(nil)
        t.expect(h.marked, "- [ ] |", "empty document")
    }

    t.group("todo return") {
        let h = TextHarness("- [x] one|")
        t.expect(h.view.continueTodoList(), true)
        t.expect(h.marked, "- [x] one\n- [ ] |")
        t.expect(h.view.continueTodoList(), true)
        t.expect(h.marked, "- [x] one\n|", "empty item ends list")

        h.set("- [ ] foo|bar")
        _ = h.view.continueTodoList()
        t.expect(h.marked, "- [ ] foo\n- [ ] |bar", "split")

        h.set("  2. [ ] two|")
        _ = h.view.continueTodoList()
        t.expect(h.marked, "  2. [ ] two\n  3. [ ] |", "numbered")

        h.set("- [ ] |foo")
        _ = h.view.continueTodoList()
        t.expect(h.view.string, "- [ ] \n- [ ] foo", "at start of text")
    }
}
