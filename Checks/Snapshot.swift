import AppKit
import WebKit
@testable import LightdownKit

/// `swift run LightdownChecks --snapshot <file.md> <out.png> [dark]`
/// Renders a document's preview pane to a PNG, for checking styles without screen-recording
/// permission. (AppKit views in an offscreen window don't draw, so only the preview is captured.)
@MainActor
func snapshot(markdown: URL, to output: URL, dark: Bool) {
    NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let h = DocumentHarness((try? String(contentsOf: markdown, encoding: .utf8)) ?? "")
    defer { h.close() }
    h.editor.view.window?.setFrame(NSRect(x: -5000, y: -5000, width: 1200, height: 760), display: true)
    _ = h.waitForPreview()
    waitUntil(timeout: 1.5) { false }   // let diagrams and highlighting settle

    var image: NSImage?
    h.webView.takeSnapshot(with: nil) { img, _ in image = img }
    waitUntil { image != nil }
    guard let image, let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: output)
}
