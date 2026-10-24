import AppKit

struct Heading: Equatable {
    var level: Int
    var title: String
    var line: Int   // 1-based
}

/// Finds ATX (`## Title`) and setext (`Title` over `===`/`---`) headings, skipping fenced code.
enum OutlineParser {
    private static let atx = try! NSRegularExpression(pattern: #"^ {0,3}(#{1,6})(?:[ \t]+(.*?))?(?:[ \t]+#+)?[ \t]*$"#)
    private static let fence = try! NSRegularExpression(pattern: #"^ {0,3}(`{3,}|~{3,})"#)
    private static let setextUnderline = try! NSRegularExpression(pattern: #"^ {0,3}(=+|-+)[ \t]*$"#)
    private static let link = try! NSRegularExpression(pattern: #"!?\[([^\]]*)\]\([^)]*\)"#)

    static func headings(in text: String) -> [Heading] {
        let lines = text.components(separatedBy: "\n")
        var result: [Heading] = []
        var openFence: String?
        var previousWasParagraph = false

        for (i, line) in lines.enumerated() {
            let ns = line as NSString
            let full = NSRange(location: 0, length: ns.length)

            if let m = fence.firstMatch(in: line, range: full) {
                let marker = ns.substring(with: m.range(at: 1))
                if let open = openFence {
                    if marker.first == open.first, marker.count >= open.count { openFence = nil }
                } else {
                    openFence = marker
                }
                previousWasParagraph = false
                continue
            }
            if openFence != nil { continue }

            if let m = atx.firstMatch(in: line, range: full) {
                let level = m.range(at: 1).length
                let title = m.range(at: 2).location == NSNotFound ? "" : ns.substring(with: m.range(at: 2))
                result.append(Heading(level: level, title: clean(title), line: i + 1))
                previousWasParagraph = false
                continue
            }
            if previousWasParagraph, let m = setextUnderline.firstMatch(in: line, range: full) {
                let level = ns.substring(with: m.range(at: 1)).hasPrefix("=") ? 1 : 2
                result.append(Heading(level: level, title: clean(lines[i - 1]), line: i))
                previousWasParagraph = false
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            previousWasParagraph = !trimmed.isEmpty && !ListMove.isListItem(line) && !trimmed.hasPrefix(">")
        }
        return result
    }

    /// Strips inline Markdown so the outline shows plain titles.
    static func clean(_ title: String) -> String {
        var s = title.trimmingCharacters(in: .whitespaces)
        s = link.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: "$1")
        for marker in ["**", "__", "~~", "*", "_", "`"] { s = s.replacingOccurrences(of: marker, with: "") }
        return s
    }
}

/// The sidebar: a list of headings. Selecting one asks the editor to jump there.
final class OutlineViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    var onSelect: ((Heading) -> Void)?
    private(set) var headings: [Heading] = []
    private let tableView = NSTableView()
    private let emptyLabel = NSTextField(labelWithString: "No headings")
    private var isUpdatingSelection = false

    override func loadView() {
        let column = NSTableColumn(identifier: .init("heading"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .sourceList
        tableView.rowSizeStyle = .default
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)   // re-clicking the selected heading jumps again

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        scrollView.frame = container.bounds
        scrollView.autoresizingMask = [.width, .height]
        container.addSubview(scrollView)
        container.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        view = container
    }

    func update(_ newHeadings: [Heading]) {
        guard newHeadings != headings else { return }
        headings = newHeadings
        tableView.reloadData()
        emptyLabel.isHidden = !headings.isEmpty
    }

    /// Highlights the section containing `line` without navigating.
    func highlightSection(atLine line: Double) {
        let index = headings.lastIndex { Double($0.line) <= line + 0.5 }
        isUpdatingSelection = true
        defer { isUpdatingSelection = false }
        if let index {
            tableView.selectRowIndexes([index], byExtendingSelection: false)
            tableView.scrollRowToVisible(index)
        } else {
            tableView.deselectAll(nil)
        }
    }

    var selectedRow: Int { tableView.selectedRow }

    func select(row: Int) {
        tableView.selectRowIndexes([row], byExtendingSelection: false)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { headings.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? {
            let cell = NSTableCellView()
            cell.identifier = id
            let label = NSTextField(labelWithString: "")
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            cell.textField = label
            return cell
        }()
        let heading = headings[row]
        let label = cell.textField!
        label.stringValue = heading.title.isEmpty ? "Untitled" : heading.title
        label.font = heading.level == 1 ? .systemFont(ofSize: 13, weight: .semibold) : .systemFont(ofSize: 13)
        label.textColor = heading.level <= 2 ? .labelColor : .secondaryLabelColor
        label.toolTip = heading.title
        NSLayoutConstraint.deactivate(cell.constraints)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: CGFloat(4 + (heading.level - 1) * 12)),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    @objc private func rowClicked() {
        guard tableView.clickedRow >= 0 else { return }
        onSelect?(headings[tableView.clickedRow])
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isUpdatingSelection, tableView.selectedRow >= 0 else { return }
        onSelect?(headings[tableView.selectedRow])
    }
}
