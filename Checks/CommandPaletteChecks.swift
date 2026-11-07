import AppKit
@testable import LightdownKit

/// Sends one key press, such as an arrow or Escape, to the window.
@MainActor
private func press(_ characters: String, keyCode: UInt16, in window: NSWindow,
                   modifiers: NSEvent.ModifierFlags = []) {
    for kind in [NSEvent.EventType.keyDown, .keyUp] {
        let event = NSEvent.keyEvent(with: kind, location: .zero, modifierFlags: modifiers,
                                     timestamp: ProcessInfo.processInfo.systemUptime,
                                     windowNumber: window.windowNumber, context: nil, characters: characters,
                                     charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
        NSApp.sendEvent(event)
    }
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
}

@MainActor private func pressDown(_ w: NSWindow) {
    press(String(UnicodeScalar(UInt16(NSDownArrowFunctionKey))!), keyCode: 125, in: w, modifiers: [.function, .numericPad])
}
@MainActor private func pressUp(_ w: NSWindow) {
    press(String(UnicodeScalar(UInt16(NSUpArrowFunctionKey))!), keyCode: 126, in: w, modifiers: [.function, .numericPad])
}
@MainActor private func pressEscape(_ w: NSWindow) { press("\u{1b}", keyCode: 53, in: w) }

@MainActor
func commandPaletteChecks(_ t: Checker) {
    t.group("palette shows shortcuts like the menus") {
        func item(_ key: String, _ mods: NSEvent.ModifierFlags) -> NSMenuItem {
            let i = NSMenuItem(title: "x", action: nil, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            return i
        }
        let left = String(UnicodeScalar(UInt16(NSLeftArrowFunctionKey))!)
        t.expect(CommandPalette.shortcut(for: item("b", [.command])), "⌘B")
        t.expect(CommandPalette.shortcut(for: item("p", [.command, .shift])), "⇧⌘P")
        t.expect(CommandPalette.shortcut(for: item(left, [.command, .option, .shift])), "⌥⇧⌘←")
        t.expect(CommandPalette.shortcut(for: item("`", [.control])), "⌃`")
        t.expect(CommandPalette.shortcut(for: item("Z", [.command])), "⇧⌘Z", "uppercase implies Shift")
        t.expect(CommandPalette.shortcut(for: item("", [.command])), "", "no shortcut")
    }

    t.group("palette matching") {
        t.expect(CommandPalette.match("cas", in: "Collapse All Sections")?.indices, [0, 9, 13], "word starts")
        t.expect(CommandPalette.match("zoom in", in: "Zoom In")?.indices, [0, 1, 2, 3, 5, 6], "spaces ignored")
        t.expect(CommandPalette.match("ZOOM", in: "zoom out")?.indices, [0, 1, 2, 3], "ignores case")
        t.expect(CommandPalette.match("xyz", in: "Bold") == nil, true, "no match")
        t.expect(CommandPalette.match("", in: "Bold")?.indices, [], "empty query matches everything")
        let prefix = CommandPalette.match("col", in: "Collapse All Sections")!.score
        let scattered = CommandPalette.match("col", in: "Copy HTML Link")?.score ?? .min
        t.expect(prefix > scattered, true, "a run of letters beats scattered ones")
    }

    t.group("palette menu shortcut") {
        let view = MainMenu.build().items.lazy.compactMap { $0.submenu }.first { $0.title == "View" }
        let item = view?.items.first { $0.action == #selector(DocumentViewController.showCommandPalette(_:)) }
        t.expect(item?.keyEquivalent, "p", "⇧⌘P")
        t.expect(item?.keyEquivalentModifierMask, [.command, .shift], "⇧⌘P")
    }

    /// A document in the key window with the app's menu, as when the palette opens in the app.
    @MainActor func session(_ text: String, caret: Int = 0,
                            _ body: (DocumentHarness, NSWindow, DocumentViewController) -> Void) {
        let savedMenu = NSApp.mainMenu, savedRecent = CommandPalette.recent
        NSApp.mainMenu = MainMenu.build()
        CommandPalette.recent = []
        let h = DocumentHarness(text)
        let window = h.editor.view.window!
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(h.editor.textView)
        h.editor.textView.setSelectedRange(NSRange(location: caret, length: 0))
        body(h, window, window.contentViewController as! DocumentViewController)
        window.orderOut(nil)
        h.close()
        NSApp.mainMenu = savedMenu
        CommandPalette.recent = savedRecent
    }

    t.group("palette lists the menu commands") {
        session("# One\n\ntext\n") { h, window, _ in
            let commands = CommandPalette.commands(in: NSApp.mainMenu!, for: window)
            func find(_ title: String) -> PaletteCommand? { commands.first { $0.title == title } }
            t.expect(find("Collapse All Sections")?.path, ["View"])
            t.expect(find("Collapse All Sections")?.shortcut, "⌥⇧⌘←")
            t.expect(find("Bold")?.path, ["Format"])
            t.expect(find("Bold")?.shortcut, "⌘B")
            t.expect(find("Bold")?.target === h.editor.textView, true, "sent to the editor that had focus")
            t.expect(find("Find Next")?.path, ["Edit", "Find"], "submenu path")
            t.expect(find("Show Outline") != nil || find("Hide Outline") != nil, true, "titles as validated")
            t.expect(find("Expand All Sections") == nil, true, "disabled items left out: nothing collapsed")
            t.expect(find("Show Tab 1") == nil, true, "hidden items left out")
            t.expect(commands.contains { $0.path.contains("Services") }, false, "no Services")
            t.expect(commands.contains { $0.item.action == #selector(DocumentViewController.showCommandPalette(_:)) },
                     false, "not itself")
            t.expect(commands.contains { $0.item.isSeparatorItem || $0.item.submenu != nil }, false, "only commands")
            t.expect(Set(commands.map(\.key)).count, commands.count, "each has its own key")
        }
    }

    t.group("palette ranking") {
        session("# One\n") { _, window, _ in
            let commands = CommandPalette.commands(in: NSApp.mainMenu!, for: window)
            func top(_ query: String, recent: [String] = []) -> String? {
                CommandPalette.results(commands, query: query, recent: recent).first?.command.title
            }
            t.expect(top("coll all"), "Collapse All Sections")
            t.expect(top("bold"), "Bold")
            t.expect(top("zoom out"), "Zoom Out")
            t.expect(top("format link"), "Link", "matches the menu name too")
            t.expect(CommandPalette.results(commands, query: "qqqxxx", recent: []).isEmpty, true, "nothing matches")
            t.expect(CommandPalette.results(commands, query: "", recent: []).map(\.command.title),
                     commands.map(\.title), "no query: everything, in menu order")
            let bold = commands.first { $0.title == "Bold" }?.key ?? "missing"
            t.expect(top("", recent: [bold]), "Bold", "recently used first")
            let link = CommandPalette.results(commands, query: "format link", recent: []).first
            t.expect(link?.titleIndices, [0, 1, 2, 3], "highlights only the title's part of the match")
        }
    }

    t.group("running a command from the palette") {
        session("hello world", caret: 2) { h, window, vc in
            vc.showCommandPalette(nil)
            let palette = vc.palette
            t.expect(palette.isOpen, true, "opens")
            t.expect((window.firstResponder as? NSTextView)?.delegate === palette.searchField, true, "typing goes to the search field")
            type("bold", in: window)
            t.expect(palette.results.first?.command.title, "Bold", "filters as you type")
            t.expect(palette.selectedIndex, 0, "first result selected")
            type("\n", in: window)
            t.expect(palette.isOpen, false, "closes after running")
            t.expect(h.text, "**hello** world", "ran Bold on the word at the caret")
            t.expect(window.firstResponder === h.editor.textView, true, "focus back in the editor")

            vc.showCommandPalette(nil)
            t.expect(palette.searchField.stringValue, "", "opens empty")
            t.expect(palette.results.first?.command.title, "Bold", "recently used first")
            pressEscape(window)
        }
    }

    t.group("palette commands reach the editor, not the search field") {
        session("one two three", caret: 3) { h, window, vc in
            vc.showCommandPalette(nil)
            type("select all", in: window)
            t.expect(vc.palette.results.first?.command.title, "Select All")
            type("\n", in: window)
            t.expect(h.editor.textView.selectedRange(), NSRange(location: 0, length: 13), "selected the document")
        }
    }

    t.group("palette keys") {
        session("# One\n", caret: 0) { h, window, vc in
            let palette = vc.palette
            let zoom = Zoom.level
            vc.showCommandPalette(nil)
            type("zoom", in: window)
            t.expect(palette.results.count >= 2, true, "several matches (\(palette.results.map(\.command.title)))")
            pressDown(window)
            t.expect(palette.selectedIndex, 1, "↓ moves down")
            pressUp(window)
            pressUp(window)
            t.expect(palette.selectedIndex, 0, "↑ stops at the top")
            pressEscape(window)
            t.expect(palette.isOpen, false, "Esc closes")
            t.expect(Zoom.level, zoom, "Esc runs nothing")
            t.expect(window.firstResponder === h.editor.textView, true, "focus back in the editor")

            vc.showCommandPalette(nil)
            vc.showCommandPalette(nil)
            t.expect(palette.isOpen, false, "⇧⌘P again closes it")
            t.expect(window.firstResponder === h.editor.textView, true, "focus back after toggling")
        }
    }
}
