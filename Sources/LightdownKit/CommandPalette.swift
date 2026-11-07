import AppKit

/// A menu command the palette can run.
struct PaletteCommand {
    let title: String
    /// The menus it sits in, such as ["Edit", "Find"].
    let path: [String]
    let shortcut: String
    let isOn: Bool
    /// Identifies the command for "recently used", even when its title changes (Show/Hide Outline).
    fileprivate(set) var key: String
    let item: NSMenuItem
    /// Who handles it, found from the window's focus at the time.
    let target: AnyObject?
}

struct PaletteResult {
    let command: PaletteCommand
    let score: Int
    /// Characters of the title the query matched, to show in bold.
    let titleIndices: [Int]
}

/// ⇧⌘P lists every command in the menu bar, as in VS Code and Sublime Text. It reads the menus
/// each time it opens, so new menu items show up without being registered anywhere.
enum CommandPalette {
    /// The commands available in `window` now: enabled, visible, with the titles the menus would show.
    @MainActor static func commands(in menu: NSMenu, for window: NSWindow?) -> [PaletteCommand] {
        var result: [PaletteCommand] = []
        collect(menu, path: [], window: window, into: &result)
        // Window and Open Recent entries share an action: tell them apart by title.
        var counts: [String: Int] = [:]
        for command in result { counts[command.key, default: 0] += 1 }
        for i in result.indices where counts[result[i].key]! > 1 {
            result[i].key += "/" + result[i].title
        }
        return result
    }

    @MainActor private static func collect(_ menu: NSMenu, path: [String], window: NSWindow?,
                                           into result: inout [PaletteCommand]) {
        menu.delegate?.menuNeedsUpdate?(menu)   // menus that fill themselves in when opened
        for item in menu.items {
            guard !item.isSeparatorItem, !item.isHidden, !item.isAlternate, item.view == nil else { continue }
            if let submenu = item.submenu {
                guard submenu !== NSApp.servicesMenu, submenu.title != "Services" else { continue }
                collect(submenu, path: path + [item.title], window: window, into: &result)
                continue
            }
            guard let action = item.action,
                  action != #selector(DocumentViewController.showCommandPalette(_:)) else { continue }
            let target = item.target ?? self.target(for: action, from: item, in: window)
            guard target != nil, validate(item, target: target, autoenables: menu.autoenablesItems) else { continue }
            let key = (path + [NSStringFromSelector(action), String(item.tag)]).joined(separator: "/")
            result.append(PaletteCommand(title: item.title, path: path, shortcut: shortcut(for: item),
                                         isOn: item.state == .on, key: key, item: item, target: target))
        }
    }

    /// The object a menu item's action would reach if `window` were key: the responder chain from its
    /// focus, then its delegate, window controller and document, then the app and its delegate.
    /// Worked out here rather than with NSApp.target(forAction:), which follows the key window.
    @MainActor static func target(for action: Selector, from sender: Any?, in window: NSWindow?) -> AnyObject? {
        var candidates: [AnyObject] = []
        var responder = window?.firstResponder
        while let next = responder {
            candidates.append(next)
            responder = next.nextResponder
        }
        if let window {
            candidates.append(window)
            if let delegate = window.delegate { candidates.append(delegate) }
            if let controller = window.windowController {
                candidates.append(controller)
                if let document = controller.document as AnyObject? { candidates.append(document) }
            }
        }
        candidates.append(NSApp)
        if let delegate = NSApp.delegate { candidates.append(delegate) }
        candidates.append(NSDocumentController.shared)
        for candidate in candidates {
            if let supplemental = (candidate as? NSResponder)?.supplementalTarget(forAction: action, sender: sender) {
                return supplemental as AnyObject
            }
            if candidate.responds(to: action) { return candidate }
        }
        return nil
    }

    /// Asks the target, as the menu would before showing the item. This also updates titles, such
    /// as Show Outline becoming Hide Outline.
    @MainActor private static func validate(_ item: NSMenuItem, target: AnyObject?, autoenables: Bool) -> Bool {
        guard autoenables else { return item.isEnabled }
        if let validator = target as? NSMenuItemValidation { return validator.validateMenuItem(item) }
        if let validator = target as? NSUserInterfaceValidations { return validator.validateUserInterfaceItem(item) }
        return true
    }

    /// The shortcut as the menu shows it, such as ⌥⇧⌘←.
    static func shortcut(for item: NSMenuItem) -> String {
        let key = item.keyEquivalent
        guard !key.isEmpty else { return "" }
        var modifiers = item.keyEquivalentModifierMask
        if key != key.lowercased() { modifiers.insert(.shift) }   // an uppercase key implies Shift
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + symbol(for: key)
    }

