import AppKit
@testable import LightdownKit

/// Regression check: formatting text after scrolling made both panes jump around.
@MainActor
func editStabilityChecks(_ t: Checker) {
    t.group("no jumping after an edit") {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let h = DocumentHarness((try? String(contentsOf: root.appendingPathComponent("Lightdown-Test.md"), encoding: .utf8)) ?? "")
        defer { h.close() }
        try? FileManager.default.copyItem(at: root.appendingPathComponent("images"), to: h.directory.appendingPathComponent("images"))
        let window = h.editor.view.window!
        window.setFrame(NSRect(x: -5000, y: -5000, width: 1200, height: 760), display: true)
        window.orderFrontRegardless()
        t.expect(h.waitForPreview(), true, "preview loaded")
        waitUntil(timeout: 1) { false }

        let view = h.editor.textView!
        let text = view.string as NSString
        view.scrollToLine(Double(text.substring(to: text.range(of: "## 12. Scroll sync").location).components(separatedBy: "\n").count))
        waitUntil(timeout: 0.6) { false }

        // Select a word in view and press Cmd+B.
        let word = text.range(of: "Paragraph after the image")
        view.setSelectedRange(NSRange(location: word.location, length: 9))
        let before = view.topVisibleLine()
        view.formatBold(nil)

        var editorTops: [Double] = [], previewTops: [Double] = []
        let end = Date().addingTimeInterval(2)
        while Date() < end {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            editorTops.append(view.topVisibleLine())
            if let y = evaluate("window.scrollY", in: h.webView) as? Double { previewTops.append(y) }
        }
        func directionChanges(_ values: [Double]) -> Int {
            let deltas = zip(values.dropFirst(), values).map { $0 - $1 }.filter { abs($0) > 0.5 }
            return zip(deltas.dropFirst(), deltas).filter { ($0 > 0) != ($1 > 0) }.count
        }
        t.expect(abs((editorTops.last ?? 0) - before) < 1, true,
                 "editor stays put (was \(before), now \(editorTops.last ?? -1))")
        t.expect(directionChanges(editorTops), 0, "editor doesn't bounce")
        t.expect(directionChanges(previewTops), 0, "preview doesn't bounce")

        // Then keep scrolling down, like a trackpad: both panes should only ever move down.
        var editorPath: [Double] = [], previewPath: [Double] = []
        let clip = view.enclosingScrollView!.contentView
        for _ in 0..<40 {
            clip.scroll(to: NSPoint(x: 0, y: clip.bounds.minY + 25))
            view.enclosingScrollView!.reflectScrolledClipView(clip)
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            editorPath.append(view.topVisibleLine())
            if let y = evaluate("window.scrollY", in: h.webView) as? Double { previewPath.append(y) }
        }
        waitUntil(timeout: 0.5) { false }
        t.expect(directionChanges(editorPath), 0, "editor scrolls smoothly after the edit")
        t.expect(directionChanges(previewPath), 0, "preview follows smoothly after the edit")
    }

    t.group("typing speed in a large document") {
        let big = (1...3000).map { "Line \($0) with some **bold** text, a [link](https://x.com) and `code`." }.joined(separator: "\n\n")
        let h = DocumentHarness(big)
        defer { h.close() }
        let view = h.editor.textView!
        view.scrollToLine(3000)
        view.setSelectedRange(NSRange(location: (view.string as NSString).length / 2, length: 0))
        let start = Date()
        for _ in 0..<10 {
            view.insertText("x", replacementRange: view.selectedRange())
            view.layoutManager!.ensureLayout(for: view.textContainer!)
        }
        let perKey = Date().timeIntervalSince(start) / 10 * 1000
        print("    typing in a \((big as NSString).length / 1024) KB document: \(Int(perKey)) ms per keystroke")
        t.expect(perKey < 50, true, "under 50 ms per keystroke (\(Int(perKey)) ms)")
    }
}
