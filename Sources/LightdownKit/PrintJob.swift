import AppKit
import WebKit

/// Lays out a document's exported HTML in an offscreen web view for printing and PDF export,
/// so the output doesn't inherit the preview's zoom or dark appearance. Waits for Mermaid
/// diagrams to finish rendering before handing the view over.
final class PrintJob: NSObject, WKNavigationDelegate {
    private let window: NSWindow
    private let webView: WKWebView
    private let pageFile: URL
    private var ready: ((WKWebView) -> Void)?
    private static var running = Set<PrintJob>()   // keeps jobs alive while loading

    private init(html: String, ready: @escaping (WKWebView) -> Void) {
        window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 800, height: 1000),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        webView = WKWebView(frame: window.contentView!.bounds)
        webView.appearance = NSAppearance(named: .aqua)
        window.contentView = webView
        pageFile = FileManager.default.temporaryDirectory.appendingPathComponent("lightdown-print-\(UUID().uuidString).html")
        self.ready = ready
        super.init()
        webView.navigationDelegate = self
        try? html.write(to: pageFile, atomically: true, encoding: .utf8)
        webView.loadFileURL(pageFile, allowingReadAccessTo: URL(fileURLWithPath: "/"))
    }

    static func start(html: String, ready: @escaping (WKWebView) -> Void) {
        running.insert(PrintJob(html: html, ready: ready))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        waitForDiagrams(attempts: 100)
    }

    private func waitForDiagrams(attempts: Int) {
        webView.evaluateJavaScript("document.querySelectorAll('.mermaid:not([data-processed])').length") { [self] value, _ in
            if (value as? Int ?? 0) > 0, attempts > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.waitForDiagrams(attempts: attempts - 1) }
            } else {
                finish()
            }
        }
    }

    private func finish() {
        ready?(webView)
        ready = nil
        try? FileManager.default.removeItem(at: pageFile)
        // Stay alive until the print operation that uses the view has finished.
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { Self.running.remove(self) }
    }
}

extension MarkdownDocument {
    override func printDocument(_ sender: Any?) {
        runPrintJob(savingTo: nil)
    }

    @IBAction func exportPDF(_ sender: Any?) {
        guard let window = windowControllers.first?.window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = (displayName as NSString).deletingPathExtension + ".pdf"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.exportPDF(to: url)
        }
    }

    func exportPDF(to url: URL, completion: ((Bool) -> Void)? = nil) {
        runPrintJob(savingTo: url) { success in
            if success, FileManager.default.fileExists(atPath: url.path) { Self.revealInFinder(url) }
            completion?(success)
        }
    }

    /// Prints (with the print panel) or, given a URL, saves a PDF there without any panels.
    func runPrintJob(savingTo url: URL?, completion: ((Bool) -> Void)? = nil) {
        let html = Self.standaloneHTML(title: displayName, body: MarkdownRenderer.html(from: currentText),
                                       baseURL: fileURL?.deletingLastPathComponent())
        let info = printInfo.copy() as! NSPrintInfo
        info.topMargin = 36; info.bottomMargin = 36; info.leftMargin = 36; info.rightMargin = 36
        if let url {
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        }

        PrintJob.start(html: html) { [weak self] webView in
            guard let self else { return }
            let op = webView.printOperation(with: info)
            op.showsPrintPanel = url == nil
            op.showsProgressPanel = url == nil
            op.jobTitle = self.displayName
            // WKWebView's print view starts with a zero frame and prints blank pages without this.
            op.view?.frame = NSRect(origin: .zero, size: info.paperSize)
            self.printCompletion = completion
            if let window = self.windowControllers.first?.window {
                op.runModal(for: window, delegate: self,
                            didRun: #selector(self.printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
            } else {
                completion?(op.run())
            }
        }
    }

    @objc private func printOperationDidRun(_ op: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        printCompletion?(success)
        printCompletion = nil
    }
}
