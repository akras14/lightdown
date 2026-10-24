import AppKit
@testable import LightdownKit

@MainActor
func themeChecks(_ t: Checker) {
    t.group("appearance") {
        let saved = Theme.appearance
        defer { Theme.appearance = saved }

        let h = DocumentHarness("# Hi\n")
        defer { h.close() }
        t.expect(h.waitForPreview(), true, "preview loaded")

        @MainActor func previewBackground() -> String? {
            evaluate("getComputedStyle(document.documentElement).backgroundColor", in: h.webView) as? String
        }
        @MainActor func editorBackground() -> NSColor {
            var color = NSColor.clear
            h.editor.textView.effectiveAppearance.performAsCurrentDrawingAppearance {
                color = Theme.background.usingColorSpace(.sRGB)!
            }
            return color
        }

        Theme.appearance = .dark
        t.expect(NSApp.appearance?.name, .darkAqua, "dark applied")
        t.expect(waitUntil { previewBackground() == "rgb(13, 17, 23)" }, true, "preview dark (got \(previewBackground() ?? "nil"))")
        t.expect(Int(round(editorBackground().redComponent * 255)), 13, "editor matches preview in dark")

        Theme.appearance = .light
        t.expect(waitUntil { previewBackground() == "rgb(255, 255, 255)" }, true, "preview light")
        t.expect(editorBackground().redComponent, 1, "editor matches preview in light")

        Theme.appearance = .system
        t.expect(NSApp.appearance == nil, true, "system follows macOS")
        t.expect(UserDefaults.standard.integer(forKey: "appearance"), 0, "remembered")
    }
}
