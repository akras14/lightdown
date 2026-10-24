import AppKit
import PDFKit
@testable import LightdownKit

@MainActor
func exportChecks(_ t: Checker) {
    t.group("export PDF") {
        let h = DocumentHarness("""
        # Export test

        Hello from Lightdown.

        ```mermaid
        graph TD
          Alpha --> Beta
        ```
        """)
        defer { h.close() }
        let savedZoom = Zoom.level
        NSApp.appearance = NSAppearance(named: .darkAqua)
        Zoom.level = 2
        defer { NSApp.appearance = nil; Zoom.level = savedZoom }

        let pdfURL = h.directory.appendingPathComponent("out.pdf")
        var result: Bool?
        h.document.runPrintJob(savingTo: pdfURL) { result = $0 }
        t.expect(waitUntil(timeout: 15) { result != nil }, true, "finished")
        t.expect(result, true, "succeeded")

        guard let pdf = PDFDocument(url: pdfURL), let page = pdf.page(at: 0) else {
            t.expect(false, true, "PDF readable")
            return
        }
        let text = pdf.string ?? ""
        t.expect(text.contains("Hello from Lightdown."), true, "body text")
        t.expect(text.contains("Alpha") && text.contains("Beta"), true, "Mermaid diagram rendered before capture")
        t.expect(pdf.pageCount, 1, "fits one page at normal size despite 200% preview zoom")

        // Light background even though the app is in dark mode.
        let thumb = page.thumbnail(of: NSSize(width: 100, height: 130), for: .mediaBox)
        let rep = NSBitmapImageRep(data: thumb.tiffRepresentation!)!
        let corner = rep.colorAt(x: 50, y: 120)!.usingColorSpace(.deviceRGB)!
        t.expect(corner.brightnessComponent > 0.9, true, "white page background (got brightness \(corner.brightnessComponent))")
    }

    t.group("copy HTML") {
        let h = DocumentHarness("# Hi\n\nSome **bold** text.\n")
        defer { h.close() }
        let saved = NSPasteboard.general.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        } ?? []
        defer { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(saved) }

        h.editor.textView.setSelectedRange(NSRange(location: 6, length: 20))
        h.editor.copyHTML(nil)
        t.expect(NSPasteboard.general.string(forType: .string), "<p>Some <strong>bold</strong> text.</p>\n", "selection only, as source")
        t.expect(NSPasteboard.general.string(forType: .html) != nil, true, "also as rich HTML")
    }
}
