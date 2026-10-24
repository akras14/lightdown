import AppKit
@testable import LightdownKit

@MainActor
func sessionChecks(_ t: Checker) {
    t.group("open recent menu") {
        // AppKit adds its own Open Recent; a second one of ours would show up twice.
        let file = MainMenu.build().items.first { $0.title == "File" }?.submenu
        t.expect(file?.items.filter { $0.title == "Open Recent" }.count, 0, "File menu leaves Open Recent to AppKit")
    }

    t.group("reopening documents") {
        let key = "openDocuments"
        let savedList = UserDefaults.standard.stringArray(forKey: key)
        defer { UserDefaults.standard.set(savedList, forKey: key); Session.isTerminating = false }

        let a = DocumentHarness("a"), b = DocumentHarness("b", name: "other.md")
        NSDocumentController.shared.addDocument(a.document)
        NSDocumentController.shared.addDocument(b.document)
        Session.saveOpenDocuments()
        t.expect(Set(Session.documentsToRestore().map(\.lastPathComponent)), ["note.md", "other.md"], "open documents remembered")

        // Quitting: the list is frozen, so windows closing during quit don't empty it.
        Session.isTerminating = true
        b.document.close()
        t.expect(Session.documentsToRestore().count, 2, "closing during quit keeps the list")
        Session.isTerminating = false

        // Closing a window normally updates it; files deleted since are skipped.
        b.close()
        t.expect(Session.documentsToRestore().map(\.lastPathComponent), ["note.md"], "closed and deleted documents dropped")
        a.close()
        t.expect(Session.documentsToRestore(), [], "nothing open")
    }
}
