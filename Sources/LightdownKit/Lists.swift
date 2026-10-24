import AppKit

/// Return, Tab and Shift-Tab behaviour for bullet, numbered and task lists.
enum ListEditing {
    enum Continuation {
        case insert(String)   // text to insert at the caret, starting with "\n"
        case outdent          // empty nested item: move it up a level
        case endList          // empty top-level item: remove its marker
    }

    private static let thematicBreak = try! NSRegularExpression(pattern: #"^[ \t]*([-*_])([ \t]*\1){2,}[ \t]*$"#)
    private static let numbered = try! NSRegularExpression(pattern: #"^([ \t]*)(\d+)([.)])(?=[ \t]|$)"#)

    /// What Return should do, or nil for a plain newline.
    static func continuation(beforeCaret: String, line: String) -> Continuation? {
        if thematicBreak.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil {
            return nil
        }
        let whole = TodoList.Line(line)
        if whole.marker != nil, whole.text.trimmingCharacters(in: .whitespaces).isEmpty {
            return whole.indent.isEmpty ? .endList : .outdent
        }
        let item = TodoList.Line(beforeCaret)
        guard var marker = item.marker else { return nil }
        if let n = Int(marker.dropLast()) { marker = "\(n + 1)\(marker.last!)" }
        let box = item.state == .plain ? "" : "[ ] "
        return .insert("\n\(item.indent)\(marker) \(box)")
    }

    // MARK: Indentation

    /// Indents or outdents the list items on `selection` (line indices) together with their children.
    /// Returns nil when the selection doesn't start on a list item.
    static func shift(_ lines: [String], selection: Range<Int>, indent: Bool) -> [String]? {
        guard !selection.isEmpty, ListMove.isListItem(lines[selection.lowerBound]) else { return nil }
        let width = lines[selection].filter { !ListMove.isBlank($0) }.map(ListMove.indentWidth).min() ?? 0
        var end = selection.upperBound
        while end < lines.count, !ListMove.isBlank(lines[end]), ListMove.indentWidth(lines[end]) > width { end += 1 }
        let block = selection.lowerBound..<end

        let delta: Int
        if indent {
            // Nest under the previous sibling by aligning with its text, as CommonMark expects.
            var k = block.lowerBound - 1
            while k >= 0, !ListMove.isBlank(lines[k]), ListMove.indentWidth(lines[k]) > width { k -= 1 }
            if k >= 0, ListMove.isListItem(lines[k]), ListMove.indentWidth(lines[k]) == width {
                delta = contentOffset(lines[k]) - width
            } else {
                delta = contentOffset(lines[block.lowerBound]) - width
            }
        } else {
            guard width > 0 else { return lines }
            var k = block.lowerBound - 1
            while k >= 0, ListMove.isBlank(lines[k]) || ListMove.indentWidth(lines[k]) >= width { k -= 1 }
            let parentWidth = k >= 0 ? ListMove.indentWidth(lines[k]) : 0
            delta = parentWidth - width
        }

        var result = lines
        for i in block where !ListMove.isBlank(lines[i]) {
            let line = lines[i]
            let leading = line.prefix { $0 == " " || $0 == "\t" }
            let newWidth = max(0, ListMove.indentWidth(line) + delta)
            result[i] = String(repeating: " ", count: newWidth) + line.dropFirst(leading.count)
        }
        // A numbered item that now starts a new sub-list counts from 1.
        let newWidth = ListMove.indentWidth(result[block.lowerBound])
        var k = block.lowerBound - 1
        while k >= 0, !ListMove.isBlank(result[k]), ListMove.indentWidth(result[k]) > newWidth { k -= 1 }
        let joinsList = k >= 0 && ListMove.indentWidth(result[k]) == newWidth && numberInfo(result[k]) != nil
        if !joinsList, numberInfo(result[block.lowerBound]) != nil {
            let first = result[block.lowerBound]
            // "$11$3" is group 1, a literal "1", then group 3 (there is no group 11).
            result[block.lowerBound] = numbered.stringByReplacingMatches(
                in: first, range: NSRange(location: 0, length: (first as NSString).length), withTemplate: "$11$3")
        }
        for i in [block.lowerBound - 1, block.lowerBound, block.upperBound] where i >= 0 && i < result.count {
            result = renumber(result, around: i)
        }
        return result
    }

    /// Width of the indent plus marker and following spaces, i.e. where the item's text starts.
    private static func contentOffset(_ line: String) -> Int {
        let item = TodoList.Line(line)
        return ListMove.indentWidth(line) + (item.marker?.count ?? 0) + 1
    }

    // MARK: Numbering

    /// Renumbers the numbered list that contains `index` so it counts up from its first item.
    /// Lists written in the lazy `1. 1. 1.` style stay that way.
    static func renumber(_ lines: [String], around index: Int) -> [String] {
        guard index >= 0, index < lines.count, let (width, _) = numberInfo(lines[index]) else { return lines }

        func isSibling(_ i: Int) -> Bool? {   // true: item at this level, nil: child/continuation, false: stop
            let line = lines[i]
            if ListMove.isBlank(line) { return false }
            let w = ListMove.indentWidth(line)
            if w > width { return nil }
            if w == width, numberInfo(line) != nil { return true }
            return false
        }

        var items = [index]
        var i = index - 1
        up: while i >= 0 {
            switch isSibling(i) {
            case true?: items.insert(i, at: 0)
            case nil: break
            case false?: break up
            }
            i -= 1
        }
        i = index + 1
        down: while i < lines.count {
            switch isSibling(i) {
            case true?: items.append(i)
            case nil: break
            case false?: break down
            }
            i += 1
        }
        guard items.count > 1 else { return lines }

        let numbers = items.map { numberInfo(lines[$0])!.1 }
        let others = zip(items, numbers).filter { $0.0 != index }.map(\.1)
        let lazy = others.count >= 2 && Set(others).count == 1
        let start = lazy ? others[0] : numbers[0]

        var result = lines
        for (n, item) in items.enumerated() {
            let number = lazy ? start : start + n
            let line = lines[item] as NSString
            result[item] = numbered.stringByReplacingMatches(
                in: lines[item], range: NSRange(location: 0, length: line.length), withTemplate: "$1\(number)$3")
        }
        return result
    }

    private static func numberInfo(_ line: String) -> (width: Int, number: Int)? {
        let ns = line as NSString
        guard let m = numbered.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              let n = Int(ns.substring(with: m.range(at: 2))) else { return nil }
        return (ListMove.indentWidth(line), n)
    }
}

extension EditorTextView {
    /// Handles Return in a list. Returns false to let the text view insert a plain newline.
    func continueList() -> Bool {
        let selection = selectedRange()
        guard selection.length == 0 else { return false }
        let text = string as NSString
        let lineRange = text.lineRange(for: NSRange(location: selection.location, length: 0))
        let lineStart = lineRange.location
        let beforeCaret = text.substring(with: NSRange(location: lineStart, length: selection.location - lineStart))
        let line = text.substring(with: lineRange).trimmingCharacters(in: .newlines)

        switch ListEditing.continuation(beforeCaret: beforeCaret, line: line) {
        case .insert(let s)?:
            insertText(s, replacementRange: selection)
            let caretLine = lineIndex(of: selectedRange().location)
            editLines("Typing") { ListEditing.renumber($0, around: caretLine) }
        case .outdent?:
            _ = shiftListItems(indent: false)
        case .endList?:
            let lineEnd = lineStart + (line as NSString).length
            insertText("", replacementRange: NSRange(location: lineStart, length: lineEnd - lineStart))
        case nil:
            return false
        }
        return true
    }

    /// Tab / Shift-Tab on list items. Returns false when the selection isn't in a list.
    func shiftListItems(indent: Bool) -> Bool {
        let text = string as NSString
        let selection = selectedRange()
        var selEnd = NSMaxRange(selection)
        if selection.length > 0, text.character(at: selEnd - 1) == 0x0A { selEnd -= 1 }
        let first = lineIndex(of: selection.location), last = lineIndex(of: selEnd)
        let lines = string.components(separatedBy: "\n")
        guard let shifted = ListEditing.shift(lines, selection: first..<(last + 1), indent: indent) else { return false }
        editLines(indent ? "Indent" : "Outdent") { _ in shifted }
        return true
    }

    func lineIndex(of location: Int) -> Int {
        let text = string as NSString
        var count = 0, i = 0
        while i < location, i < text.length {
            if text.character(at: i) == 0x0A { count += 1 }
            i += 1
        }
        return count
    }

    /// Applies a whole-document line transform as one minimal edit, keeping the selection
    /// on the same text: positions shift by however much their own line changed length.
    func editLines(_ actionName: String, _ transform: ([String]) -> [String]) {
        let old = string.components(separatedBy: "\n")
        let new = transform(old)
        guard new != old, new.count == old.count else { return }

        var first = 0
        while old[first] == new[first] { first += 1 }
        var last = old.count - 1
        while old[last] == new[last] { last -= 1 }

        func start(of line: Int, in lines: [String]) -> Int {
            lines[..<line].reduce(0) { $0 + ($1 as NSString).length + 1 }
        }
        let rangeStart = start(of: first, in: old)
        let oldText = old[first...last].joined(separator: "\n")
        let newText = new[first...last].joined(separator: "\n")
        let range = NSRange(location: rangeStart, length: (oldText as NSString).length)

        // Map the selection: each end keeps its column relative to the end of its line's leading prefix.
        func map(_ location: Int) -> Int {
            let line = lineIndex(of: location)
            let column = location - start(of: line, in: old)
            let delta = (new[line] as NSString).length - (old[line] as NSString).length
            let prefix = old[line].prefix { $0 == " " || $0 == "\t" }.utf16.count
            return start(of: line, in: new) + max(0, column + (column > prefix || delta > 0 ? delta : 0))
        }
        let selection = selectedRange()
        let newStart = map(selection.location), newEnd = map(NSMaxRange(selection))

        guard shouldChangeText(in: range, replacementString: newText) else { return }
        textStorage?.replaceCharacters(in: range, with: newText)
        didChangeText()
        undoManager?.setActionName(actionName)
        setSelectedRange(NSRange(location: newStart, length: max(0, newEnd - newStart)))
    }
}
