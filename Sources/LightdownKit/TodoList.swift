import AppKit

/// Text transformations for GFM task list items (`- [ ] item`, `- [x] item`).
enum TodoList {
    enum State { case plain, unchecked, checked }

    struct Line {
        var indent: String
        var marker: String?   // "-", "*", "+", "1." or "1)"
        var state: State
        var text: String

        init(_ line: String) {
            let ns = line as NSString
            let m = TodoList.lineRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length))!
            func group(_ i: Int) -> String? {
                let r = m.range(at: i)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            }
            indent = group(1) ?? ""
            marker = group(2)
            switch group(3) {
            case " "?: state = .unchecked
            case let box? where box.lowercased() == "x": state = .checked
            default: state = .plain
            }
            if marker == nil { state = .plain }
            text = group(4) ?? ""
        }

        var isBlank: Bool { marker == nil && text.trimmingCharacters(in: .whitespaces).isEmpty }

        func rendered(as newState: State) -> String {
            switch newState {
            case .plain: return indent + text
            case .unchecked: return "\(indent)\(marker ?? "-") [ ] \(text)"
            case .checked: return "\(indent)\(marker ?? "-") [x] \(text)"
            }
        }

        /// Length of everything before the item text.
        func prefixLength(as state: State) -> Int {
            (rendered(as: state) as NSString).length - (text as NSString).length
        }
    }

    // indent, optional list marker, optional checkbox, rest of the line
    private static let lineRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*)(?:([-*+]|\d+[.)])[ \t]+(?:\[([ xX])\](?:[ \t]+|$))?)?(.*)$"#)

    /// Toggles a group of lines together. The first non-blank line decides:
    /// plain/list item -> unchecked, unchecked -> checked, checked -> unchecked.
    static func toggle(_ lines: [String]) -> [String] {
        let parsed = lines.map(Line.init)
        let target: State
        switch parsed.first(where: { !$0.isBlank })?.state ?? .plain {
        case .plain, .checked: target = .unchecked
        case .unchecked: target = .checked
        }
        if parsed.count == 1 { return [parsed[0].rendered(as: target)] }
        return zip(lines, parsed).map { original, line in
            line.isBlank || line.state == target ? original : line.rendered(as: target)
        }
    }
}

extension EditorTextView {
    @IBAction func toggleTodo(_ sender: Any?) {
        let text = string as NSString
        let selection = selectedRange()
        // A selection ending at the start of a line shouldn't pull in that line.
        var range = selection
        if range.length > 0, text.character(at: NSMaxRange(range) - 1) == 0x0A { range.length -= 1 }
        let lineRange = text.lineRange(for: range)

        let block = text.substring(with: lineRange)
        let trailingNewline = block.hasSuffix("\n")
        let lines = (trailingNewline ? String(block.dropLast()) : block).components(separatedBy: "\n")
        let toggled = TodoList.toggle(lines)
        let replacement = toggled.joined(separator: "\n") + (trailingNewline ? "\n" : "")
        guard replacement != block, shouldChangeText(in: lineRange, replacementString: replacement) else { return }

        textStorage?.replaceCharacters(in: lineRange, with: replacement)
        didChangeText()
        undoManager?.setActionName("Toggle To-Do")

        if lines.count == 1 {
            // Keep the caret on the same character of the item text.
            let before = TodoList.Line(lines[0]), after = TodoList.Line(toggled[0])
            let oldPrefix = before.prefixLength(as: before.state), newPrefix = after.prefixLength(as: after.state)
            let offset = max(0, selection.location - lineRange.location - oldPrefix)
            let length = min(selection.length, (after.text as NSString).length)
            setSelectedRange(NSRange(location: lineRange.location + newPrefix + offset, length: length))
        } else {
            setSelectedRange(NSRange(location: lineRange.location, length: (replacement as NSString).length - (trailingNewline ? 1 : 0)))
        }
    }

    /// Checks or unchecks the task on `line` (0-based), e.g. when its checkbox is clicked in the preview.
    func toggleTaskCheckbox(line: Int) {
        editLines("Toggle To-Do") { lines in
            guard line >= 0, line < lines.count else { return lines }
            let item = TodoList.Line(lines[line])
            guard item.state != .plain else { return lines }
            var result = lines
            result[line] = item.rendered(as: item.state == .checked ? .unchecked : .checked)
            return result
        }
    }
}
