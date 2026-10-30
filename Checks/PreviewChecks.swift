import AppKit
import WebKit
@testable import LightdownKit

@MainActor
func previewChecks(_ t: Checker) {
    t.group("task states") {
        func checked(_ markdown: String) -> [Bool] {
            let html = MarkdownRenderer.html(from: markdown)
            return html.components(separatedBy: "<input type=\"checkbox\"").dropFirst().map { $0.hasPrefix(" checked") }
        }
        t.expect(checked("- [ ] press ⌘L: plain → `- [ ]` → `- [x]`"), [false], "[x] later in the text doesn't check it")
        t.expect(checked("- [x] done, unlike `- [ ]`"), [true], "checked with [ ] later in the text")
        t.expect(checked("- [ ] a\n- [X] b\n  - [ ] c [x]"), [false, true, false], "nested and capital X")
        t.expect(checked("1. [ ] numbered [x]\n2) [x] paren"), [false, true], "numbered markers")
        t.expect(checked("- [ ] émoji 😀 then [x]"), [false], "multi-byte text before [x]")
    }

    t.group("table checkboxes") {
        func checked(_ markdown: String) -> [Bool] {
            let html = MarkdownRenderer.html(from: markdown)
            return html.components(separatedBy: "<input type=\"checkbox\"").dropFirst().map { $0.hasPrefix(" checked") }
        }
        let table = "| Task | Mon | Tue |\n|---|:-:|:-:|\n| Run | [ ] | [x] |\n| Read | [X] done | [ ]|\n"
        t.expect(checked(table), [false, true, true, false], "one box per cell")
        let html = MarkdownRenderer.html(from: table)
        t.expect(html.contains("<td align=\"center\"><input type=\"checkbox\" checked=\"\" disabled=\"\" /> done</td>"), true,
                 "box replaces the brackets, text follows (html: \(html))")
        t.expect(html.contains("[ ]") || html.contains("[x]") || html.contains("[X]"), false, "no brackets left")
        t.expect(checked("| a |\n|---|\n| see [ ] |\n| `[x]` |\n| \\[ ] |\n| [ ]x |\n"), [],
                 "only a box at the start of a cell, followed by a space or the cell end")
        t.expect(checked("| Project | Done |\n|---|:-:|\n| **Search** 1 | [x] |\n| `code` | [ ] |\n| [a](https://x.y) | [ ] |\n"),
                 [true, false, false], "boxes after cells with inline markup")
    }

    t.group("bare checkboxes") {
        func checked(_ markdown: String) -> [Bool] {
            let html = MarkdownRenderer.html(from: markdown)
            return html.components(separatedBy: "<input type=\"checkbox\"").dropFirst().map { $0.hasPrefix(" checked") }
        }
        t.expect(checked("[ ] a\n[x] b\n\n> [X] quoted\n"), [false, true, true], "lines, including in a quote")
        t.expect(checked("see [ ] here\n\n\\[ ] escaped\n\n[ ]x\n\n[ ](url)\n\n`[x]` code\n"), [],
                 "only an unescaped box at the start of a line, followed by a space or the line end")
        t.expect(checked("- [ ] task [x]\n"), [false], "list tasks unchanged")
        t.expect(checked("text\n[x] b\n"), [true], "box on a later line of a paragraph")
        let html = MarkdownRenderer.html(from: "[ ] a\n[x] b\n")
        t.expect(html.contains("<input type=\"checkbox\" disabled=\"\" /> a<br />\n<input"), true,
                 "each box starts its own line (html: \(html))")
        let positioned = MarkdownRenderer.html(from: "# T\n\n[ ] a\n[x] b\n", sourcePositions: true)
        t.expect(positioned.contains("data-line=\"4\" data-column=\"1\""), true, "preview knows the source line (html: \(positioned))")
        t.expect(MarkdownRenderer.html(from: "[ ] a").contains("data-line"), false, "no positions in export")
    }

    t.group("toggle box at a position") {
        t.expect(TodoList.toggleBox("| Run | [ ] | [x] |", column: 8), "| Run | [x] | [x] |", "check")
        t.expect(TodoList.toggleBox("| Run | [ ] | [x] |", column: 14), "| Run | [ ] | [ ] |", "uncheck")
        t.expect(TodoList.toggleBox("|[X] done|", column: 2), "|[ ] done|", "capital X, no padding")
        t.expect(TodoList.toggleBox("| é | [ ] |", column: 7), "| é | [x] |", "byte columns after multi-byte text")
        t.expect(TodoList.toggleBox("> [ ] quoted", column: 1), "> [x] quoted", "in a quote")
        t.expect(TodoList.toggleBox("| Run | x |", column: 8), nil, "no box")
    }

    t.group("list spacing") {
        let h = DocumentHarness("[ ] Brother\n[ ] Brother\n\n* test\n* Test\n\n- [ ] Dude\n- [ ] Sweet\n\n1. one\n2. two\n")
        defer { h.close() }
        t.expect(h.waitForPreview(), true, "preview loaded")
        // Row pitch of bare lines, bullets, tasks and numbers, then the box-to-text gap for bare lines and tasks.
        let m = evaluate("""
            (() => { const b = [...document.querySelectorAll('#content input[type=checkbox]')];
              const li = [...document.querySelectorAll('#content li')];
              const text = el => { const r = document.createRange(); r.selectNodeContents(el.nextSibling);
                return [...r.getClientRects()].find(x => x.width > 4).left; };
              const gap = el => text(el) - el.getBoundingClientRect().right;
              const top = el => el.getBoundingClientRect().top;
              return [top(b[1]) - top(b[0]), top(li[1]) - top(li[0]), top(b[3]) - top(b[2]), top(li[5]) - top(li[4]),
                      gap(b[0]), gap(b[2])]; })()
            """, in: h.webView) as? [Double]
        t.expect(m != nil, true, "measured")
        if let m {
            for (i, name) in ["bare lines", "bullets", "tasks", "numbers"].enumerated() {
                t.expect(abs(m[i] - 24) < 0.5, true, "\(name) one line apart (\(m[i]))")
            }
            t.expect(abs(m[4] - m[5]) < 1, true, "same gap after the box (bare \(m[4]), task \(m[5]))")
        }
    }

    t.group("clicking bare checkboxes") {
        let h = DocumentHarness("# Today\n\n[ ] a\n[x] b\n")
        defer { h.close() }
        t.expect(h.waitForPreview(), true, "preview loaded")
        _ = evaluate("document.querySelectorAll('p input[type=checkbox]')[0].click(); 0", in: h.webView)
        t.expect(waitUntil { h.text == "# Today\n\n[x] a\n[x] b\n" }, true, "checks a (text: \(h.text.debugDescription))")
        _ = evaluate("document.querySelectorAll('p input[type=checkbox]')[1].click(); 0", in: h.webView)
        t.expect(waitUntil { h.text == "# Today\n\n[x] a\n[ ] b\n" }, true, "unchecks b (text: \(h.text.debugDescription))")
    }

    t.group("clicking table checkboxes") {
        let h = DocumentHarness("| Task | Mon | Tue |\n|---|---|---|\n| Run | [ ] | [x] |\n| Read | [ ] | [ ] |\n")
        defer { h.close() }
        t.expect(h.waitForPreview(), true, "preview loaded")
        @MainActor func click(_ index: Int) {
            _ = evaluate("document.querySelectorAll('td input[type=checkbox]')[\(index)].click(); 0", in: h.webView)
        }
        click(1)
        t.expect(waitUntil { h.text.contains("| Run | [ ] | [ ] |") }, true, "unchecks Run/Tue")
        click(2)
        t.expect(waitUntil { h.text.contains("| Read | [x] | [ ] |") }, true, "checks Read/Mon")
        t.expect(h.text, "| Task | Mon | Tue |\n|---|---|---|\n| Run | [ ] | [ ] |\n| Read | [x] | [ ] |\n", "nothing else changed")
        t.expect(waitUntil {
            evaluate("document.querySelectorAll('td input[type=checkbox]')[2].checked", in: h.webView) as? Bool == true
        }, true, "preview re-renders checked")
    }

    t.group("source positions") {
        let html = MarkdownRenderer.html(from: "# Title\n\n- [ ] task\n", sourcePositions: true)
        t.expect(html.contains("<li data-sourcepos=\"3:1-3:10\">"), true, "task item tagged with its line")
        t.expect(MarkdownRenderer.html(from: "# Title").contains("data-sourcepos"), false, "off by default (export)")
    }

    t.group("clicking preview checkboxes") {
        let h = DocumentHarness("# List\n\n- [ ] first\n- [x] second\n  - [ ] nested\n")
        defer { h.close() }
        t.expect(h.waitForPreview(), true, "preview loaded")

        @MainActor func click(_ index: Int) {
            _ = evaluate("document.querySelectorAll('li input[type=checkbox]')[\(index)].click(); 0", in: h.webView)
        }
        click(0)
        t.expect(waitUntil { h.text.contains("- [x] first") }, true, "checks first item")
        click(1)
        t.expect(waitUntil { h.text.contains("- [ ] second") }, true, "unchecks second item")
        click(2)
        t.expect(waitUntil { h.text.contains("  - [x] nested") }, true, "nested item")
        t.expect(h.text, "# List\n\n- [x] first\n- [ ] second\n  - [x] nested\n", "nothing else changed")
        t.expect(waitUntil {
            evaluate("document.querySelectorAll('li input[type=checkbox]')[0].checked", in: h.webView) as? Bool == true
        }, true, "preview re-renders checked")
    }

    t.group("unchecking updates the preview") {
        let h = DocumentHarness("- [x] done\n- [ ] open\n")
        defer { h.close() }
        t.expect(h.waitForPreview(), true, "preview loaded")
        @MainActor func states() -> String? {
            evaluate("[...document.querySelectorAll('li input[type=checkbox]')].map(b => b.checked ? 'x' : '-').join('')",
                     in: h.webView) as? String
        }
        t.expect(states(), "x-", "initial")

        // Click the checked box in the preview.
        _ = evaluate("document.querySelectorAll('li input[type=checkbox]')[0].click(); 0", in: h.webView)
        t.expect(waitUntil { h.text.hasPrefix("- [ ] done") }, true, "source unchecked by click")
        t.expect(waitUntil { states() == "--" }, true, "preview unchecked after click (got \(states() ?? "nil"))")

        // Check it again by click, then uncheck with Cmd+L in the editor.
        _ = evaluate("document.querySelectorAll('li input[type=checkbox]')[0].click(); 0", in: h.webView)
        t.expect(waitUntil { states() == "x-" }, true, "preview checked again (got \(states() ?? "nil"))")
        h.editor.textView.setSelectedRange(NSRange(location: 2, length: 0))
        h.editor.textView.toggleTodo(nil)
        t.expect(h.text.hasPrefix("- [ ] done"), true, "source unchecked by Cmd+L")
        t.expect(waitUntil { states() == "--" }, true, "preview unchecked after Cmd+L (got \(states() ?? "nil"))")

        // Undo while the preview has focus (as after clicking a checkbox).
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))   // close the undo group
        _ = evaluate("document.querySelectorAll('li input[type=checkbox]')[1].click(); 0", in: h.webView)
        t.expect(waitUntil { h.text.contains("- [x] open") }, true, "second item checked by click")
        t.expect(waitUntil { states() == "-x" }, true, "preview shows it checked")
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        let window = h.editor.view.window!
        window.makeFirstResponder(h.webView)
        let handled = window.firstResponder?.tryToPerform(Selector(("undo:")), with: nil) ?? false
        t.expect(handled, true, "Cmd+Z from the preview reaches an undo handler")
        t.expect(waitUntil { h.text.contains("- [ ] open") }, true, "undo reverts the source (text: \(h.text.debugDescription))")
        t.expect(waitUntil { states() == "--" }, true, "preview follows the undo (got \(states() ?? "nil"))")
    }

    // Issue #1: the repro from GitHub, which renders it with Mermaid 12 (ELK layout).
    t.group("mermaid renders like GitHub") {
        let h = DocumentHarness("""
        ```mermaid
        flowchart LR
            A["team-a"]
            B["team-b"]
            C["team-c"]
            A -- "file_one.rb + test<br/>file_two.rb" --> B
            C -. "keeps file_three_test.rb<br/>(matches its *txn*_test.rb glob)" .-> C
        ```
        """)
        defer { h.close() }
        t.expect(h.waitForPreview(), true, "preview loaded")
        t.expect(waitUntil { evaluate("!!document.querySelector('#content .mermaid svg')", in: h.webView) as? Bool == true },
                 true, "diagram rendered")
        let label = evaluate("""
            [...document.querySelectorAll('#content .mermaid svg .edgeLabel')].map(e => e.textContent).join(' | ')
            """, in: h.webView) as? String ?? ""
        t.expect(label.contains("*txn*_test.rb"), true, "asterisks in a label stay literal (got \(label.debugDescription))")
        t.expect(evaluate("document.querySelectorAll('#content .mermaid svg .edgeLabel em').length", in: h.webView) as? Int, 0,
                 "no italics in labels")
        // The self-loop stays next to its node instead of stretching across the page.
        let sizes = evaluate("""
            (() => { const svg = document.querySelector('#content .mermaid svg');
              const node = [...svg.querySelectorAll('.node')].find(n => n.textContent.trim() === 'team-c');
              // Mermaid 11 draws a self-loop as three edges (C-cyclic-special-*), 12 as one (L_C_C_0).
              const loop = [...svg.querySelectorAll('path.flowchart-link')]
                .filter(p => /C_C|C-cyclic/.test(p.getAttribute('data-id') || p.id))
                .map(p => p.getBoundingClientRect());
              if (!node || !loop.length) return null;
              const width = Math.max(...loop.map(r => r.right)) - Math.min(...loop.map(r => r.left));
              return [node.getBoundingClientRect().width, width]; })()
            """, in: h.webView) as? [Double]
        t.expect(sizes != nil, true, "found the self-loop and its node")
        if let sizes { t.expect(sizes[1] < sizes[0], true, "self-loop narrower than its node (node \(sizes[0]), loop \(sizes[1]))") }
    }
}
