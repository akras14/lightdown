import AppKit

/// Inline Markdown formatting: wrapping and unwrapping text in emphasis markers, and links.
enum InlineStyle {
    case bold, italic, strikethrough, code

    var marker: Character {
        switch self {
        case .bold, .italic: return "*"
        case .strikethrough: return "~"
        case .code: return "`"
        }
    }

    var width: Int {
        switch self {
        case .bold, .strikethrough: return 2
        case .italic, .code: return 1
        }
    }

    /// Whether a run of `count` markers on both sides means this style is applied.
    /// `***x***` is bold and italic at once, so italic is "on" for odd runs of `*`.
    func isApplied(run count: Int) -> Bool {
        switch self {
        case .italic: return count % 2 == 1
        default: return count >= width
        }
    }

    var actionName: String {
        switch self {
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .strikethrough: return "Strikethrough"
        case .code: return "Inline Code"
        }
    }
}

extension EditorTextView {
    @IBAction func formatBold(_ sender: Any?) { toggle(.bold) }
    @IBAction func formatItalic(_ sender: Any?) { toggle(.italic) }
    @IBAction func formatStrikethrough(_ sender: Any?) { toggle(.strikethrough) }
    @IBAction func formatInlineCode(_ sender: Any?) { toggle(.code) }

    func toggle(_ style: InlineStyle) {
        let text = string as NSString
        let original = selectedRange()
        var target = original
        var caretOffset: Int?  // caret position inside the word, when we expanded to it

        if target.length == 0 {
            let word = wordRange(at: target.location)
            if word.length > 0 {
                caretOffset = target.location - word.location
                target = word
            }
        } else {
            target = trimmingWhitespace(target)
        }

        let w = style.width
        let ch = style.marker.utf16.first!

        func run(from index: Int, step: Int, limit: Int) -> Int {
            var count = 0, i = index
            while i >= 0, i < text.length, count < limit, text.character(at: i) == ch { count += 1; i += step }
            return count
        }

        // 1. Markers just outside the target: **|word|**
        let before = run(from: target.location - 1, step: -1, limit: 3)
        let after = run(from: NSMaxRange(target), step: 1, limit: 3)
        if style.isApplied(run: min(before, after)) {
            let outer = NSRange(location: target.location - w, length: target.length + 2 * w)
            let inner = text.substring(with: target)
            let newStart = outer.location
            replace(outer, with: inner, actionName: style.actionName,
                    select: caretOffset.map { NSRange(location: newStart + $0, length: 0) }
                        ?? NSRange(location: newStart, length: target.length))
            return
        }

        // 2. Markers just inside the selection: |**word**|
        if target.length >= 2 * w {
            let lead = run(from: target.location, step: 1, limit: 3)
            let trail = run(from: NSMaxRange(target) - 1, step: -1, limit: 3)
            if target.length > 2 * w, style.isApplied(run: min(lead, trail)) {
                let inner = text.substring(with: NSRange(location: target.location + w, length: target.length - 2 * w))
                replace(target, with: inner, actionName: style.actionName,
                        select: NSRange(location: target.location, length: (inner as NSString).length))
                return
            }
        }

        // 3. Wrap (or insert an empty pair at the caret).
        let markers = String(repeating: style.marker, count: w)
        let inner = text.substring(with: target)
        let select = caretOffset.map { NSRange(location: target.location + w + $0, length: 0) }
            ?? NSRange(location: target.location + w, length: target.length)
        replace(target, with: markers + inner + markers, actionName: style.actionName, select: select)
    }

    /// ⌘K: `[selection](|)`, `[|](url)` when the selection is a URL, or uses a copied URL.
    @IBAction func formatLink(_ sender: Any?) {
        let text = string as NSString
        let target = trimmingWhitespace(selectedRange())
        let selected = text.substring(with: target)

        if Self.looksLikeURL(selected) {
            replace(target, with: "[](\(selected))", actionName: "Link",
                    select: NSRange(location: target.location + 1, length: 0))
        } else if !selected.isEmpty,
                  let copied = Self.linkPasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  Self.looksLikeURL(copied) {
            let link = "[\(selected)](\(copied))"
            replace(target, with: link, actionName: "Link",
                    select: NSRange(location: target.location + (link as NSString).length, length: 0))
        } else {
            let link = "[\(selected)]()"
            let caret = selected.isEmpty ? target.location + 1 : target.location + (link as NSString).length - 1
            replace(target, with: link, actionName: "Link", select: NSRange(location: caret, length: 0))
        }
    }

    /// Where ⌘K looks for a copied URL (swapped out in tests).
    static var linkPasteboard = NSPasteboard.general

    static func looksLikeURL(_ s: String) -> Bool {
        guard !s.isEmpty, !s.contains(where: \.isWhitespace) else { return false }
        let lower = s.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("mailto:") || lower.hasPrefix("www.")
    }

    // MARK: Helpers

    /// The word containing `location` (letters, digits, `_`, `'`), or an empty range.
    private func wordRange(at location: Int) -> NSRange {
        let text = string as NSString
        func isWord(_ i: Int) -> Bool {
            guard i >= 0, i < text.length, let scalar = UnicodeScalar(text.character(at: i)) else { return false }
            return CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "'"
        }
        guard isWord(location) || isWord(location - 1) else { return NSRange(location: location, length: 0) }
        var start = location, end = location
        while isWord(start - 1) { start -= 1 }
        while isWord(end) { end += 1 }
        return NSRange(location: start, length: end - start)
    }

    private func trimmingWhitespace(_ range: NSRange) -> NSRange {
        let text = string as NSString
        var r = range
        while r.length > 0, let c = UnicodeScalar(text.character(at: r.location)), CharacterSet.whitespacesAndNewlines.contains(c) {
            r.location += 1; r.length -= 1
        }
        while r.length > 0, let c = UnicodeScalar(text.character(at: NSMaxRange(r) - 1)), CharacterSet.whitespacesAndNewlines.contains(c) {
            r.length -= 1
        }
        return r
    }

    /// One undoable edit, then the given selection.
    func replace(_ range: NSRange, with replacement: String, actionName: String, select: NSRange) {
        guard shouldChangeText(in: range, replacementString: replacement) else { return }
        textStorage?.replaceCharacters(in: range, with: replacement)
        didChangeText()
        undoManager?.setActionName(actionName)
        setSelectedRange(select)
    }
}
