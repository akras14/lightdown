import AppKit

/// ⌘1–⌘9 select the first nine tabs of a window, and each of those tabs shows its shortcut at
/// its trailing edge. Tabs past the ninth get neither.
enum TabShortcuts {
    static let limit = 9

    static func label(forTabAt index: Int) -> String? {
        index < limit ? "⌘\(index + 1)" : nil
    }

    /// Selects tab `number` (1-based) in the window's tab group. Returns false if there's no such tab.
    @MainActor @discardableResult
    static func select(_ number: Int, from window: NSWindow) -> Bool {
        let tabs = window.tabGroup?.windows ?? [window]
        guard number >= 1, number <= min(limit, tabs.count) else { return false }
        window.tabGroup?.selectedWindow = tabs[number - 1]
        tabs[number - 1].makeKeyAndOrderFront(nil)
        return true
    }

    /// The shortcut shown on the window's tab, if any.
    @MainActor static func shownLabel(_ window: NSWindow) -> String? {
        guard let title = window.tab.attributedTitle, title.length > 0 else { return nil }
        return title.attribute(shortcutKey, at: title.length - 1, effectiveRange: nil) as? String
    }

    private static let shortcutKey = NSAttributedString.Key("LightdownTabShortcut")

    /// The name followed by the dimmed shortcut. Part of the title rather than an accessory view,
    /// which the tab would leave out when centring the name.
    private static func title(_ name: String, shortcut: String) -> NSAttributedString {
        let title = NSMutableAttributedString(string: name + "  ")
        title.append(NSAttributedString(string: shortcut, attributes: [
            .foregroundColor: NSColor.secondaryLabelColor, shortcutKey: shortcut,
        ]))
        return title
    }

    /// Watched tab groups and windows, so reordering, closing and renaming update the titles.
    @MainActor private static let observed = NSMapTable<NSObject, NSKeyValueObservation>.weakToStrongObjects()

    @MainActor private static func watch<Object: NSObject, Value>(_ object: Object, _ keyPath: KeyPath<Object, Value>) {
        guard observed.object(forKey: object) == nil else { return }
        observed.setObject(object.observe(keyPath) { _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { refresh() } }
        }, forKey: object)
    }

    @MainActor private static let observeWindows: Void = {
        // New tabs and windows become key; tabs dragged between windows change their group.
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification, NSWindow.willCloseNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { refresh() } }
            }
        }
    }()

    /// Updates the shortcut in every document window's tab title.
    @MainActor static func refresh() {
        _ = observeWindows
        let windows = NSDocumentController.shared.documents.flatMap(\.windowControllers).compactMap(\.window)
        for window in windows {
            if let group = window.tabGroup { watch(group, \.windows) }
            watch(window, \.title)
            let tabs = window.tabGroup?.windows ?? [window]
            let shortcut = tabs.firstIndex(of: window).flatMap(label(forTabAt:))
            let newTitle = shortcut.map { title(window.title, shortcut: $0) }
            if window.tab.attributedTitle != newTitle { window.tab.attributedTitle = newTitle }
        }
    }
}
