import AppKit
import WebKit

/// Accumulates trackpad pinch gestures into discrete app-wide zoom steps.
private struct PinchZoom {
    private var accumulated: CGFloat = 0

    mutating func handle(_ event: NSEvent) {
        if event.phase == .began { accumulated = 0 }
        accumulated += event.magnification
        if accumulated > 0.12 { Zoom.zoomIn(); accumulated = 0 }
        if accumulated < -0.12 { Zoom.zoomOut(); accumulated = 0 }
    }
}

final class EditorTextView: NSTextView {
    private var pinch = PinchZoom()
    override func magnify(with event: NSEvent) { pinch.handle(event) }

    // Undo a word or line at a time, as in VS Code. By default NSTextView coalesces everything
    // typed since the caret last moved into one undo step.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        let location = replacementRange.location == NSNotFound ? selectedRange().location : replacementRange.location
        if !hasMarkedText(), let first = text.unicodeScalars.first, location > 0,
           !CharacterSet.whitespacesAndNewlines.contains(first),
           let before = UnicodeScalar((self.string as NSString).character(at: location - 1)),
           CharacterSet.whitespacesAndNewlines.contains(before) {
            breakUndoCoalescing()
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    override func insertNewline(_ sender: Any?) {
        breakUndoCoalescing()
        if !continueList() { super.insertNewline(sender) }
    }

    override func insertTab(_ sender: Any?) {
        if !shiftListItems(indent: true) { super.insertTab(sender) }
    }

    override func insertBacktab(_ sender: Any?) {
        if !shiftListItems(indent: false) { super.insertBacktab(sender) }
    }

    override func paste(_ sender: Any?) {
        if !insertImages(from: .general, at: selectedRange()) { super.paste(sender) }
    }

    // A plain-text view disables Paste when the clipboard holds only an image (e.g. a screenshot),
    // so ⌘V would never reach paste(_:) above.
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(paste(_:)), Self.hasImages(.general) { return true }
        return super.validateUserInterfaceItem(item)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let index = characterIndexForInsertion(at: convert(sender.draggingLocation, from: nil))
        if insertImages(from: sender.draggingPasteboard, at: NSRange(location: index, length: 0)) {
            window?.makeFirstResponder(self)
            return true
        }
        return super.performDragOperation(sender)
    }

    // ⇧⌘↑/↓ move list items; elsewhere they keep selecting to the start/end of the document.
    @IBAction func moveItemUp(_ sender: Any?) {
        if !moveListItem(up: true) { moveToBeginningOfDocumentAndModifySelection(sender) }
    }

    @IBAction func moveItemDown(_ sender: Any?) {
        if !moveListItem(up: false) { moveToEndOfDocumentAndModifySelection(sender) }
    }
}

/// The window's content: the split view with the status bar below it.
final class DocumentViewController: NSViewController {
    let editor: EditorSplitViewController

