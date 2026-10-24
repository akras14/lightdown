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

        guard let out = cmark_render_html(doc, options, cmark_parser_get_syntax_extensions(parser)) else { return "" }
        defer { free(out) }
        return String(cString: out)
    }
}
