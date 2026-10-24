import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var restoredDocuments = 0

    func applicationWillFinishLaunching(_ notification: Notification) {
        Theme.applySavedAppearance()
        NSApp.mainMenu = MainMenu.build()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        restoredDocuments = Session.restoreOpenDocuments()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Session.saveOpenDocuments()
        Session.isTerminating = true
        return .terminateNow
    }

    // Not "setAppearance:": views, windows and NSApp already have a setter by that name, and the
    // menu action would reach them first through the responder chain.
    @objc func chooseAppearance(_ sender: NSMenuItem) {
        Theme.appearance = Theme.Appearance(rawValue: sender.tag) ?? .system
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(chooseAppearance(_:)) {
            menuItem.state = menuItem.tag == Theme.appearance.rawValue ? .on : .off
        }
        return true
    }

    /// A blank document only when nothing was reopened.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { restoredDocuments == 0 }
}

enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu(appMenu()))
        main.addItem(submenu(fileMenu()))
        main.addItem(submenu(editMenu()))
        main.addItem(submenu(formatMenu()))
        main.addItem(submenu(viewMenu()))
        let window = windowMenu()
        main.addItem(submenu(window))
        NSApp.windowsMenu = window
        let help = NSMenu(title: "Help")
        main.addItem(submenu(help))
        NSApp.helpMenu = help
        return main
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(_ title: String, _ action: Selector?, _ key: String = "",
                             _ modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private static func arrow(_ key: Int) -> String {
        String(Character(UnicodeScalar(UInt16(key))!))
    }

    private static func appMenu() -> NSMenu {
        let name = ProcessInfo.processInfo.processName
        let menu = NSMenu(title: name)
        menu.addItem(item("About \(name)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(.separator())
        let services = NSMenu(title: "Services")
        let servicesItem = submenu(services)
        menu.addItem(servicesItem)
        NSApp.servicesMenu = services
        menu.addItem(.separator())
        menu.addItem(item("Hide \(name)", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit \(name)", #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(item("New", #selector(NSDocumentController.newDocument(_:)), "n"))
        menu.addItem(item("Open…", #selector(NSDocumentController.openDocument(_:)), "o"))

        let recent = NSMenu(title: "Open Recent")
        recent.delegate = RecentDocumentsMenu.shared
        menu.addItem(submenu(recent))

        menu.addItem(.separator())
        menu.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))
        menu.addItem(item("Save…", #selector(NSDocument.save(_:)), "s"))
        menu.addItem(item("Duplicate", #selector(NSDocument.duplicate(_:)), "s", [.command, .shift]))
        menu.addItem(item("Rename…", #selector(NSDocument.rename(_:))))
        menu.addItem(item("Move To…", #selector(NSDocument.move(_:))))
        menu.addItem(item("Revert to Saved", #selector(NSDocument.revertToSaved(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Export HTML…", #selector(MarkdownDocument.exportHTML(_:)), "e", [.command, .shift]))
        menu.addItem(item("Export PDF…", #selector(MarkdownDocument.exportPDF(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Page Setup…", #selector(NSDocument.runPageLayout(_:)), "p", [.command, .shift]))
        menu.addItem(item("Print…", #selector(NSDocument.printDocument(_:)), "p"))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(item("Undo", Selector(("undo:")), "z"))
        menu.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        menu.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        menu.addItem(item("Copy HTML", #selector(EditorSplitViewController.copyHTML(_:)), "c", [.command, .option]))
        menu.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        menu.addItem(item("Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .option, .shift]))
        menu.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        menu.addItem(.separator())

        let find = NSMenu(title: "Find")
        func findItem(_ title: String, _ key: String, _ tag: NSTextFinder.Action, _ mods: NSEvent.ModifierFlags = [.command]) {
            let i = item(title, #selector(NSTextView.performFindPanelAction(_:)), key, mods)
            i.tag = tag.rawValue
            find.addItem(i)
        }
        findItem("Find…", "f", .showFindInterface)
        findItem("Find and Replace…", "f", .showReplaceInterface, [.command, .option])
        findItem("Find Next", "g", .nextMatch)
        findItem("Find Previous", "g", .previousMatch, [.command, .shift])
        findItem("Use Selection for Find", "e", .setSearchString)
        find.addItem(item("Jump to Selection", #selector(NSResponder.centerSelectionInVisibleArea(_:)), "j"))
        menu.addItem(submenu(find))

        let spelling = NSMenu(title: "Spelling and Grammar")
        spelling.addItem(item("Check Spelling While Typing", #selector(NSTextView.toggleContinuousSpellChecking(_:))))
        menu.addItem(submenu(spelling))
        return menu
    }

    private static func formatMenu() -> NSMenu {
        let menu = NSMenu(title: "Format")
        menu.addItem(item("Bold", #selector(EditorTextView.formatBold(_:)), "b"))
        menu.addItem(item("Italic", #selector(EditorTextView.formatItalic(_:)), "i"))
        menu.addItem(item("Strikethrough", #selector(EditorTextView.formatStrikethrough(_:)), "x", [.command, .shift]))
        menu.addItem(item("Inline Code", #selector(EditorTextView.formatInlineCode(_:)), "`", [.control]))
        menu.addItem(item("Link", #selector(EditorTextView.formatLink(_:)), "k"))
        menu.addItem(.separator())
        menu.addItem(item("Toggle To-Do", #selector(EditorTextView.toggleTodo(_:)), "l"))
        menu.addItem(item("Move Item Up", #selector(EditorTextView.moveItemUp(_:)), arrow(NSUpArrowFunctionKey), [.command, .shift]))
        menu.addItem(item("Move Item Down", #selector(EditorTextView.moveItemDown(_:)), arrow(NSDownArrowFunctionKey), [.command, .shift]))
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(item("Zoom In", #selector(EditorSplitViewController.zoomIn(_:)), "="))
        // Also accept ⌘+ (shift-=) for zoom in.
        let plus = item("Zoom In", #selector(EditorSplitViewController.zoomIn(_:)), "+")
        plus.isHidden = true
        plus.allowsKeyEquivalentWhenHidden = true
        menu.addItem(plus)
        menu.addItem(item("Zoom Out", #selector(EditorSplitViewController.zoomOut(_:)), "-"))
        menu.addItem(item("Actual Size", #selector(EditorSplitViewController.resetZoom(_:)), "0"))
        menu.addItem(.separator())
        menu.addItem(item("Show Outline", #selector(EditorSplitViewController.toggleOutline(_:)), "s", [.command, .control]))
        menu.addItem(item("Hide Preview", #selector(EditorSplitViewController.togglePreview(_:)), "p", [.command, .option]))
        menu.addItem(item("Hide Editor", #selector(EditorSplitViewController.toggleEditor(_:)), "e", [.command, .option]))
        menu.addItem(.separator())
        let appearance = NSMenu(title: "Appearance")
        for option in Theme.Appearance.allCases {
            let i = item(option.title, #selector(AppDelegate.chooseAppearance(_:)))
            i.tag = option.rawValue
            appearance.addItem(i)
        }
        menu.addItem(submenu(appearance))
        menu.addItem(.separator())
        menu.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }
}

public enum LightdownApp {
    private static let delegate = AppDelegate()

    public static func run() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