    private static func symbol(for key: String) -> String {
        guard let scalar = key.unicodeScalars.first else { return key }
        switch Int(scalar.value) {
        case NSUpArrowFunctionKey: return "↑"
        case NSDownArrowFunctionKey: return "↓"
        case NSLeftArrowFunctionKey: return "←"
        case NSRightArrowFunctionKey: return "→"
        case NSDeleteFunctionKey: return "⌦"
        case 0x0D, 0x03: return "↩"
        case 0x09: return "⇥"
        case 0x1B: return "⎋"
        case 0x08, 0x7F: return "⌫"
        case 0x20: return "Space"
        default: return key.uppercased()
        }
    }

    // MARK: Matching

    /// Fuzzy match: the query's letters in order, anywhere in `text`, ignoring case and spaces.
    /// Letters that start words and runs of letters score higher, so "cas" finds Collapse All
    /// Sections. Returns the best score and the matched character offsets, or nil.
    static func match(_ query: String, in text: String) -> (score: Int, indices: [Int])? {
        let q = query.filter { !$0.isWhitespace }.map { $0.lowercased() }
        guard !q.isEmpty else { return (0, []) }
        let chars = Array(text)
        let t = chars.map { $0.lowercased() }
        let n = q.count, m = t.count
        guard n <= m else { return nil }

        func startsWord(_ j: Int) -> Bool {
            j == 0 || !(chars[j - 1].isLetter || chars[j - 1].isNumber) ||
                (chars[j].isUppercase && chars[j - 1].isLowercase)
        }
        // score[i][j]: the best score for the first i + 1 query letters with letter i at text offset j.
        let none = Int.min
        var score = [[Int]](repeating: [Int](repeating: none, count: m), count: n)
        var previous = [[Int]](repeating: [Int](repeating: -1, count: m), count: n)
        for j in 0..<m where t[j] == q[0] {
            score[0][j] = 1 + (startsWord(j) ? 8 : 0) - min(j, 3)
        }
        for i in 1..<n {
            for j in i..<m where t[j] == q[i] {
                let own = 1 + (startsWord(j) ? 8 : 0)
                for k in (i - 1)..<j where score[i - 1][k] != none {
                    let gap = j - k - 1
                    let s = score[i - 1][k] + own + (gap == 0 ? 6 : -min(gap, 5))
                    if s > score[i][j] { score[i][j] = s; previous[i][j] = k }
                }
            }
        }
        guard let end = (0..<m).filter({ score[n - 1][$0] != none })
            .max(by: { score[n - 1][$0] < score[n - 1][$1] }) else { return nil }
        var indices = [end]
        var j = end
        for i in stride(from: n - 1, to: 0, by: -1) {
            j = previous[i][j]
            indices.insert(j, at: 0)
        }
        return (score[n - 1][end], indices)
    }

    /// Matches against the title, or the menu path and title ("format link" finds Format › Link).
    private static func rank(_ command: PaletteCommand, _ query: String) -> PaletteResult? {
        var best = match(query, in: command.title).map {
            PaletteResult(command: command, score: $0.score, titleIndices: $0.indices)
        }
        let prefix = command.path.joined(separator: " ") + " "
        if let full = match(query, in: prefix + command.title), full.score - 3 > best?.score ?? .min {
            let offset = prefix.count
            best = PaletteResult(command: command, score: full.score - 3,
                                 titleIndices: full.indices.filter { $0 >= offset }.map { $0 - offset })
        }
        return best
    }

    /// Best matches first. With no query, everything, recently used first and then in menu order.
    static func results(_ commands: [PaletteCommand], query: String, recent: [String]) -> [PaletteResult] {
        if query.allSatisfy(\.isWhitespace) {
            var order: [String: Int] = [:]
            for (i, key) in recent.enumerated() where order[key] == nil { order[key] = i }
            return commands.enumerated()
                .sorted { (order[$0.element.key] ?? .max, $0.offset) < (order[$1.element.key] ?? .max, $1.offset) }
                .map { PaletteResult(command: $0.element, score: 0, titleIndices: []) }
        }
        return commands.enumerated()
            .compactMap { i, command in rank(command, query).map { (result: $0, index: i) } }
            .sorted { ($0.result.score, -$0.index) > ($1.result.score, -$1.index) }
            .map(\.result)
    }

    // MARK: Recently used

    static let recentLimit = 8
    private static let recentDefaultsKey = "CommandPaletteRecent"

