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
}
