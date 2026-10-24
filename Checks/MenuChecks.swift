import AppKit
import WebKit
@testable import LightdownKit

/// Menu actions travel the responder chain (focused view → window → app → delegate), so an action
/// named like a built-in AppKit method gets handled by the wrong object. `setAppearance:` did exactly
/// that: the focused text view took the menu item as its appearance and crashed on the next redraw.
@MainActor
func menuChecks(_ t: Checker) {
    t.group("menu actions") {
        let menu = MainMenu.build()
        var items: [NSMenuItem] = []
        func collect(_ m: NSMenu) { for i in m.items { items.append(i); if let s = i.submenu { collect(s) } } }
        collect(menu)

        let ours: [AnyClass] = [AppDelegate.self, MarkdownDocument.self, EditorSplitViewController.self, EditorTextView.self]
        let builtIns: [AnyClass] = [NSView.self, NSTextView.self, NSTableView.self, WKWebView.self, NSWindow.self,
                                    NSWindowController.self, NSViewController.self, NSSplitViewController.self,
                                    NSApplication.self, NSDocument.self]
        var checked = 0
        for item in items {
            guard let action = item.action else { continue }
            // Only actions introduced by our classes (not overrides like paste:).
            let introducedByUs = ours.contains { cls in
                class_getInstanceMethod(cls, action) != nil &&
                    (class_getSuperclass(cls).map { class_getInstanceMethod($0, action) == nil } ?? true)
            }
            guard introducedByUs else { continue }
            checked += 1
            let clash: AnyClass? = builtIns.first { $0.instancesRespond(to: action) }
            t.expect(clash.map { "\($0)" }, nil, "\(item.title) → \(NSStringFromSelector(action)) clashes with")
        }
        t.expect(checked > 10, true, "checked our menu actions (\(checked))")
    }

    t.group("appearance through the menu") {
        let saved = Theme.appearance
        defer { Theme.appearance = saved }
        let h = DocumentHarness("# Hi\n")
        defer { h.close() }

        let item = NSMenuItem(title: "Dark", action: #selector(AppDelegate.chooseAppearance(_:)), keyEquivalent: "")
        item.tag = Theme.Appearance.dark.rawValue
        let delegate = AppDelegate()
        // Walk the chain the way AppKit does when the editor has focus.
        let handler = NSApp.target(forAction: item.action!, to: nil, from: item)
        let chainHandles = [h.editor.textView as NSResponder, h.editor.view.window!].contains { $0.responds(to: item.action!) }
        t.expect(chainHandles, false, "focused view and window don't swallow the action (handler: \(String(describing: handler)))")
        delegate.chooseAppearance(item)
        t.expect(NSApp.appearance?.name, .darkAqua, "Dark applied")
        t.expect(h.editor.textView.appearance == nil, true, "text view's own appearance untouched")
    }
}
