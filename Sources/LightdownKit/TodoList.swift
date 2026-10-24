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

    enum Continuation {
        case insert(String)   // text to insert at the caret, starting with "\n"
        case endList          // empty item: remove its marker instead of adding a line
    }

    /// What Return should do on a task line, or nil to fall back to a normal newline.
    static func continuation(beforeCaret: String, line: String) -> Continuation? {
        let whole = Line(line)
        if whole.state != .plain, whole.text.trimmingCharacters(in: .whitespaces).isEmpty { return .endList }
        let item = Line(beforeCaret)
        guard item.state != .plain, let marker = item.marker else { return nil }
        var next = marker
        if let n = Int(marker.dropLast()) { next = "\(n + 1)\(marker.last!)" }
        return .insert("\n\(item.indent)\(next) [ ] ")
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

    /// Handles Return on a task line. Returns false to let the text view insert a plain newline.
    func continueTodoList() -> Bool {
        let selection = selectedRange()
        guard selection.length == 0 else { return false }
        let text = string as NSString
        let lineRange = text.lineRange(for: NSRange(location: selection.location, length: 0))
        let lineStart = lineRange.location
        let beforeCaret = text.substring(with: NSRange(location: lineStart, length: selection.location - lineStart))
        let line = text.substring(with: lineRange).trimmingCharacters(in: .newlines)

        switch TodoList.continuation(beforeCaret: beforeCaret, line: line) {
        case .insert(let s)?:
            insertText(s, replacementRange: selection)
        case .endList?:
            let lineEnd = lineStart + (line as NSString).length
            insertText("", replacementRange: NSRange(location: lineStart, length: lineEnd - lineStart))
        case nil:
            return false
        }
        return true
    }
}
