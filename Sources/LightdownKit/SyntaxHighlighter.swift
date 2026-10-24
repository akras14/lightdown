import AppKit

/// Lightweight regex-based Markdown highlighting for the editor.
final class SyntaxHighlighter: NSObject, NSTextStorageDelegate {
    var fontSize: CGFloat = 14

    private struct Rule {
        let regex: NSRegularExpression
        let attributes: (CGFloat) -> [NSAttributedString.Key: Any]
    }

    private static func re(_ pattern: String, _ options: NSRegularExpression.Options = [.anchorsMatchLines]) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }

    // Order matters: later rules win over earlier ones.
    private let rules: [Rule] = [
        Rule(regex: re(#"^#{1,6}[ \t].*$"#)) { s in [.font: mono(s, .bold), .foregroundColor: NSColor.systemBlue] },
        Rule(regex: re(#"^[ \t]*(?:[-*+]|\d+[.)])[ \t]+\[[xX]\].*$"#)) { _ in [.foregroundColor: NSColor.tertiaryLabelColor] },
        Rule(regex: re(#"^[ \t]*(?:[-*+]|\d+[.)])[ \t]+(?:\[[ xX]\](?=[ \t]|$))?"#)) { _ in [.foregroundColor: NSColor.systemOrange] },
        Rule(regex: re(#"^>.*$"#)) { _ in [.foregroundColor: NSColor.secondaryLabelColor] },
        Rule(regex: re(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)) { s in [.font: mono(s, .bold)] },
        Rule(regex: re(#"(?<![*_\w])([*_])(?=\S)(.+?)(?<=\S)\1(?![*_\w])"#)) { s in
            [.font: NSFontManager.shared.convert(mono(s), toHaveTrait: .italicFontMask)]
        },
        Rule(regex: re(#"~~.+?~~"#)) { _ in [.strikethroughStyle: NSUnderlineStyle.single.rawValue] },
        Rule(regex: re(#"!?\[[^\]\n]*\]\([^)\n]*\)"#)) { _ in [.foregroundColor: NSColor.systemPurple] },
        Rule(regex: re(#"<https?://[^>\s]+>"#)) { _ in [.foregroundColor: NSColor.systemPurple] },
        Rule(regex: re(#"`[^`\n]+`"#)) { _ in [.foregroundColor: NSColor.systemPink] },
    ]

    // Applied after the line rules, so code blocks and rules win.
    private static let fencedBlock = re(#"^(```|~~~).*?^\1[ \t]*$"#, [.anchorsMatchLines, .dotMatchesLineSeparators])
    private static let fenceMarker = re(#"^(```|~~~)"#)
    private static let thematicBreak = re(#"^[ \t]*([-*_])([ \t]*\1){2,}[ \t]*$"#)

    private var fenceMarkerCount = 0

    /// Re-styles only the edited paragraphs: restyling the whole document on every keystroke
    /// invalidated all layout, which was slow and made the scroll position shift after edits.
    /// Every rule is confined to a line except fenced code, so the restyled range only widens
    /// (to the end of the document) when a fence line is added, removed or edited.
    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        let text = textStorage.string as NSString
        var dirty = text.paragraphRange(for: editedRange)
        let fences = Self.fenceMarker.numberOfMatches(in: textStorage.string, range: NSRange(location: 0, length: text.length))
        if fences != fenceMarkerCount || Self.fenceMarker.firstMatch(in: textStorage.string, range: dirty) != nil {
            dirty.length = text.length - dirty.location
        }
        fenceMarkerCount = fences
        highlight(textStorage, in: dirty)
    }

    /// Re-styles the whole document (on load and when the font size changes).
    func highlight(_ storage: NSTextStorage) {
        fenceMarkerCount = Self.fenceMarker.numberOfMatches(in: storage.string, range: NSRange(location: 0, length: storage.length))
        highlight(storage, in: NSRange(location: 0, length: storage.length))
    }

    private func highlight(_ storage: NSTextStorage, in range: NSRange) {
        guard range.length > 0 else { return }
        let text = storage.string
        storage.setAttributes([.font: Self.mono(fontSize), .foregroundColor: NSColor.textColor], range: range)
        for rule in rules {
            let attrs = rule.attributes(fontSize)
            rule.regex.enumerateMatches(in: text, range: range) { match, _, _ in
                if let r = match?.range { storage.addAttributes(attrs, range: r) }
            }
        }
        // Fenced blocks are found in the whole text (a block can start above the range) and clipped to it.
        Self.fencedBlock.enumerateMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) { match, _, stop in
            guard let block = match?.range else { return }
            if block.location >= NSMaxRange(range) { stop.pointee = true; return }
            let overlap = NSIntersectionRange(block, range)
            if overlap.length > 0 { storage.addAttributes([.foregroundColor: NSColor.systemPink], range: overlap) }
        }
        Self.thematicBreak.enumerateMatches(in: text, range: range) { match, _, _ in
            if let r = match?.range { storage.addAttributes([.foregroundColor: NSColor.tertiaryLabelColor], range: r) }
        }
    }
}