    init(document: MarkdownDocument) {
        editor = EditorSplitViewController(document: document)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        addChild(editor)
        let split = editor.view, bar = editor.statusBar
        split.translatesAutoresizingMaskIntoConstraints = false
        bar.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
        container.addSubview(split)
        container.addSubview(bar)
        NSLayoutConstraint.activate([
            split.topAnchor.constraint(equalTo: container.topAnchor),
            split.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bar.topAnchor.constraint(equalTo: split.bottomAnchor),
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        view = container
    }
}

/// A view filled with the editor background, so the status bar matches the text area in both themes.
final class BackgroundView: NSView {
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { layer?.backgroundColor = Theme.background.cgColor }
}

/// WKUserContentController retains its handlers; this keeps it from retaining the controller.
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

final class PreviewWebView: WKWebView {
    private var pinch = PinchZoom()
    override func magnify(with event: NSEvent) { pinch.handle(event) }
}

final class EditorSplitViewController: NSSplitViewController, NSTextViewDelegate, WKNavigationDelegate, WKScriptMessageHandler, NSWindowDelegate, NSMenuItemValidation {
    private weak var document: MarkdownDocument?

    private let highlighter = SyntaxHighlighter()
    private(set) var textView: EditorTextView!
    private var editorScrollView: NSScrollView!
    private(set) var webView: PreviewWebView!
    private var editorItem: NSSplitViewItem!
    private var previewItem: NSSplitViewItem!
    private var outlineItem: NSSplitViewItem!
    private(set) var outline = OutlineViewController()

    private static let showOutlineKey = "showOutline"

    private(set) var previewReady = false
    private var renderWorkItem: DispatchWorkItem?

    var currentText: String { textView.string }

    init(document: MarkdownDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        // New name: positions saved with the outline on the left don't fit this order.
        splitView.autosaveName = "LightdownSplitOutlineRight"

        editorItem = NSSplitViewItem(viewController: makeEditorPane())
        editorItem.minimumThickness = 200
        previewItem = NSSplitViewItem(viewController: makePreviewPane())
        previewItem.minimumThickness = 200
        previewItem.canCollapse = true
        editorItem.canCollapse = true
        addSplitViewItem(editorItem)
        addSplitViewItem(previewItem)

        // The outline sits on the right, as in Obsidian, and keeps its width when the window resizes.
        outline.onSelect = { [weak self] heading in self?.jump(to: heading) }
        outlineItem = NSSplitViewItem(viewController: outline)
        outlineItem.canCollapse = true
        outlineItem.holdingPriority = .init(260)
        outlineItem.minimumThickness = 150
        outlineItem.maximumThickness = 400
        outlineItem.isCollapsed = !UserDefaults.standard.bool(forKey: Self.showOutlineKey)
        addSplitViewItem(outlineItem)

        NotificationCenter.default.addObserver(self, selector: #selector(applyZoom), name: Zoom.didChange, object: nil)
        applyZoom()
        reloadFromDocument()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textView)
    }

    // MARK: Panes

    private func makeEditorPane() -> NSViewController {
        let scrollView = NSScrollView()
        // TextKit 1: scroll sync needs exact line geometry from NSLayoutManager.
        let tv = EditorTextView(usingTextLayoutManager: false)
        tv.frame = NSRect(origin: .zero, size: scrollView.contentSize)
        // Contiguous layout: estimated heights above the viewport made scroll positions shift after every
        // edit (the highlighter re-styles the whole document), which scroll sync then amplified.
        tv.layoutManager?.allowsNonContiguousLayout = false
        tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        scrollView.documentView = tv

        tv.delegate = self
        tv.allowsUndo = true
        tv.isRichText = false
        tv.importsGraphics = false
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.textContainerInset = NSSize(width: 16, height: 20)
        tv.backgroundColor = Theme.background
        tv.textStorage?.delegate = highlighter

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Theme.background
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(editorDidScroll),
                                               name: NSView.boundsDidChangeNotification, object: scrollView.contentView)

        textView = tv
        editorScrollView = scrollView
        let vc = NSViewController()
        vc.view = scrollView
        return vc
    }

    private func makePreviewPane() -> NSViewController {
        let config = WKWebViewConfiguration()
        config.userContentController.add(WeakScriptMessageHandler(self), name: "lightdown")
        let wv = PreviewWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        wv.allowsMagnification = false
        wv.setValue(false, forKey: "drawsBackground")
        if let template = AppResources.url("preview.html") {
            wv.loadFileURL(template, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        }
        webView = wv
        let vc = NSViewController()
        vc.view = wv
        return vc
    }

    // MARK: Content

    func reloadFromDocument() {
        guard isViewLoaded, let document else { return }
        if textView.string != document.text, let storage = textView.textStorage {
            // Replace only the part that changed so the caret and scroll position survive a reload.
            storage.replaceChangedRange(with: document.text)
            textView.undoManager?.removeAllActions()
        }
        renderPreview()
    }

    func textDidChange(_ notification: Notification) {
        renderWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.renderPreview() }
        renderWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
    }

    private func renderPreview() {
        documentWordCount = WordCount.count(in: textView.string)
        updateWordCount()
        outline.update(OutlineParser.headings(in: textView.string))
        outline.highlightSection(atLine: textView.topVisibleLine())
        guard previewReady else { return }
        let html = MarkdownRenderer.html(from: textView.string, sourcePositions: true)
        let base = (document?.fileURL?.deletingLastPathComponent() ?? FileManager.default.homeDirectoryForCurrentUser).absoluteString
        let js = "ldSetBase(\(jsString(base))); ldRender(\(jsString(html))); \(syncScript())"
        webView.evaluateJavaScript(js)
    }

    private func jsString(_ s: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [s], options: [.fragmentsAllowed])
        let array = String(decoding: data, as: UTF8.self)
        return String(array.dropFirst().dropLast())
    }

    // MARK: Word count

    private var documentWordCount = 0
    private(set) var wordCountLabel = NSTextField(labelWithString: "")

