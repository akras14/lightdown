import AppKit
@testable import LightdownKit

@MainActor
func scrollSyncChecks(_ t: Checker) {
    // Sections of different heights so a percentage-based sync would drift.
    var parts: [String] = []
    for i in 1...30 {
        parts.append("## Section \(i)")
        if i % 3 == 0 { parts.append("```swift\n" + (1...40).map { "let line\($0) = \($0)" }.joined(separator: "\n") + "\n```") }
        if i % 4 == 0 { parts.append((1...6).map { "- item \($0)" }.joined(separator: "\n")) }
        parts.append("Paragraph for section \(i), with enough words to wrap across the width of the preview pane at least once or twice.")
    }
    let source = parts.joined(separator: "\n\n") + "\n"
    let lines = source.components(separatedBy: "\n")
    func line(of text: String) -> Int { lines.firstIndex(of: text)! + 1 }

    let h = DocumentHarness(source)
    defer { h.close() }
    h.editor.view.window?.setFrameOrigin(NSPoint(x: -5000, y: -5000))
    h.editor.view.window?.orderFrontRegardless()
    let view = h.editor.textView!

    t.group("scroll sync") {
        t.expect(h.waitForPreview(), true, "preview loaded")

        @MainActor func previewTop(of selector: String) -> Double? {
            evaluate("Math.round(document.querySelector('\(selector)').getBoundingClientRect().top)", in: h.webView) as? Double
        }

        // Editor -> preview: a heading at the top of the editor ends up at the top of the preview.
        view.scrollToLine(Double(line(of: "## Section 20")))
        waitUntil(timeout: 1) { false }
        let top20 = previewTop(of: "#section-20")
        t.expect(top20.map { abs($0) <= 3 }, true, "editor → preview: heading at top (offset \(top20 ?? .nan))")

        // Middle of a code block lines up too.
        let codeStart = line(of: "## Section 9") + 2   // the ``` line
        view.scrollToLine(Double(codeStart + 20))
        waitUntil(timeout: 1) { false }
        let fraction = evaluate("""
            (() => { const pre = document.querySelector('#section-9').nextElementSibling;
                     const r = pre.getBoundingClientRect(); return -r.top / r.height; })()
            """, in: h.webView) as? Double
        t.expect(fraction.map { abs($0 - 20.0 / 42.0) < 0.05 }, true, "code block midpoint (fraction \(fraction ?? .nan))")

        // Preview -> editor.
        _ = evaluate("document.getElementById('section-25').scrollIntoView(); 0", in: h.webView)
        let target = Double(line(of: "## Section 25"))
        t.expect(waitUntil(timeout: 2) { abs(view.topVisibleLine() - target) < 0.3 }, true,
                 "preview → editor: line \(target) at top (got \(view.topVisibleLine()))")

        // No feedback loop: things stay put afterwards.
        waitUntil(timeout: 0.6) { false }
        t.expect(abs(view.topVisibleLine() - target) < 0.3, true, "stable after sync (got \(view.topVisibleLine()))")

        // Bottoms line up.
        view.scrollToBottom()
        waitUntil(timeout: 1) { false }
        let atBottom = evaluate("window.scrollY >= document.documentElement.scrollHeight - window.innerHeight - 1", in: h.webView) as? Bool
        t.expect(atBottom, true, "editor at bottom → preview at bottom")

        // Top of the document.
        view.scrollToLine(0)
        waitUntil(timeout: 1) { false }
        t.expect(evaluate("window.scrollY", in: h.webView) as? Double, 0, "both at top")
    }
}
