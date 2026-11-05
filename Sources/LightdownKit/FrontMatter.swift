import Foundation

/// YAML front matter: a block fenced by `---` lines at the very start of a document, as in Jekyll,
/// Hugo and Claude skills. Without this, cmark reads the opening fence as a rule and the closing
/// one as a setext underline, so the keys render as one big heading.
///
/// Only the common shapes are understood: `key: value` (plain or quoted), flow and block lists,
/// `|` and `>` block scalars. Anything nested is shown as YAML.
enum FrontMatter {
    enum Value: Equatable {
        case text(String)
        case lines(String)     // `|` block: keep the line breaks
        case list([String])
        case yaml(String)      // nested mapping, shown as code
    }

    struct Entry: Equatable {
        var key: String
        var value: Value
    }

    struct Block: Equatable {
        var entries: [Entry]
        var lineCount: Int     // including both fences
    }

    private static let keyLine = try! NSRegularExpression(pattern: #"^("[^"]*"|'[^']*'|[^\s#"'][^:]*?)[ \t]*:(?:[ \t]+(.*?))?[ \t]*$"#)

    /// The front matter at the start of `text`, if any. It needs a closing `---` (or `...`) line,
    /// and every unindented line in between must be a `key:`, a `- item` or a comment.
    static func parse(_ text: String) -> Block? {
        guard text.hasPrefix("---") else { return nil }
        let lines = text.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        guard isFence(lines[0], closing: false),
              let close = lines.indices.dropFirst().first(where: { isFence(lines[$0], closing: true) }) else { return nil }

        var entries: [Entry] = []
        var key: String?, inline = "", rest: [String] = []
        func finish() {
            guard let k = key else { return }
            entries.append(Entry(key: k, value: value(inline: inline, rest: rest)))
            key = nil; inline = ""; rest = []
        }
        for line in lines[1..<close] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indented = line.first == " " || line.first == "\t"
            if trimmed.isEmpty || (indented || line.hasPrefix("- ") || line == "-") {
                if key != nil { rest.append(line) } else if !trimmed.isEmpty, !trimmed.hasPrefix("#") { return nil }
                continue
            }
            if trimmed.hasPrefix("#") { continue }
            let ns = line as NSString
            guard let m = keyLine.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
            finish()
            key = unquote(ns.substring(with: m.range(at: 1)))
            inline = m.range(at: 2).location == NSNotFound ? "" : ns.substring(with: m.range(at: 2))
        }
        finish()
        return Block(entries: entries, lineCount: close + 1)
    }

    /// The document with its front matter lines blanked, so cmark skips them but every later
    /// block keeps its line number (scroll sync and checkbox toggling rely on them).
    static func blanked(_ text: String, lineCount: Int) -> String {
        var lines = text.components(separatedBy: "\n")
        for i in 0..<min(lineCount, lines.count) { lines[i] = "" }
        return lines.joined(separator: "\n")
    }

    static func html(_ block: Block, sourcePositions: Bool) -> String {
        guard !block.entries.isEmpty else { return "" }
        let position = sourcePositions ? #" data-sourcepos="1:1-\#(block.lineCount):3""# : ""
        var out = #"<dl class="frontmatter"\#(position)>"#
        for entry in block.entries {
            out += "<dt>\(escape(entry.key))</dt>"
            switch entry.value {
            case .text(let s): out += "<dd>\(escape(s))</dd>"
            case .lines(let s): out += #"<dd class="literal">\#(escape(s))</dd>"#
            case .list(let items): out += "<dd><ul>" + items.map { "<li>\(escape($0))</li>" }.joined() + "</ul></dd>"
            case .yaml(let s): out += "<dd><pre><code>\(escape(s))</code></pre></dd>"
            }
        }
        return out + "</dl>\n"
    }

    // MARK: - Values

    private static func isFence(_ line: String, closing: Bool) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t == "---" || (closing && t == "...")
    }

    private static func value(inline: String, rest: [String]) -> Value {
        // Drop trailing blank lines, then the common indentation.
        var rest = rest
        while let last = rest.last, last.trimmingCharacters(in: .whitespaces).isEmpty { rest.removeLast() }
        let indent = rest.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.prefix { $0 == " " || $0 == "\t" }.count }.min() ?? 0
        let body = rest.map { String($0.dropFirst(min(indent, $0.prefix { $0 == " " || $0 == "\t" }.count))) }

        if let style = inline.first, style == "|" || style == ">" {
            if style == "|" { return .lines(body.joined(separator: "\n")) }
            return .text(fold(body))
        }
        if inline.hasPrefix("["), inline.hasSuffix("]") {
            return .list(splitFlow(String(inline.dropFirst().dropLast())).map(unquote).filter { !$0.isEmpty })
        }
        let content = body.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if inline.isEmpty, !content.isEmpty, content.allSatisfy({ $0.hasPrefix("- ") || $0 == "-" }) {
            return .list(content.map { unquote(String($0.dropFirst()).trimmingCharacters(in: .whitespaces)) })
        }
        if inline.isEmpty, !content.isEmpty { return .yaml(body.joined(separator: "\n")) }
        let first = isQuoted(inline) ? inline : stripComment(inline)
        return .text(unquote(([first] + content).joined(separator: " ")))
    }

    /// `>` folding: lines join with spaces, blank lines become line breaks.
    private static func fold(_ lines: [String]) -> String {
        lines.split(whereSeparator: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
            .map { $0.joined(separator: " ") }.joined(separator: "\n")
    }

    private static func isQuoted(_ s: String) -> Bool {
        s.count >= 2 && ((s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")))
    }

    private static func unquote(_ s: String) -> String {
        guard isQuoted(s) else { return s }
        let inner = String(s.dropFirst().dropLast())
        if s.hasPrefix("'") { return inner.replacingOccurrences(of: "''", with: "'") }
        var out = "", escaping = false
        for c in inner {
            if escaping {
                switch c {
                case "n": out.append("\n")
                case "t": out.append("\t")
                default: out.append(c)
                }
                escaping = false
            } else if c == "\\" {
                escaping = true
            } else {
                out.append(c)
            }
        }
        return out
    }

    /// In a plain value, " #" starts a comment.
    private static func stripComment(_ s: String) -> String {
        guard let r = s.range(of: " #") else { return s }
        return String(s[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
    }

    /// Splits `a, "b, c", d` on commas outside quotes.
    private static func splitFlow(_ s: String) -> [String] {
        var items: [String] = [], current = "", quote: Character?
        for c in s {
            if let q = quote {
                if c == q { quote = nil }
                current.append(c)
            } else if c == "\"" || c == "'" {
                quote = c
                current.append(c)
            } else if c == "," {
                items.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(c)
            }
        }
        items.append(current.trimmingCharacters(in: .whitespaces))
        return items
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