    /// A slim bar across the bottom of the window for the word count, spanning all panes so it
    /// doesn't take part in the split layout. (The window subtitle didn't redraw reliably while
    /// typing once documents were open as tabs.)
    private(set) lazy var statusBar: NSView = {
        wordCountLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        wordCountLabel.textColor = .secondaryLabelColor
        wordCountLabel.alignment = .right
        wordCountLabel.translatesAutoresizingMaskIntoConstraints = false
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let bar = BackgroundView()
        bar.addSubview(separator)
        bar.addSubview(wordCountLabel)
        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: bar.topAnchor),
            separator.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            wordCountLabel.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 3),
            wordCountLabel.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -4),
            wordCountLabel.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            wordCountLabel.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
        ])
        return bar
    }()

    func textViewDidChangeSelection(_ notification: Notification) {
        updateWordCount()
    }

    private func updateWordCount() {
        let selection = textView.selectedRange()
        wordCountLabel.stringValue = selection.length > 0
            ? WordCount.label(WordCount.count(in: (textView.string as NSString).substring(with: selection)), of: documentWordCount)
            : WordCount.label(documentWordCount)
    }

    // MARK: Scroll sync

    /// Ignore editor scroll events caused by following the preview, so the panes don't fight.
    private var followingPreviewUntil = Date.distantPast

    private func syncScript() -> String {
        "ldScrollToLine(\(textView.topVisibleLine()), \(textView.isScrolledToBottom));"
    }

    @objc private func editorDidScroll() {
        if !outlineItem.isCollapsed { outline.highlightSection(atLine: textView.topVisibleLine()) }
        guard previewReady, Date() >= followingPreviewUntil else { return }
        webView.evaluateJavaScript(syncScript())
    }

    private func previewDidScroll(toLine line: Double, atBottom: Bool) {
        followingPreviewUntil = Date().addingTimeInterval(0.15)
        if atBottom { textView.scrollToBottom() } else { textView.scrollToLine(line) }
    }

    // MARK: Zoom

    @objc private func applyZoom() {
        let level = Zoom.level
        highlighter.fontSize = CGFloat(Zoom.baseEditorFontSize * level)
        textView.font = .monospacedSystemFont(ofSize: highlighter.fontSize, weight: .regular)
        textView.typingAttributes[.font] = textView.font
        if let storage = textView.textStorage {
            storage.beginEditing()
            highlighter.highlight(storage)
            storage.endEditing()
        }
        webView.pageZoom = level
    }

    @IBAction func zoomIn(_ sender: Any?) { Zoom.zoomIn() }
    @IBAction func zoomOut(_ sender: Any?) { Zoom.zoomOut() }
    @IBAction func resetZoom(_ sender: Any?) { Zoom.reset() }

    // MARK: Layout toggles

    @IBAction func toggleOutline(_ sender: Any?) {
        outlineItem.animator().isCollapsed.toggle()
        UserDefaults.standard.set(!outlineItem.isCollapsed, forKey: Self.showOutlineKey)
        if !outlineItem.isCollapsed { outline.highlightSection(atLine: textView.topVisibleLine()) }
    }

    /// Scrolls the editor so the heading is at the top (the preview follows) and puts the caret on it.
    func jump(to heading: Heading) {
        guard heading.line - 1 < textView.lineIndex.count else { return }
        let range = textView.lineIndex.range(ofLine: heading.line - 1)
        textView.setSelectedRange(NSRange(location: range.location, length: 0))
        textView.scrollToLine(Double(heading.line))
        view.window?.makeFirstResponder(textView)
    }

    @IBAction func togglePreview(_ sender: Any?) {
        if previewItem.isCollapsed == false && editorItem.isCollapsed { return }
        previewItem.animator().isCollapsed.toggle()
    }

    @IBAction func toggleEditor(_ sender: Any?) {
        if editorItem.isCollapsed == false && previewItem.isCollapsed { return }
        editorItem.animator().isCollapsed.toggle()
        if editorItem.isCollapsed == false { view.window?.makeFirstResponder(textView) }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(togglePreview(_:)):
            menuItem.title = previewItem.isCollapsed ? "Show Preview" : "Hide Preview"
            return !editorItem.isCollapsed
        case #selector(toggleEditor(_:)):
            menuItem.title = editorItem.isCollapsed ? "Show Editor" : "Hide Editor"
            return !previewItem.isCollapsed
        case #selector(toggleOutline(_:)):
            menuItem.title = outlineItem.isCollapsed ? "Show Outline" : "Hide Outline"
            return true
        case #selector(resetZoom(_:)):
            return abs(Zoom.level - 1) > 0.001
        default:
            return super.validateUserInterfaceItem(menuItem)
        }
    }

    // MARK: Copy HTML

    /// Copies the rendered HTML of the selection (or the whole document): as source for plain-text
    /// apps and as formatted text for rich editors like Mail or Google Docs.
    @IBAction func copyHTML(_ sender: Any?) {
        let selection = textView.selectedRange()
        let markdown = selection.length > 0 ? (textView.string as NSString).substring(with: selection) : textView.string
        let html = MarkdownRenderer.html(from: markdown)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(html, forType: .string)
        pasteboard.setString(html, forType: .html)
    }

    // MARK: Messages from the preview

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "previewScroll":
            if let line = body["line"] as? Double {
                previewDidScroll(toLine: line, atBottom: body["atBottom"] as? Bool ?? false)
            }
        case "toggleTask":
            if let line = body["line"] as? Int { textView.toggleTaskCheckbox(line: line - 1) }
        default:
            break
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        previewReady = true
        renderPreview()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        NSWorkspace.shared.open(url)
        decisionHandler(.cancel)
    }

    // MARK: NSWindowDelegate

    /// An empty Untitled document goes away once you move to another document (another tab,
    /// or a file you just opened), so it doesn't linger next to real ones.
    func windowDidResignMain(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.closeIfEmptyUntitled(newMainWindow: NSApp.mainWindow)
        }
    }

    func closeIfEmptyUntitled(newMainWindow: NSWindow?) {
        guard let document, document.isEmptyUntitled,
              let newMainWindow, newMainWindow !== view.window,
              newMainWindow.windowController?.document is MarkdownDocument else { return }
        document.close()
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        document?.undoManager
    }
}
