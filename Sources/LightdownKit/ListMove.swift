import AppKit

/// Moving list items (with their nested children) past their siblings.
enum ListMove {
    struct Result {
        var lines: [String]          // replacement for `changed`
        var changed: Range<Int>      // line range that was rewritten
        var movedStart: Int          // new index of the moved block's first line
        var firstLineDelta: Int      // length change of the moved block's first line (renumbering)
    }

    private static let itemRegex = try! NSRegularExpression(pattern: #"^[ \t]*(?:[-*+]|\d+[.)])(?:[ \t]|$)"#)
    private static let numberRegex = try! NSRegularExpression(pattern: #"^([ \t]*)(\d+)([.)])"#)

    static func isBlank(_ line: String) -> Bool { line.allSatisfy { $0 == " " || $0 == "\t" } }

    static func isListItem(_ line: String) -> Bool {
        itemRegex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
    }

    static func indentWidth(_ line: String) -> Int {
        var width = 0
        for c in line {
            if c == " " { width += 1 } else if c == "\t" { width += 4 } else { break }
        }
        return width
    }

    /// End (exclusive) of the block starting with `lines[last]`'s item: following lines indented deeper than `indent`.
    private static func blockEnd(_ lines: [String], after last: Int, indent: Int) -> Int {
        var end = last + 1
        while end < lines.count, !isBlank(lines[end]), indentWidth(lines[end]) > indent { end += 1 }
        return end
    }

    /// Moves the list item(s) on `selection` (line indices) up or down past one sibling.
    /// Returns nil when the selection doesn't start on a list item or there's no sibling to swap with.
    static func move(_ lines: [String], selection: Range<Int>, up: Bool) -> Result? {
        guard !selection.isEmpty, isListItem(lines[selection.lowerBound]) else { return nil }
        let indent = lines[selection].filter { !isBlank($0) }.map(indentWidth).min() ?? 0
        let block = selection.lowerBound..<blockEnd(lines, after: selection.upperBound - 1, indent: indent)

        let sibling: Range<Int>
        if up {
            var k = block.lowerBound - 1
            while k >= 0, !isBlank(lines[k]), indentWidth(lines[k]) > indent { k -= 1 }
            guard k >= 0, !isBlank(lines[k]), indentWidth(lines[k]) == indent, isListItem(lines[k]) else { return nil }
            sibling = k..<block.lowerBound
        } else {
            let k = block.upperBound
            guard k < lines.count, !isBlank(lines[k]), indentWidth(lines[k]) == indent, isListItem(lines[k]) else { return nil }
            sibling = k..<blockEnd(lines, after: k, indent: indent)
        }

        var moved = Array(lines[block])
        var other = Array(lines[sibling])
        let originalFirst = moved[0]
        // Numbered siblings swap places but keep the numbers in order.
        if let a = number(in: moved[0]), let b = number(in: other[0]) {
            moved[0] = renumber(moved[0], to: b)
            other[0] = renumber(other[0], to: a)
        }
        let delta = (moved[0] as NSString).length - (originalFirst as NSString).length

        if up {
            return Result(lines: moved + other, changed: sibling.lowerBound..<block.upperBound,
                          movedStart: sibling.lowerBound, firstLineDelta: delta)
        } else {
            return Result(lines: other + moved, changed: block.lowerBound..<sibling.upperBound,
                          movedStart: block.lowerBound + other.count, firstLineDelta: delta)
        }
    }

    private static func number(in line: String) -> String? {
        let ns = line as NSString
        guard let m = numberRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range(at: 2))
    }

    private static func renumber(_ line: String, to n: String) -> String {
        numberRegex.stringByReplacingMatches(in: line, range: NSRange(location: 0, length: (line as NSString).length),
                                             withTemplate: "$1\(n)$3")
    }
}

extension EditorTextView {
    /// Moves the list item at the selection up or down. Returns false if there's nothing to move.
    func moveListItem(up: Bool) -> Bool {
        let text = string as NSString
        let lines = string.components(separatedBy: "\n")
        var lineStarts: [Int] = []
        var offset = 0
        for line in lines {
            lineStarts.append(offset)
            offset += (line as NSString).length + 1
        }
        func lineIndex(_ location: Int) -> Int {
            var lo = 0, hi = lineStarts.count - 1
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if lineStarts[mid] <= location { lo = mid } else { hi = mid - 1 }
            }
            return lo
        }

        let selection = selectedRange()
        var selEnd = NSMaxRange(selection)
        // A selection ending at the start of a line shouldn't include that line.
        if selection.length > 0, text.character(at: selEnd - 1) == 0x0A { selEnd -= 1 }
        let first = lineIndex(selection.location), last = lineIndex(selEnd)
        guard let result = ListMove.move(lines, selection: first..<(last + 1), up: up) else { return false }

        let changedStart = lineStarts[result.changed.lowerBound]
        let changedEnd = lineStarts[result.changed.upperBound - 1] + (lines[result.changed.upperBound - 1] as NSString).length
        let changedRange = NSRange(location: changedStart, length: changedEnd - changedStart)
        let replacement = result.lines.joined(separator: "\n")
        guard shouldChangeText(in: changedRange, replacementString: replacement) else { return true }
        textStorage?.replaceCharacters(in: changedRange, with: replacement)
        didChangeText()
        undoManager?.setActionName("Move Item")

        // Keep the selection on the same text inside the moved block.
        let oldBlockStart = lineStarts[first]
        var newBlockStart = changedStart
        for line in result.lines[0..<(result.movedStart - result.changed.lowerBound)] {
            newBlockStart += (line as NSString).length + 1
        }
        let indentLength = lines[first].prefix { $0 == " " || $0 == "\t" }.utf16.count
        func map(_ location: Int) -> Int {
            let rel = location - oldBlockStart
            return newBlockStart + rel + (rel > indentLength ? result.firstLineDelta : 0)
        }
        setSelectedRange(NSRange(location: map(selection.location), length: map(NSMaxRange(selection)) - map(selection.location)))
        scrollRangeToVisible(selectedRange())
        return true
    }
}