    /// Keys of the commands last run from the palette, most recent first.
    static var recent: [String] {
        get { UserDefaults.standard.stringArray(forKey: recentDefaultsKey) ?? [] }
        set { UserDefaults.standard.set(Array(newValue.prefix(recentLimit)), forKey: recentDefaultsKey) }
    }

    static func noteUsed(_ command: PaletteCommand) {
        recent = [command.key] + recent.filter { $0 != command.key }
    }
}

// MARK: - The palette

/// A search field and list over the top of the window. It's part of the window rather than a
/// panel of its own, so when it closes the editor gets focus back and the chosen command reaches
/// the editor, as if it had been picked from the menu.
@MainActor
final class CommandPaletteController: NSObject, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    let searchField = NSTextField()
    private(set) var results: [PaletteResult] = []
    var selectedIndex: Int { tableView.selectedRow }
    var isOpen: Bool { overlay.superview != nil }

    private var commands: [PaletteCommand] = []
    private weak var returnFocus: NSResponder?
    private let overlay = PaletteOverlay()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "No matching commands")
    private var listHeight: NSLayoutConstraint!

    private static let rowHeight: CGFloat = 28
    private static let visibleRows = 12
    private static let width: CGFloat = 600

    override init() {
        super.init()
        build()
    }

    /// Lists the menu's commands as they are now, then moves focus to the search field.
    /// `fallbackFocus` gets focus back on close if nothing in the window had it.
    func open(in container: NSView, menu: NSMenu?, fallbackFocus: NSResponder?) {
        guard !isOpen, let window = container.window else { return }
        var focus = window.firstResponder
        // A text field being edited: return to the field, not its shared field editor.
        if let editor = focus as? NSTextView, editor.isFieldEditor, let field = editor.delegate as? NSResponder {
            focus = field
        }
        returnFocus = focus == nil || focus === window ? fallbackFocus : focus
        commands = menu.map { CommandPalette.commands(in: $0, for: window) } ?? []
        searchField.stringValue = ""
        overlay.frame = container.bounds
        container.addSubview(overlay)
        refresh()
        window.makeFirstResponder(searchField)
    }

    func close() {
        guard isOpen else { return }
        overlay.window?.makeFirstResponder(returnFocus)
        overlay.removeFromSuperview()
        commands = []
        results = []
        tableView.reloadData()
    }

    /// Closes the palette, then sends the command's action to the object it found when it opened,
    /// with the menu item as the sender, as choosing the item from the menu would.
    func run(_ index: Int) {
        guard results.indices.contains(index) else { return }
        let command = results[index].command
        close()
        CommandPalette.noteUsed(command)
        if let action = command.item.action {
            NSApp.sendAction(action, to: command.target, from: command.item)
        }
    }

    private func refresh() {
        results = CommandPalette.results(commands, query: searchField.stringValue, recent: CommandPalette.recent)
        tableView.reloadData()
        emptyLabel.isHidden = !results.isEmpty
        scrollView.isHidden = results.isEmpty
        listHeight.constant = CGFloat(max(1, min(results.count, Self.visibleRows))) * Self.rowHeight
        select(0)
    }

    private func select(_ row: Int) {
        guard !results.isEmpty else { return }
        let row = min(max(row, 0), results.count - 1)
        tableView.selectRowIndexes([row], byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    // MARK: Search field

    func controlTextDidChange(_ obj: Notification) { refresh() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUp(_:)): select(selectedIndex - 1)
        case #selector(NSResponder.moveDown(_:)): select(selectedIndex + 1)
        case #selector(NSResponder.pageUp(_:)), #selector(NSResponder.scrollPageUp(_:)):
            select(selectedIndex - Self.visibleRows)
        case #selector(NSResponder.pageDown(_:)), #selector(NSResponder.scrollPageDown(_:)):
            select(selectedIndex + Self.visibleRows)
        case #selector(NSResponder.insertNewline(_:)): run(selectedIndex)
        case #selector(NSResponder.cancelOperation(_:)): close()
        default: return false
        }
        return true
    }

    // MARK: List

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: PaletteCell.identifier, owner: nil) as? PaletteCell ?? PaletteCell()
        cell.show(results[row])
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { PaletteRowView() }

    @objc private func clicked(_ sender: Any?) {
        if tableView.clickedRow >= 0 { run(tableView.clickedRow) }
    }

    // MARK: Layout

    private func build() {
        overlay.wantsLayer = true
        overlay.autoresizingMask = [.width, .height]
        overlay.onClickOutside = { [weak self] in self?.close() }

        let panel = NSView()
        panel.wantsLayer = true
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowBlurRadius = 16
        shadow.shadowOffset = NSSize(width: 0, height: -4)
        panel.shadow = shadow

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .withinWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 1
        background.layer?.borderColor = NSColor.separatorColor.cgColor

        searchField.placeholderString = "Search commands"
        searchField.font = .systemFont(ofSize: 16)
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.cell?.usesSingleLineMode = true
        searchField.cell?.lineBreakMode = .byTruncatingTail
        searchField.delegate = self

        let separator = NSBox()
        separator.boxType = .separator

        let column = NSTableColumn(identifier: .init("command"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.rowHeight = Self.rowHeight
        tableView.intercellSpacing = .zero
        tableView.backgroundColor = .clear
        tableView.refusesFirstResponder = true   // typing stays in the search field
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(clicked(_:))
        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.isHidden = true

        for view in [background, searchField, separator, scrollView, emptyLabel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            panel.addSubview(view)
        }
        panel.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(panel)
        overlay.panel = panel

        listHeight = scrollView.heightAnchor.constraint(equalToConstant: Self.rowHeight)
        let preferredWidth = panel.widthAnchor.constraint(equalToConstant: Self.width)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(equalTo: overlay.topAnchor, constant: 10),
            panel.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            preferredWidth,
            panel.widthAnchor.constraint(lessThanOrEqualTo: overlay.widthAnchor, constant: -32),

            background.topAnchor.constraint(equalTo: panel.topAnchor),
            background.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            background.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: panel.trailingAnchor),

            searchField.topAnchor.constraint(equalTo: panel.topAnchor, constant: 10),
            searchField.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            searchField.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),

            separator.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 9),
            separator.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: panel.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 5),
            scrollView.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 5),
            scrollView.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -5),
            scrollView.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -5),
            listHeight,

            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
        ])
    }
}

