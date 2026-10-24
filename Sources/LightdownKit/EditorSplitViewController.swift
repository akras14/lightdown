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

    override func insertNewline(_ sender: Any?) {
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
        splitView.autosaveName = "LightdownSplit"

        editorItem = NSSplitViewItem(viewController: makeEditorPane())
        editorItem.minimumThickness = 200
        previewItem = NSSplitViewItem(viewController: makePreviewPane())
        previewItem.minimumThickness = 200
        previewItem.canCollapse = true
        editorItem.canCollapse = true
        addSplitViewItem(editorItem)
        addSplitViewItem(previewItem)

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
        let tv = EditorTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
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
        tv.backgroundColor = .textBackgroundColor
        tv.textStorage?.delegate = highlighter

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
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
        guard previewReady else { return }
        let html = MarkdownRenderer.html(from: textView.string, sourcePositions: true)
        let base = (document?.fileURL?.deletingLastPathComponent() ?? FileManager.default.homeDirectoryForCurrentUser).absoluteString
        let js = "ldSetBase(\(jsString(base))); ldRender(\(jsString(html))); ldScrollTo(\(scrollFraction()));"
        webView.evaluateJavaScript(js)
    }

    private func jsString(_ s: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [s], options: [.fragmentsAllowed])
        let array = String(decoding: data, as: UTF8.self)
        return String(array.dropFirst().dropLast())
    }

    // MARK: Scroll sync (editor -> preview)

    private func scrollFraction() -> Double {
        let clip = editorScrollView.contentView
        let docHeight = editorScrollView.documentView?.frame.height ?? 0
        let maxY = docHeight - clip.bounds.height
        guard maxY > 0 else { return 0 }
        return min(1, max(0, clip.bounds.origin.y / maxY))
    }

    @objc private func editorDidScroll() {
        guard previewReady else { return }
        webView.evaluateJavaScript("ldScrollTo(\(scrollFraction()))")
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

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        document?.undoManager
    }
}
