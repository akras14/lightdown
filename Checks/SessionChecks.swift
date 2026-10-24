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

    t.group("no blank document when reopening") {
        let key = "openDocuments"
        let savedList = UserDefaults.standard.stringArray(forKey: key)
        defer { UserDefaults.standard.set(savedList, forKey: key) }
        let h = DocumentHarness("x")
        defer { h.close() }

        let delegate = AppDelegate()
        UserDefaults.standard.set([h.url.path], forKey: key)
        delegate.applicationWillFinishLaunching(Notification(name: NSApplication.willFinishLaunchingNotification))
        t.expect(delegate.applicationShouldOpenUntitledFile(NSApp), false, "documents to reopen: no Untitled")

        UserDefaults.standard.set([String](), forKey: key)
        delegate.applicationWillFinishLaunching(Notification(name: NSApplication.willFinishLaunchingNotification))
        t.expect(delegate.applicationShouldOpenUntitledFile(NSApp), true, "nothing to reopen: Untitled")
        NSApp.mainMenu = nil
    }

    t.group("empty Untitled closes when you move on") {
        @MainActor func untitled() -> (MarkdownDocument, EditorSplitViewController) {
            let doc = MarkdownDocument()
            doc.makeWindowControllers()
            NSDocumentController.shared.addDocument(doc)
            return (doc, (doc.windowControllers.first!.contentViewController as! DocumentViewController).editor)
        }
        let other = DocumentHarness("# A real document\n")
        defer { other.close() }
        let otherWindow = other.editor.view.window!

        let (blank, blankEditor) = untitled()
        blankEditor.closeIfEmptyUntitled(newMainWindow: nil)
        t.expect(NSDocumentController.shared.documents.contains(blank), true, "stays while nothing else is in front")
        blankEditor.closeIfEmptyUntitled(newMainWindow: blankEditor.view.window)
        t.expect(NSDocumentController.shared.documents.contains(blank), true, "stays while it's the front document")
        blankEditor.closeIfEmptyUntitled(newMainWindow: otherWindow)
        t.expect(NSDocumentController.shared.documents.contains(blank), false, "closes when another document comes forward")

        let (typed, typedEditor) = untitled()
        typedEditor.textView.string = "some notes"
        typedEditor.closeIfEmptyUntitled(newMainWindow: otherWindow)
        t.expect(NSDocumentController.shared.documents.contains(typed), true, "an Untitled with text is kept")
        typed.close()

        let (panelCase, panelEditor) = untitled()
        panelEditor.closeIfEmptyUntitled(newMainWindow: NSPanel())
        t.expect(NSDocumentController.shared.documents.contains(panelCase), true,
                 "a non-document window (e.g. the Open panel) doesn't close it")
        panelCase.close()
    }
}
