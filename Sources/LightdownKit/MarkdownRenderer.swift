import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// Markdown -> HTML using cmark-gfm (tables, strikethrough, autolinks, task lists).
enum MarkdownRenderer {
    private static let extensionNames = ["table", "strikethrough", "autolink", "tasklist", "tagfilter"]

    /// `sourcePositions` adds `data-sourcepos="line:col-line:col"` to block elements, which the
    /// preview uses to map between editor lines and rendered content.
    static func html(from markdown: String, sourcePositions: Bool = false) -> String {
        cmark_gfm_core_extensions_ensure_registered()

        var options = CMARK_OPT_UNSAFE | CMARK_OPT_FOOTNOTES | CMARK_OPT_SMART
        if sourcePositions { options |= CMARK_OPT_SOURCEPOS }
        guard let parser = cmark_parser_new(options) else { return "" }
        defer { cmark_parser_free(parser) }

        for name in extensionNames {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }

        markdown.withCString { cstr in
            cmark_parser_feed(parser, cstr, strlen(cstr))
        }
        guard let doc = cmark_parser_finish(parser) else { return "" }
        defer { cmark_node_free(doc) }
        fixTaskStates(in: doc, source: markdown)
        addCheckboxes(in: doc, source: markdown, positions: sourcePositions)

        guard let out = cmark_render_html(doc, options, cmark_parser_get_syntax_extensions(parser)) else { return "" }
        defer { free(out) }
        return String(cString: out)
    }

