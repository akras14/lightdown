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
        Rule(regex: re(#"^(```|~~~).*?^\1[ \t]*$"#, [.anchorsMatchLines, .dotMatchesLineSeparators])) { _ in
            [.foregroundColor: NSColor.systemPink]
        },
        Rule(regex: re(#"^[ \t]*([-*_])([ \t]*\1){2,}[ \t]*$"#)) { _ in [.foregroundColor: NSColor.tertiaryLabelColor] },
    ]

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        highlight(textStorage)
    }

    func highlight(_ storage: NSTextStorage) {
        let full = NSRange(location: 0, length: storage.length)
        let text = storage.string
        storage.setAttributes([.font: Self.mono(fontSize), .foregroundColor: NSColor.textColor], range: full)
        for rule in rules {
            let attrs = rule.attributes(fontSize)
            rule.regex.enumerateMatches(in: text, range: full) { match, _, _ in
                if let r = match?.range { storage.addAttributes(attrs, range: r) }
            }
        }
    }
}
