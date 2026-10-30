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
            text = group(4) ?? ""
        }

        var isBlank: Bool { marker == nil && state == .plain && text.trimmingCharacters(in: .whitespaces).isEmpty }

        func rendered(as newState: State) -> String {
            // A plain line becomes a "- [ ]" item; a bare "[ ]" stays bare.
            let prefix = marker.map { "\($0) " } ?? (state == .plain ? "- " : "")
            switch newState {
            case .plain: return indent + text
            case .unchecked: return "\(indent)\(prefix)[ ] \(text)"
            case .checked: return "\(indent)\(prefix)[x] \(text)"
            }
        }

        /// Length of everything before the item text.
        func prefixLength(as state: State) -> Int {
            (rendered(as: state) as NSString).length - (text as NSString).length
        }
    }

    // indent, optional list marker, optional checkbox, rest of the line. A checkbox without
    // a marker ("[ ] item") still counts.
    private static let lineRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*)(?:([-*+]|\d+[.)])[ \t]+)?(?:\[([ xX])\](?:[ \t]+|$))?(.*)$"#)

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

    /// Checks or unchecks the first box at or after `column`, skipping spaces and quote markers.
    /// `column` is a 1-based byte offset like cmark's source positions, e.g. where a table cell
    /// starts. Returns nil when there's no box there.
    static func toggleBox(_ line: String, column: Int) -> String? {
        var bytes = Array(line.utf8)
        var i = column - 1
        guard i >= 0 else { return nil }
        while i < bytes.count, [" ", "\t", ">"].map(UInt8.init(ascii:)).contains(bytes[i]) { i += 1 }
        guard i + 2 < bytes.count, bytes[i] == UInt8(ascii: "["), bytes[i + 2] == UInt8(ascii: "]") else { return nil }
        switch bytes[i + 1] {
        case UInt8(ascii: " "): bytes[i + 1] = UInt8(ascii: "x")
        case UInt8(ascii: "x"), UInt8(ascii: "X"): bytes[i + 1] = UInt8(ascii: " ")
        default: return nil
        }
        return String(decoding: bytes, as: UTF8.self)
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

    /// Checks or unchecks the box at `line` (0-based) and `column` (1-based byte offset), when a
    /// table or bare checkbox is clicked in the preview.
    func toggleCheckbox(line: Int, column: Int) {
        editLines("Toggle To-Do") { lines in
            guard line >= 0, line < lines.count, let toggled = TodoList.toggleBox(lines[line], column: column) else { return lines }
            var result = lines
            result[line] = toggled
            return result
        }
    }
}
