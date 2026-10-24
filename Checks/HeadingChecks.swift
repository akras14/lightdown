import AppKit
@testable import LightdownKit

@MainActor
func headingChecks(_ t: Checker) {
    t.group("heading links") {
        let filler = (1...80).map { "Line \($0)" }.joined(separator: "\n\n")
        let h = DocumentHarness("""
        # Hello, World!

        [jump](#setup-1) · [footnote](#fn-1)[^1]

        \(filler)

        ## Setup

        ## Setup

        ### Ünïcode & Ümlauts_2

        \(filler)

        [^1]: A note.
        """)
        defer { h.close() }
        t.expect(h.waitForPreview(), true, "preview loaded")

        let ids = evaluate("[...document.querySelectorAll('h1,h2,h3')].map(h => h.id).join(' ')", in: h.webView) as? String
        t.expect(ids, "hello-world setup setup-1 ünïcode--ümlauts_2", "GitHub-style ids")

        _ = evaluate("window.scrollTo(0, 0); document.querySelector('a[href=\"#setup-1\"]').click(); 0", in: h.webView)
        let top = evaluate("Math.round(document.getElementById('setup-1').getBoundingClientRect().top)", in: h.webView) as? Int
        t.expect(top.map { abs($0) < 5 }, true, "clicking the link scrolls to the heading (top: \(top ?? -1))")

        let html = MarkdownDocument.standaloneHTML(title: "x", body: "<h2>A B</h2>")
        t.expect(html.contains("ldAddHeadingIds(document.body)"), true, "exported HTML adds ids too")
    }
}
