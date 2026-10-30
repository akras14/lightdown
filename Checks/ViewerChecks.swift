import AppKit
import WebKit
@testable import LightdownKit

/// The zoom viewer: diagrams and images open over the preview with zoom, pan, fit and reset.
@MainActor
func viewerChecks(_ t: Checker) {
    let h = DocumentHarness("""
    # Viewer

    Some text.

    | Habit | Mon | Tue | Wed | Thu | Fri | Sat | Sun | Notes, long enough to make this table wider than the window | More notes, also long enough to keep going past the edge |
    |---|---|---|---|---|---|---|---|---|---|
    | Run | [ ] | [x] | [ ] | [ ] | [ ] | [ ] | [ ] | a | b |

    ```mermaid
    graph LR
      Alpha --> Beta --> Gamma --> Delta --> Epsilon
    ```

    """)
    defer { h.close() }
    // A 400x200 PNG next to the document, so the image has a known natural size. Linked from the
    // text only once it exists, so the preview doesn't cache a failed load.
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 200, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let images = h.directory.appendingPathComponent("images")
    try! FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
    try! rep.representation(using: .png, properties: [:])!.write(to: images.appendingPathComponent("sample.png"))
    h.editor.textView.insertText("![sample](images/sample.png)\n\n[![linked](images/sample.png)](https://example.com)\n",
                                 replacementRange: NSRange(location: (h.text as NSString).length, length: 0))
    h.editor.view.window?.setFrameOrigin(NSPoint(x: -5000, y: -5000))
    h.editor.view.window?.orderFrontRegardless()
    let web = h.editor.webView!

    @MainActor func js(_ script: String) -> Any? { evaluate(script, in: web) }
    @MainActor func state() -> [String: Any] { js("ldViewerState()") as? [String: Any] ?? [:] }
    @MainActor func scale() -> Double { state()["scale"] as? Double ?? -1 }
    @MainActor func isOpen() -> Bool { state()["open"] as? Bool ?? false }
    @MainActor func click(_ selector: String) {
        _ = js("document.querySelector('\(selector)').dispatchEvent(new MouseEvent('click', {bubbles: true, cancelable: true})); 0")
    }

    t.group("zoom viewer: diagrams") {
        t.expect(h.waitForPreview(), true, "preview loaded")
        t.expect(waitUntil { js("!!document.querySelector('#content .mermaid svg')") as? Bool == true }, true, "diagram rendered")
        t.expect(isOpen(), false, "closed at first")

        click("#content .mermaid svg")
        t.expect(isOpen(), true, "clicking a diagram opens the viewer")
        t.expect(state()["kind"] as? String, "diagram", "shows the diagram")
        t.expect(js("!!document.querySelector('#ld-viewer svg')") as? Bool, true, "viewer holds a copy of the SVG")
        t.expect(waitUntil { web.viewerOpen }, true, "app knows the viewer is open")

        let fit = scale()
        t.expect(fit > 0, true, "has a scale (\(fit))")
        click("#ld-viewer [data-action=zoom-in]")
        t.expect(scale() > fit, true, "zoom in")
        click("#ld-viewer [data-action=zoom-out]")
        click("#ld-viewer [data-action=zoom-out]")
        t.expect(scale() < fit, true, "zoom out")
        click("#ld-viewer [data-action=reset]")
        t.expect(scale(), 1, "reset to actual size")
        click("#ld-viewer [data-action=fit]")
        t.expect(abs(scale() - fit) < 0.001, true, "fit to window")
        let fits = js("""
            (() => { const r = document.querySelector('#ld-viewer .ld-viewer-item').getBoundingClientRect();
                     return r.left >= 0 && r.top >= 0 && r.right <= innerWidth && r.bottom <= innerHeight; })()
            """) as? Bool
        t.expect(fits, true, "fitted diagram is inside the window")

        // Zooming past page width: well beyond what fits.
        for _ in 0..<6 { click("#ld-viewer [data-action=zoom-in]") }
        let wide = js("document.querySelector('#ld-viewer .ld-viewer-item').getBoundingClientRect().width > innerWidth") as? Bool
        t.expect(wide, true, "zooms beyond the window width")

        // Drag to pan.
        let before = state()
        _ = js("""
            (() => { const s = document.getElementById('ld-viewer');
              const ev = (type, x, y) => s.dispatchEvent(new PointerEvent(type, {bubbles: true, clientX: x, clientY: y, pointerId: 1, button: 0, buttons: 1}));
              ev('pointerdown', 300, 300); ev('pointermove', 340, 320); ev('pointerup', 340, 320); return 0; })()
            """)
        let after = state()
        t.expect((after["x"] as? Double ?? 0) - (before["x"] as? Double ?? 0), 40, "drag pans horizontally")
        t.expect((after["y"] as? Double ?? 0) - (before["y"] as? Double ?? 0), 20, "drag pans vertically")
        t.expect(isOpen(), true, "a drag doesn't close the viewer")

        // Trackpad pinch, forwarded by the app while the viewer is open.
        let pinchFrom = scale()
        let pageZoom = web.pageZoom
        web.zoomViewer(by: 1.5, at: CGPoint(x: 200, y: 200))
        t.expect(waitUntil { abs(scale() - pinchFrom * 1.5) < 0.001 }, true, "pinch zooms the viewer")
        t.expect(web.pageZoom, pageZoom, "pinch leaves the page zoom alone")

        _ = js("document.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape', bubbles: true})); 0")
        t.expect(isOpen(), false, "Escape closes")
        t.expect(js("document.getElementById('ld-viewer') === null || document.getElementById('ld-viewer').hidden") as? Bool, true,
                 "overlay gone")
        t.expect(waitUntil { !web.viewerOpen }, true, "app knows the viewer closed")
    }

    t.group("zoom viewer: images") {
        t.expect(waitUntil { js("document.querySelector('#content p > img')?.naturalWidth ?? 0") as? Int == 400 }, true, "image loaded")
        click("#content p > img")
        t.expect(isOpen(), true, "clicking an image opens the viewer")
        t.expect(state()["kind"] as? String, "image", "shows the image")
        t.expect(js("document.querySelector('#ld-viewer img').naturalWidth") as? Int, 400, "same image")
        t.expect(scale(), 1, "a small image opens at actual size, not blown up")
        click("#ld-viewer [data-action=close]")
        t.expect(isOpen(), false, "close button closes")

        // Cancel the link afterwards (window listeners run last), so the check doesn't open a browser.
        _ = js("window.addEventListener('click', e => e.preventDefault(), {once: true}); 0")
        click("#content a img")
        t.expect(isOpen(), false, "an image inside a link follows the link instead")
    }

    t.group("zoom viewer: tables") {
        t.expect(h.waitForPreview(), true, "preview loaded")
        click("#content td")
        t.expect(isOpen(), false, "clicking a cell doesn't open the viewer")
        t.expect(js("document.querySelectorAll('#content .ld-table-expand').length") as? Int, 1, "table has an expand button")

        click("#content .ld-table-expand")
        t.expect(isOpen(), true, "expand button opens the viewer")
        t.expect(state()["kind"] as? String, "table", "shows the table")
        t.expect(js("document.querySelectorAll('#ld-viewer td').length") as? Int, 10, "viewer holds a copy of the table")
        t.expect(scale() < 1, true, "a table wider than the window is fitted (\(scale()))")
        // Laid out again at its natural width, not copied squeezed into the page's width.
        let pageWidth = js("document.querySelector('#content table').offsetWidth") as? Int ?? 0
        let viewerWidth = js("document.querySelector('#ld-viewer table').offsetWidth") as? Int ?? 0
        t.expect(viewerWidth > pageWidth, true, "wider than in the page (\(viewerWidth) vs \(pageWidth))")
        let headerLines = js("""
            (() => { const th = document.querySelector('#ld-viewer th:nth-child(9)'), cs = getComputedStyle(th);
                     return Math.round((th.clientHeight - parseFloat(cs.paddingTop) - parseFloat(cs.paddingBottom)) / parseFloat(cs.lineHeight)); })()
            """) as? Int
        t.expect(headerLines, 1, "headers don't wrap")
        t.expect(js("document.querySelector('#ld-viewer .ld-viewer-item').offsetWidth") as? Int, viewerWidth,
                 "viewer sized to the table")
        t.expect(js("document.querySelector('#ld-viewer .ld-table-expand') === null") as? Bool, true, "no expand button in the copy")

        // Checkboxes in the copy edit the source, and the copy follows.
        click("#ld-viewer input[type=checkbox]")
        t.expect(waitUntil { h.text.contains("| Run | [x] | [x] |") }, true, "checks the box in the source")
        t.expect(waitUntil { js("document.querySelector('#ld-viewer input[type=checkbox]').checked") as? Bool == true }, true,
                 "copy shows it checked")
        t.expect(isOpen(), true, "viewer stays open")
        t.expect(state()["kind"] as? String, "table", "still the table")
        _ = js("ldViewerClose(); 0")
    }

    t.group("zoom viewer: context menu") {
        @MainActor func menu(rightClicking selector: String) -> NSMenu {
            // The page's message to the app arrives before the reply to this script.
            _ = js("document.querySelector('\(selector)').dispatchEvent(new MouseEvent('contextmenu', {bubbles: true, cancelable: true})); 0")
            let menu = NSMenu()
            menu.addItem(withTitle: "Reload", action: nil, keyEquivalent: "")
            let event = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                                           windowNumber: web.window?.windowNumber ?? 0, context: nil,
                                           eventNumber: 0, clickCount: 1, pressure: 1)!
            web.willOpenMenu(menu, with: event)
            return menu
        }
        let item = menu(rightClicking: "#content .mermaid svg").items.first { $0.title == "Open in Viewer" }
        t.expect(item != nil, true, "diagram menu has Open in Viewer")
        if let item, let action = item.action { NSApp.sendAction(action, to: item.target, from: item) }
        t.expect(waitUntil { isOpen() }, true, "menu item opens the viewer")
        t.expect(state()["kind"] as? String, "diagram", "with the right-clicked diagram")
        _ = js("ldViewerClose(); 0")

        t.expect(menu(rightClicking: "#content p > img").items.contains { $0.title == "Open in Viewer" }, true,
                 "image menu has Open in Viewer")
        t.expect(menu(rightClicking: "#content td").items.contains { $0.title == "Open in Viewer" }, true,
                 "table menu has Open in Viewer")
        t.expect(menu(rightClicking: "#content h1").items.contains { $0.title == "Open in Viewer" }, false,
                 "text menu doesn't")
    }
}
