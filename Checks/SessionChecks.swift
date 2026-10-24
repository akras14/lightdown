import AppKit
@testable import LightdownKit

@MainActor
func sessionChecks(_ t: Checker) {
    t.group("open recent menu") {
        let menu = NSMenu()
        let saved = RecentDocumentsMenu.shared.recentURLs
        defer { RecentDocumentsMenu.shared.recentURLs = saved }
        RecentDocumentsMenu.shared.recentURLs = {
            [URL(fileURLWithPath: "/a/notes.md"), URL(fileURLWithPath: "/b/notes.md"), URL(fileURLWithPath: "/c/todo.md")]
        }
        RecentDocumentsMenu.shared.menuNeedsUpdate(menu)
        t.expect(menu.items.map(\.title), ["notes.md — a", "notes.md — b", "todo.md", "", "Clear Menu"],
                 "recent files, same names told apart, then Clear Menu")
        t.expect(menu.items.first?.toolTip, "/a/notes.md", "full path as tooltip")

        RecentDocumentsMenu.shared.recentURLs = { [] }
        RecentDocumentsMenu.shared.menuNeedsUpdate(menu)
        t.expect(menu.items.map(\.title), ["Clear Menu"], "empty list")

        let built = MainMenu.build()
        let recent = built.items.first { $0.title == "File" }?.submenu?.items.first { $0.title == "Open Recent" }
        t.expect(recent?.submenu?.delegate === RecentDocumentsMenu.shared, true, "File > Open Recent is wired up")
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
