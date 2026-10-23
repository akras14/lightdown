# Lightdown

A minimal, native Markdown editor for macOS: an editor on the left and a live preview on the right. It started as a lean replacement for MacDown 3000, mainly to add zoom in and out.

## Features

- **Zoom.** ⌘= / ⌘- / ⌘0, or pinch on the trackpad. One zoom level covers the editor and the preview, and it's remembered between launches.
- **GitHub-style Markdown** via [cmark-gfm](https://github.com/swiftlang/swift-cmark): tables, task lists, strikethrough, footnotes, autolinks.
- **To-do lists.** ⌘L turns a line into a to-do (`- [ ] `), then checks and unchecks it, and works on several selected lines at once. Return on a to-do starts a new one; Return on an empty one ends the list.
- **Move list items.** ⇧⌘↑ / ⇧⌘↓ swap the current item, with its sub-items, past its neighbour. Numbered lists keep their order. In ordinary text these keys still select to the start or end of the document.
- **Mermaid diagrams** in fenced ` ```mermaid ` blocks.
- **Syntax colouring** for code blocks in the preview, and for Markdown in the editor.
- **Dark mode** support.
- **Synced scrolling:** scrolling the editor scrolls the preview to match.
- **Hide either pane:** ⌥⌘E hides the editor, ⌥⌘P hides the preview.
- **Standard Mac documents:** autosave, version history, tabs, recent files, find and replace.
- **Export to HTML** (⇧⌘E) and **print**.
- **Works offline.** Everything is bundled and nothing loads from the network.

## Build

You need macOS 13 or later and the Xcode Command Line Tools (`xcode-select --install`). Full Xcode isn't required.

```sh
./build.sh            # builds build/Lightdown.app
./build.sh --install  # also copies it to /Applications
```

To make Lightdown the default for `.md` files, open **Get Info** on any `.md` file in Finder, choose Lightdown under **Open with**, then click **Change All…**.

## Project layout

| Path | What it does |
|------|--------------|
| `Sources/Lightdown/EditorSplitViewController.swift` | Editor and preview panes, scroll sync, zoom, pane toggles |
| `Sources/Lightdown/MarkdownDocument.swift` | Opening, saving, HTML export, printing |
| `Sources/Lightdown/MarkdownRenderer.swift` | Markdown to HTML via cmark-gfm |
| `Sources/Lightdown/SyntaxHighlighter.swift` | Markdown colouring in the editor |
| `Sources/Lightdown/Zoom.swift` | Zoom steps and the saved zoom level |
| `Sources/Lightdown/main.swift` | App startup and menus |
| `Resources/preview.html`, `preview.css` | Preview page template and styles |
| `scripts/make-icon.swift` | Builds `AppIcon.icns` from `icon-source.jpg` |

To change the icon, replace `icon-source.jpg` and run `swift scripts/make-icon.swift icon-source.jpg`.

## Third-party code

These libraries are bundled in `Resources/`:

- [highlight.js](https://highlightjs.org) 11.9.0: BSD 3-Clause
- [Mermaid](https://mermaid.js.org) 11.12.0: MIT

This one is fetched by Swift Package Manager when you build:

- [swift-cmark](https://github.com/swiftlang/swift-cmark), `gfm` branch: BSD 2-Clause

## License

Lightdown is licensed under the [Apache License 2.0](LICENSE). Third-party notices are in [NOTICE](NOTICE).
