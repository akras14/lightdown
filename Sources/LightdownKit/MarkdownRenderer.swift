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
}