/// Covers the window while the palette is open: a click outside the palette closes it.
private final class PaletteOverlay: NSView {
    var onClickOutside: (() -> Void)?
    weak var panel: NSView?

    override func mouseDown(with event: NSEvent) { onClickOutside?() }
    override func rightMouseDown(with event: NSEvent) { onClickOutside?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
}

/// Draws the selected row in the accent colour even though the search field, not the list, has focus.
private final class PaletteRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { true }
        set {}
    }
}

/// A row: check mark, title (matched letters in bold), the menu it's in, and its shortcut.
private final class PaletteCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("PaletteCell")

    private let check = NSTextField(labelWithString: "")
    private let title = NSTextField(labelWithString: "")
    private let path = NSTextField(labelWithString: "")
    private let shortcut = NSTextField(labelWithString: "")
    private var result: PaletteResult?

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        for label in [check, title, path, shortcut] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingTail
            addSubview(label)
        }
        title.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        path.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        shortcut.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            check.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            check.widthAnchor.constraint(equalToConstant: 14),
            title.leadingAnchor.constraint(equalTo: check.trailingAnchor, constant: 2),
            path.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 10),
            path.trailingAnchor.constraint(lessThanOrEqualTo: shortcut.leadingAnchor, constant: -10),
            title.trailingAnchor.constraint(lessThanOrEqualTo: shortcut.leadingAnchor, constant: -10),
            shortcut.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
        ] + [check, title, path, shortcut].map { $0.centerYAnchor.constraint(equalTo: centerYAnchor) })
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { render() }
    }

    func show(_ result: PaletteResult) {
        self.result = result
        render()
    }

    private func render() {
        guard let result else { return }
        let command = result.command
        let selected = backgroundStyle == .emphasized
        let primary: NSColor = selected ? .alternateSelectedControlTextColor : .labelColor
        let secondary: NSColor = selected ? NSColor.alternateSelectedControlTextColor.withAlphaComponent(0.75)
                                          : .secondaryLabelColor
        let font = NSFont.systemFont(ofSize: 13.5)
        let bold = NSFont.systemFont(ofSize: 13.5, weight: .bold)
        let matched = Set(result.titleIndices)
        let text = NSMutableAttributedString()
        for (i, character) in command.title.enumerated() {
            let hit = matched.contains(i)
            text.append(NSAttributedString(string: String(character), attributes: [
                .font: hit ? bold : font,
                .foregroundColor: hit && !selected ? NSColor.controlAccentColor : primary,
            ]))
        }
        title.attributedStringValue = text
        check.stringValue = command.isOn ? "✓" : ""
        check.textColor = primary
        path.stringValue = command.path.joined(separator: " › ")
        path.font = .systemFont(ofSize: 12)
        path.textColor = secondary
        shortcut.stringValue = command.shortcut
        shortcut.font = .systemFont(ofSize: 12.5)
        shortcut.textColor = secondary
    }
}
