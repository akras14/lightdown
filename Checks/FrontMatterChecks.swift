import AppKit
@testable import LightdownKit

@MainActor
func frontMatterChecks(_ t: Checker) {
    t.group("front matter rendering") {
        let skill = """
        ---
        name: "youtube-upload-kit"
        description: "Use instead of youtube-upload-kit: turn a transcript into subtitles, then copy-paste details."
        ---

        # Title
        """
        let html = MarkdownRenderer.html(from: skill)
        t.expect(html.contains("<dl class=\"frontmatter\">"), true, "a key/value block (html: \(html))")
        t.expect(html.contains("<dt>name</dt><dd>youtube-upload-kit</dd>"), true, "quotes dropped (html: \(html))")
        t.expect(html.contains("<dd>Use instead of youtube-upload-kit: turn a transcript into subtitles, then copy-paste details.</dd>"),
                 true, "a colon inside the value is kept (html: \(html))")
        t.expect(html.contains("<hr"), false, "no rule from the fences")
        t.expect(html.contains("<h2"), false, "no setext heading from the closing fence")
        t.expect(html.contains("<h1>Title</h1>"), true, "the body renders after it")

        let positioned = MarkdownRenderer.html(from: skill, sourcePositions: true)
        t.expect(positioned.contains("<dl class=\"frontmatter\" data-sourcepos=\"1:1-4:3\">"), true,
                 "the block maps to its lines (html: \(positioned))")
        t.expect(positioned.contains("<h1 data-sourcepos=\"6:1-6:7\">"), true, "body keeps its line numbers (html: \(positioned))")
        let boxes = MarkdownRenderer.html(from: "---\na: b\n---\n[ ] x\n", sourcePositions: true)
        t.expect(boxes.contains("data-line=\"4\""), true, "checkboxes keep their line (html: \(boxes))")
    }

    t.group("front matter values") {
        func html(_ yaml: String) -> String { MarkdownRenderer.html(from: "---\n\(yaml)\n---\n") }
        t.expect(html("title: <b>Hi</b> & bye").contains("<dd>&lt;b&gt;Hi&lt;/b&gt; &amp; bye</dd>"), true, "escaped")
        t.expect(html("a: 'it''s'\nb: \"say \\\"hi\\\"\"").contains("<dd>it's</dd><dt>b</dt><dd>say \"hi\"</dd>"), true,
                 "single and double quoted (html: \(html("a: 'it''s'\nb: \"say \\\"hi\\\"\"")))")
        t.expect(html("tags: [one, \"two\"]").contains("<dd><ul><li>one</li><li>two</li></ul></dd>"), true, "flow list")
        t.expect(html("tags:\n  - one\n  - two").contains("<dd><ul><li>one</li><li>two</li></ul></dd>"), true, "block list")
        t.expect(html("tags:\n- one\n- two").contains("<dd><ul><li>one</li><li>two</li></ul></dd>"), true, "unindented block list")
        t.expect(html("text: |\n  line one\n  line two").contains("<dd class=\"literal\">line one\nline two</dd>"), true,
                 "literal block keeps lines")
        t.expect(html("text: >-\n  folded\n  together").contains("<dd>folded together</dd>"), true, "folded block")
        t.expect(html("plain: one\n  two").contains("<dd>one two</dd>"), true, "continued plain scalar")
        t.expect(html("plain: value # note").contains("<dd>value</dd>"), true, "comment dropped")
        t.expect(html("author:\n  name: Al\n  site: x.com").contains("<dd><pre><code>name: Al\nsite: x.com</code></pre></dd>"), true,
                 "nested map shown as YAML (html: \(html("author:\n  name: Al\n  site: x.com")))")
        t.expect(html("# comment\nempty:").contains("<dt>empty</dt><dd></dd>"), true, "empty value, comment skipped")
        t.expect(MarkdownRenderer.html(from: "---\n---\n\nText\n").contains("<hr"), false, "empty front matter renders nothing")
    }

    t.group("not front matter") {
        t.expect(MarkdownRenderer.html(from: "Intro\n\n---\na: b\n---\n").contains("frontmatter"), false, "only at the very start")
        t.expect(MarkdownRenderer.html(from: "---\na: b\n").contains("frontmatter"), false, "needs a closing fence")
        t.expect(MarkdownRenderer.html(from: "---\nJust a sentence.\n---\n").contains("frontmatter"), false, "needs keys")
    }

    t.group("front matter in the outline") {
        let text = "---\nname: x\ndescription: y\n---\n\n# Title\n\nPara\n---\n"
        t.expect(OutlineParser.headings(in: text).map(\.title), ["Title", "Para"], "the closing fence isn't a heading")
        t.expect(OutlineParser.headings(in: text).map(\.line), [6, 8])
    }
}