    private static let checkbox = try! NSRegularExpression(pattern: #"^(?:[-*+]|\d+[.)])[ \t]+\[([ xX])\]"#)

    /// cmark-gfm marks a task as checked if "[x]" appears anywhere in the rest of its line
    /// (`strstr` in tasklist.c), so "- [ ] see `[x]`" rendered as checked. Re-derive each task's
    /// state from the checkbox at the item's own start position.
    private static func fixTaskStates(in doc: UnsafeMutablePointer<cmark_node>, source: String) {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        guard let iter = cmark_iter_new(doc) else { return }
        defer { cmark_iter_free(iter) }
        while true {
            let event = cmark_iter_next(iter)
            if event == CMARK_EVENT_DONE { break }
            guard event == CMARK_EVENT_ENTER, let node = cmark_iter_get_node(iter),
                  let type = cmark_node_get_type_string(node), String(cString: type) == "tasklist" else { continue }
            let line = Int(cmark_node_get_start_line(node)), column = Int(cmark_node_get_start_column(node))
            guard line >= 1, line <= lines.count else { continue }
            let bytes = Array(lines[line - 1].utf8)   // cmark columns are 1-based byte offsets
            guard column >= 1, column - 1 < bytes.count else { continue }
            let rest = String(decoding: bytes[(column - 1)...], as: UTF8.self)
            let ns = rest as NSString
            guard let match = checkbox.firstMatch(in: rest, range: NSRange(location: 0, length: ns.length)) else { continue }
            cmark_gfm_extensions_set_tasklist_item_checked(node, ns.substring(with: match.range(at: 1)) != " ")
        }
    }

    private static let lineCheckbox = try! NSRegularExpression(pattern: #"^[ \t>]*\[([ xX])\](?=[ \t]|$)"#)
    private static let cellCheckbox = try! NSRegularExpression(pattern: #"^[ \t]*\[([ xX])\](?=[ \t|]|$)"#)

    private struct Box {
        var node: UnsafeMutablePointer<cmark_node>   // first text node of the "[ ]"
        var line: Int, column: Int                    // where to look for it in the source
        var checked: Bool
    }

    /// GFM only has checkboxes in list items. Also turn a "[ ]" or "[x]" that starts a table cell
    /// or a line of a paragraph into one, so a table can hold a grid of checkboxes and a plain
    /// "[ ] item" line works like a task. With `positions`, each box carries its source line and
    /// column so the preview can toggle it.
    private static func addCheckboxes(in doc: UnsafeMutablePointer<cmark_node>, source: String, positions: Bool) {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        func state(line: Int, column: Int, _ regex: NSRegularExpression) -> Bool? {
            guard line >= 1, line <= lines.count else { return nil }
            let bytes = Array(lines[line - 1].utf8)   // cmark columns are 1-based byte offsets
            guard column >= 1, column - 1 <= bytes.count else { return nil }
            let rest = String(decoding: bytes[(column - 1)...], as: UTF8.self) as NSString
            guard let match = regex.firstMatch(in: rest as String, range: NSRange(location: 0, length: rest.length)) else { return nil }
            return rest.substring(with: match.range(at: 1)) != " "
        }
        // The text nodes from `node` up to the next non-text node, which cmark may split "[ ]" over.
        func leadingText(_ node: UnsafeMutablePointer<cmark_node>) -> String {
            var text = "", next: UnsafeMutablePointer<cmark_node>? = node
            while let n = next, cmark_node_get_type(n) == CMARK_NODE_TEXT {
                text += String(cString: cmark_node_get_literal(n))
                next = cmark_node_next(n)
            }
            return text
        }
        // The source has the box, and so does the parsed text (so it isn't escaped or code).
        func startsWithBox(_ node: UnsafeMutablePointer<cmark_node>) -> Bool {
            leadingText(node).range(of: #"^\[[ xX]\](?=[ \t]|$)"#, options: .regularExpression) != nil
        }

        var boxes: [Box] = []
        guard let iter = cmark_iter_new(doc) else { return }
        while true {
            let event = cmark_iter_next(iter)
            if event == CMARK_EVENT_DONE { break }
            guard event == CMARK_EVENT_ENTER, let node = cmark_iter_get_node(iter) else { continue }
            let line = Int(cmark_node_get_start_line(node)), column = Int(cmark_node_get_start_column(node))
            if cmark_node_get_type(node) == CMARK_NODE_PARAGRAPH {
                // Count line breaks to know which source line each inline starts on.
                var lineNumber = line, atLineStart = true
                var child = cmark_node_first_child(node)
                while let c = child {
                    let type = cmark_node_get_type(c)
                    if atLineStart, type == CMARK_NODE_TEXT, startsWithBox(c),
                       let checked = state(line: lineNumber, column: 1, lineCheckbox) {
                        boxes.append(Box(node: c, line: lineNumber, column: 1, checked: checked))
                    }
                    if type == CMARK_NODE_SOFTBREAK || type == CMARK_NODE_LINEBREAK {
                        lineNumber += 1
                        atLineStart = true
                    } else {
                        atLineStart = false
                    }
                    child = cmark_node_next(c)
                }
            } else if let type = cmark_node_get_type_string(node), String(cString: type) == "table_cell",
                      let first = cmark_node_first_child(node), cmark_node_get_type(first) == CMARK_NODE_TEXT,
                      startsWithBox(first), let checked = state(line: line, column: column, cellCheckbox) {
                boxes.append(Box(node: first, line: line, column: column, checked: checked))
            }
        }
        cmark_iter_free(iter)

        // Edit after iterating: the iterator doesn't survive changes to the tree.
        for box in boxes {
            // Each box in a paragraph starts its own line, as in a list.
            if let previous = cmark_node_previous(box.node), cmark_node_get_type(previous) == CMARK_NODE_SOFTBREAK,
               let lineBreak = cmark_node_new(CMARK_NODE_LINEBREAK) {
                cmark_node_insert_before(previous, lineBreak)
                cmark_node_free(previous)
            }
            guard let input = cmark_node_new(CMARK_NODE_HTML_INLINE) else { continue }
            let position = positions ? #" data-line="\#(box.line)" data-column="\#(box.column)""# : ""
            cmark_node_set_literal(input, #"<input type="checkbox"\#(box.checked ? #" checked="""# : "") disabled=""\#(position) />"#)
            cmark_node_insert_before(box.node, input)
            // Drop the three characters of "[ ]".
            var remaining = 3
            var next: UnsafeMutablePointer<cmark_node>? = box.node
            while remaining > 0, let node = next, cmark_node_get_type(node) == CMARK_NODE_TEXT {
                next = cmark_node_next(node)
                let literal = Array(String(cString: cmark_node_get_literal(node)).utf8)
                if literal.count <= remaining {
                    remaining -= literal.count
                    cmark_node_free(node)
                } else {
                    cmark_node_set_literal(node, String(decoding: literal[remaining...], as: UTF8.self))
                    remaining = 0
                }
            }
        }
    }
}
