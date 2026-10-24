import AppKit
@testable import LightdownKit

@MainActor
func imageChecks(_ t: Checker) {
    t.group("image links") {
        let folder = URL(fileURLWithPath: "/tmp/notes")
        t.expect(EditorTextView.imageLink(for: folder.appendingPathComponent("images/a b (1).png"), relativeTo: folder),
                 "![a b (1)](images/a%20b%20%281%29.png)", "spaces and parentheses encoded")
    }

    t.group("pasting and dropping images") {
        let h = DocumentHarness("Before\n")
        defer { h.close() }
        let view = h.editor.textView!
        let pasteboard = NSPasteboard(name: .init("LightdownImageChecks"))
        defer { pasteboard.releaseGlobally() }

        // A tiny PNG on the pasteboard, like a screenshot.
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = rep.representation(using: .png, properties: [:])!
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        view.setSelectedRange(NSRange(location: 7, length: 0))
        t.expect(view.insertImages(from: pasteboard, at: view.selectedRange()), true, "pasted data handled")
        let images = h.directory.appendingPathComponent("images")
        let saved = (try? FileManager.default.contentsOfDirectory(atPath: images.path)) ?? []
        t.expect(saved.count, 1, "PNG saved in images/")
        t.expect(h.text, "Before\n![\((saved.first ?? "") .replacingOccurrences(of: ".png", with: ""))](images/\(saved.first ?? ""))",
                 "link inserted")

        // Text on the pasteboard wins over a picture of it.
        pasteboard.clearContents()
        pasteboard.setString("hello", forType: .string)
        pasteboard.setData(png, forType: .tiff)
        t.expect(view.insertImages(from: pasteboard, at: view.selectedRange()), false, "rich text falls through")

        // A file outside the document folder is copied in; one inside is linked in place.
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString) shot.png")
        try! png.write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        let inside = h.directory.appendingPathComponent("local.png")
        try! png.write(to: inside)
        pasteboard.clearContents()
        pasteboard.writeObjects([outside as NSURL, inside as NSURL])
        view.string = ""
        _ = view.insertImages(from: pasteboard, at: NSRange(location: 0, length: 0))
        let name = outside.deletingPathExtension().lastPathComponent
        t.expect(FileManager.default.fileExists(atPath: images.appendingPathComponent(outside.lastPathComponent).path), true,
                 "outside file copied")
        t.expect(h.text, "![\(name)](images/\(name.replacingOccurrences(of: " ", with: "%20")).png)\n![local](local.png)",
                 "links for copied and local files")
    }

    t.group("untitled documents") {
        let view = TextHarness("|").view
        let pasteboard = NSPasteboard(name: .init("LightdownImageChecks2"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("just text", forType: .string)
        t.expect(view.insertImages(from: pasteboard, at: NSRange(location: 0, length: 0)), false, "text paste unaffected")
    }
}
