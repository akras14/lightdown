import AppKit
@testable import LightdownKit

@MainActor
func tabShortcutChecks(_ t: Checker) {
    t.group("tab shortcut labels") {
        t.expect(TabShortcuts.label(forTabAt: 0), "⌘1")
        t.expect(TabShortcuts.label(forTabAt: 8), "⌘9")
        t.expect(TabShortcuts.label(forTabAt: 9), nil, "no shortcut past the ninth tab")
    }

    t.group("tab shortcut menu") {
        let menu = MainMenu.build()
        var items: [NSMenuItem] = []
        func collect(_ m: NSMenu) { for i in m.items { items.append(i); if let s = i.submenu { collect(s) } } }
        collect(menu)
        let tabItems = items.filter { $0.action == #selector(AppDelegate.showTabNumber(_:)) }
        t.expect(tabItems.map(\.keyEquivalent), (1...9).map(String.init), "⌘1–⌘9")
        t.expect(tabItems.map(\.tag), Array(1...9), "tags are the tab numbers")
        t.expect(tabItems.allSatisfy { $0.keyEquivalentModifierMask == [.command] }, true, "command only")
    }

    t.group("switching tabs") {
        let docs = (0..<3).map { DocumentHarness("# Tab \($0)\n", name: "tab\($0).md") }
        defer { docs.forEach { $0.close() } }
        let windows = docs.map { $0.editor.view.window! }
        windows[0].addTabbedWindow(windows[1], ordered: .above)
        windows[1].addTabbedWindow(windows[2], ordered: .above)
        TabShortcuts.refresh()
        @MainActor func labels() -> [String?] { windows.map(TabShortcuts.shownLabel) }
        t.expect(labels(), ["⌘1", "⌘2", "⌘3"], "each tab shows its shortcut")
        // In the title, so the name and shortcut are centred together.
        t.expect(windows[1].tab.attributedTitle?.string, "\(windows[1].title)  ⌘2", "shortcut follows the name")
        t.expect(windows[1].tab.accessoryView == nil, true, "no accessory view")
        windows[1].title = "renamed.md"
        t.expect(waitUntil { windows[1].tab.attributedTitle?.string == "renamed.md  ⌘2" }, true,
                 "follows a rename (\(windows[1].tab.attributedTitle?.string ?? "nil"))")

        t.expect(TabShortcuts.select(1, from: windows[2]), true, "⌘1")
        t.expect(windows[0].tabGroup?.selectedWindow === windows[0], true, "first tab selected")
        t.expect(TabShortcuts.select(3, from: windows[0]), true, "⌘3")
        t.expect(windows[0].tabGroup?.selectedWindow === windows[2], true, "third tab selected")
        t.expect(TabShortcuts.select(4, from: windows[0]), false, "⌘4 with three tabs does nothing")
        t.expect(windows[0].tabGroup?.selectedWindow === windows[2], true, "still on the third tab")

        // Reordering renumbers the labels.
        let group = windows[0].tabGroup!
        group.removeWindow(windows[2])
        group.insertWindow(windows[2], at: 0)
        t.expect(waitUntil { labels() == ["⌘2", "⌘3", "⌘1"] }, true, "renumbered after a reorder (\(labels()))")

        // Closing a tab renumbers the rest.
        docs[2].close()
        t.expect(waitUntil { labels()[0...1] == ["⌘1", "⌘2"] }, true, "renumbered after a close (\(labels()))")
    }

    t.group("more than nine tabs") {
        let docs = (0..<10).map { DocumentHarness("# Tab \($0)\n", name: "tab\($0).md") }
        defer { docs.forEach { $0.close() } }
        let windows = docs.map { $0.editor.view.window! }
        for w in windows.dropFirst() { windows[0].tabGroup!.addWindow(w) }
        TabShortcuts.refresh()
        t.expect(TabShortcuts.shownLabel(windows[8]), "⌘9", "ninth tab")
        t.expect(TabShortcuts.shownLabel(windows[9]), nil, "tenth tab has no label")
        t.expect(TabShortcuts.select(9, from: windows[0]), true, "⌘9 goes to the ninth tab, not the last")
        t.expect(windows[0].tabGroup?.selectedWindow === windows[8], true, "ninth tab selected")
    }
}
