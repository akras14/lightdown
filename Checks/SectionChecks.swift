import AppKit
import WebKit
@testable import LightdownKit

/// Issue #5: collapse and expand sections in the preview.
@MainActor
func sectionChecks(_ t: Checker) {
    let markdown = """
    # Title

    intro needle

    ## Alpha

    alpha body needle

    ### Alpha child

    child body

    ```mermaid
    graph TD; A-->B
    ```

    ## Beta

    beta body
    """

    /// The text of each top-level block the preview shows, the headings without their toggle.
    func visible(_ h: DocumentHarness) -> [String] {
        evaluate("""
            [...document.getElementById('content').children]
              .filter(el => el.getClientRects().length > 0)
              .map(el => el.classList.contains('mermaid') ? 'diagram' : el.textContent.trim())
            """, in: h.webView) as? [String] ?? []
    }
    func toggle(_ h: DocumentHarness, _ heading: String) {
        _ = evaluate("""
            [...document.querySelectorAll('#content > h1, #content > h2, #content > h3')]
              .find(el => el.textContent.trim() === '\(heading)').querySelector('.ld-fold').click(); 0
            """, in: h.webView)
    }
    let everything = ["Title", "intro needle", "Alpha", "alpha body needle", "Alpha child", "child body", "diagram", "Beta", "beta body"]
    let alphaCollapsed = ["Title", "intro needle", "Alpha", "Beta", "beta body"]

    t.group("collapse one section") {
        let h = DocumentHarness(markdown)
        defer { h.close() }
        t.expect(h.waitForPreviewSettled(), true, "preview loaded")
        t.expect(evaluate("document.querySelectorAll('#content > :is(h1,h2,h3) > .ld-fold').length", in: h.webView) as? Int, 4,
                 "every heading has a toggle")
        t.expect(evaluate("[...document.querySelectorAll('h1,h2,h3')].map(h => h.id).join(' ')", in: h.webView) as? String,
                 "title alpha alpha-child beta", "toggles don't change heading ids")
        t.expect(visible(h), everything, "all expanded at first")

        toggle(h, "Alpha")
        t.expect(waitUntil { visible(h) == alphaCollapsed }, true, "Alpha hides its content and sub-sections (\(visible(h)))")
        toggle(h, "Alpha")
        t.expect(waitUntil { visible(h) == everything }, true, "and shows them again (\(visible(h)))")

        toggle(h, "Alpha child")
        toggle(h, "Alpha")
        toggle(h, "Alpha")
        t.expect(waitUntil { visible(h) == ["Title", "intro needle", "Alpha", "alpha body needle", "Alpha child", "Beta", "beta body"] },
                 true, "a collapsed sub-section stays collapsed when its parent opens (\(visible(h)))")
    }

    t.group("collapsed sections survive editing") {
        let h = DocumentHarness(markdown)
        defer { h.close() }
        t.expect(h.waitForPreviewSettled(), true, "preview loaded")
        toggle(h, "Alpha")
        t.expect(waitUntil { visible(h) == alphaCollapsed }, true, "collapsed")

        // Type inside the collapsed section, as at the keyboard.
        let tv = h.editor.textView!
        let end = (tv.string as NSString).range(of: "alpha body needle").upperBound
        tv.setSelectedRange(NSRange(location: end, length: 0))
        tv.insertText(" typed", replacementRange: tv.selectedRange())
        t.expect(waitUntil {
            evaluate("document.getElementById('content').textContent.includes('needle typed')", in: h.webView) as? Bool == true
        }, true, "preview re-rendered")
        t.expect(visible(h), alphaCollapsed, "still collapsed after the re-render")

        // A diagram drawn after the re-render stays hidden too.
        tv.insertText("\n\n```mermaid\ngraph TD; C-->D\n```", replacementRange: NSRange(location: (tv.string as NSString).range(of: "child body").upperBound, length: 0))
        t.expect(waitUntil {
            evaluate("document.querySelectorAll('#content .mermaid').length", in: h.webView) as? Int == 2 &&
                evaluate("document.querySelectorAll('#content code.language-mermaid').length", in: h.webView) as? Int == 0
        }, true, "diagrams drawn")
        t.expect(visible(h), alphaCollapsed, "new diagram hidden")
    }

    t.group("collapse all and expand all") {
        let h = DocumentHarness(markdown)
        defer { h.close() }
        t.expect(h.waitForPreviewSettled(), true, "preview loaded")
        t.expect(h.editor.validateMenuItem(NSMenuItem(title: "", action: #selector(EditorSplitViewController.expandAllSections(_:)), keyEquivalent: "")),
                 false, "Expand All disabled with nothing collapsed")
        h.editor.collapseAllSections(nil)
        t.expect(waitUntil { visible(h) == ["Title"] }, true, "only the top-level heading is left (\(visible(h)))")
        t.expect(waitUntil {
            h.editor.validateMenuItem(NSMenuItem(title: "", action: #selector(EditorSplitViewController.expandAllSections(_:)), keyEquivalent: ""))
        }, true, "Expand All enabled")
        h.editor.expandAllSections(nil)
        t.expect(waitUntil { visible(h) == everything }, true, "everything shows again (\(visible(h)))")

        let view = MainMenu.build().items.lazy.compactMap { $0.submenu }.first { $0.title == "View" }
        for action in [#selector(EditorSplitViewController.collapseAllSections(_:)), #selector(EditorSplitViewController.expandAllSections(_:))] {
            let item = view?.items.first { $0.action == action }
            t.expect(item?.keyEquivalent.isEmpty, false, "\(NSStringFromSelector(action)) in the View menu with a shortcut")
        }
    }

    t.group("find opens the section holding the match") {
        let h = DocumentHarness(markdown)
        defer { h.close() }
        t.expect(h.waitForPreviewSettled(), true, "preview loaded")
        toggle(h, "Alpha")
        t.expect(waitUntil { visible(h) == alphaCollapsed }, true, "collapsed")
        t.expect(waitUntil { h.editor.validateMenuItem(NSMenuItem(title: "", action: #selector(EditorSplitViewController.expandAllSections(_:)), keyEquivalent: "")) },
                 true, "the app knows a section is collapsed")

        // Use Selection for Find on the first "needle", then Find Next: the real find, as from the menu.
        let tv = h.editor.textView!
        tv.setSelectedRange((tv.string as NSString).range(of: "needle"))
        @MainActor func find(_ action: NSTextFinder.Action) {
            let item = NSMenuItem(title: "", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "")
            item.tag = action.rawValue
            tv.performFindPanelAction(item)
        }
        find(.setSearchString)
        find(.nextMatch)
        let match = (tv.string as NSString).range(of: "alpha body needle")
        t.expect(tv.selectedRange().location, match.location + "alpha body ".count, "found the match in Alpha")
        t.expect(waitUntil { visible(h) == ["Title", "intro needle", "Alpha", "alpha body needle", "Alpha child", "child body", "diagram", "Beta", "beta body"] },
                 true, "Alpha opened (\(visible(h)))")
    }
}
