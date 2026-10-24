import AppKit
import WebKit
@testable import LightdownKit

@MainActor
func previewChecks(_ t: Checker) {
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
}
