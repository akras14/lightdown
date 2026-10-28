import AppKit
@testable import LightdownKit

/// Issue #2: on macOS 26 the system Move To… popover fails to start in apps that aren't sandboxed
/// (ViewBridge error 14), so Move To… uses a save panel and moves the file itself.
@MainActor
func moveChecks(_ t: Checker) {
    t.group("Move To… panel") {
        let h = DocumentHarness("# Move me\n")
        defer { h.close() }
        let window = h.editor.view.window!
        h.document.move(nil)
        t.expect(waitUntil { window.attachedSheet != nil }, true, "shows a sheet")
        let panel = window.attachedSheet as? NSSavePanel
        t.expect(panel != nil, true, "the sheet is a save panel, not an error alert")
        t.expect(panel?.nameFieldStringValue, "note.md", "suggests the current name")
        t.expect(panel?.directoryURL?.standardizedFileURL.path, h.directory.standardizedFileURL.path, "starts in the current folder")
        t.expect(panel?.prompt, "Move", "button says Move")
        if let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .cancel) }
        t.expect(waitUntil { window.attachedSheet == nil }, true, "cancel closes it")
        t.expect(h.document.fileURL, h.url, "cancel leaves the file where it was")
    }

    t.group("moving the file") {
        let h = DocumentHarness("# Move me\n")
        defer { h.close() }
        let folder = h.directory.appendingPathComponent("moved")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent("renamed.md")

        var done = false
        h.document.moveFile(to: target) { done = true }
        t.expect(waitUntil { done }, true, "finished")
        t.expect(FileManager.default.fileExists(atPath: target.path), true, "file at the new place")
        t.expect(FileManager.default.fileExists(atPath: h.url.path), false, "gone from the old place")
        t.expect(h.document.fileURL?.standardizedFileURL, target.standardizedFileURL, "document follows the file")
        t.expect((UserDefaults.standard.stringArray(forKey: "openDocuments") ?? []).contains(target.path), true,
                 "reopened from the new place next launch")

        // Onto an existing file (the save panel has already asked to replace it).
        done = false
        let existing = h.directory.appendingPathComponent("existing.md")
        try! "old contents".write(to: existing, atomically: true, encoding: .utf8)
        h.document.moveFile(to: existing) { done = true }
        t.expect(waitUntil { done }, true, "replacing move finished")
        t.expect(try? String(contentsOf: existing, encoding: .utf8), "# Move me\n", "replaced with this document")
        t.expect(h.document.fileURL?.standardizedFileURL, existing.standardizedFileURL, "document follows the file")
        t.expect(FileManager.default.fileExists(atPath: target.path), false, "gone from the previous place")
        let current = existing

        // A folder that doesn't exist: the error is shown and the file stays put.
        done = false
        let missing = h.directory.appendingPathComponent("missing/x.md")
        h.document.moveFile(to: missing) { done = true }
        t.expect(waitUntil { done }, true, "failed move finished")
        t.expect(h.document.fileURL?.standardizedFileURL, current.standardizedFileURL, "failed move leaves the document")
        let window = h.editor.view.window!
        t.expect(waitUntil { window.attachedSheet != nil }, true, "failed move shows the error")
        if let sheet = window.attachedSheet { window.endSheet(sheet) }
    }
}
