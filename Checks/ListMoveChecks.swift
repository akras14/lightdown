@testable import LightdownKit

@MainActor
func listMoveChecks(_ t: Checker) {
    func move(_ marked: String, up: Bool) -> String? {
        let h = TextHarness(marked)
        return h.view.moveListItem(up: up) ? h.marked : nil
    }

    t.group("list move") {
        t.expect(move("- a\n- |b\n- c\n", up: true), "- |b\n- a\n- c\n")
        t.expect(move("- a\n- |b\n- c", up: false), "- a\n- c\n- |b")

        t.expect(move("- a\n- b\n- |c", up: false), nil, "last item")
        t.expect(move("- |a\n- b", up: true), nil, "first item")
        t.expect(move("text\n- |a\n", up: true), nil, "paragraph above")
        t.expect(move("- a\n\n- |b\n", up: true), nil, "blank line")
        t.expect(move("plain\nli|nes\n", up: true), nil, "not a list")

        t.expect(move("- a\n  - a1\n  - a2\n- |b\n", up: true), "- |b\n- a\n  - a1\n  - a2\n", "past sibling with children")
        t.expect(move("- |a\n  - a1\n- b\n  - b1\n- c\n", up: false), "- b\n  - b1\n- |a\n  - a1\n- c\n", "with own children")
        t.expect(move("- a\n  - a1\n  - |a2\n- b\n", up: true), "- a\n  - |a2\n  - a1\n- b\n", "nested")
        t.expect(move("- a\n  - |a1\n- b\n", up: false), nil, "nested stays in parent")

        t.expect(move("1. one\n2. two\n3. |three\n", up: true), "1. one\n2. |three\n3. two\n", "numbers")
        t.expect(move("9. nine\n10. |ten\n", up: true), "9. |ten\n10. nine\n", "number width change")

        t.expect(move("- a\n- «b\n- c»\n- d\n", up: false), "- a\n- d\n- «b\n- c»\n", "selection")
        t.expect(move("- «b\n»- a\n- c\n", up: false), "- a\n- «b\n»- c\n", "selection ending at line start")
        t.expect(move("- [ ] x\n- [x] |y\n", up: true), "- [x] |y\n- [ ] x\n", "todos")
        t.expect(move("\t- a\n\t- |b\n", up: true), "\t- |b\n\t- a\n", "tabs")

        let h = TextHarness("- a\n- |b\n")
        h.act { t.expect(h.view.moveListItem(up: true), true) }
        t.expect(h.view.undoManager?.undoActionName, "Move Item")
        h.view.undoManager?.undo()
        t.expect(h.view.string, "- a\n- b\n", "undo")
    }
}
