import AppKit
@testable import LightdownKit

/// Types `text` into `window` as real key presses, one run-loop turn per key, like a person typing.
@MainActor
func type(_ text: String, in window: NSWindow) {
    for c in text {
        let chars = c == "\n" ? "\r" : String(c)
        let keyCode: UInt16 = c == "\n" ? 36 : 0
        for kind in [NSEvent.EventType.keyDown, .keyUp] {
            let event = NSEvent.keyEvent(with: kind, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber, context: nil, characters: chars,
                                         charactersIgnoringModifiers: chars, isARepeat: false, keyCode: keyCode)!
            NSApp.sendEvent(event)
        }
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
}

/// Regression: ⌘Z undid everything typed since the caret last moved (AppKit's default), and
/// formatting commands merged into the typing before them.
@MainActor
func undoChecks(_ t: Checker) {
    @MainActor func session(_ body: (DocumentHarness, NSWindow, () -> [String]) -> Void) {
        let h = DocumentHarness("")
        defer { h.close() }
        let window = h.editor.view.window!
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(h.editor.textView)
        /// Undoes until nothing is left, returning the text after each step.
        func undoAll() -> [String] {
            var steps: [String] = []
            while let undo = h.document.undoManager, undo.canUndo, steps.count < 20 {
                undo.undo()
                steps.append(h.text)
            }
            return steps
        }
        body(h, window, undoAll)
        window.orderOut(nil)
    }

    t.group("undo a word at a time") {
        session { h, window, undoAll in
            type("hello big world", in: window)
            t.expect(undoAll(), ["hello big ", "hello ", ""])
        }
    }

    t.group("undo lines and list continuation") {
        session { h, window, undoAll in
            type("one\n- item\nnext", in: window)
            t.expect(h.text, "one\n- item\n- next")
            t.expect(undoAll(), ["one\n- item\n- ", "one\n- item", "one\n- ", "one\n", "one", ""])
        }
    }

    t.group("formatting commands are their own undo step") {
        session { h, window, undoAll in
            type("buy milk", in: window)
            h.editor.textView.toggleTodo(nil)
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            type(" now", in: window)
            t.expect(h.text, "- [ ] buy milk now")
            t.expect(undoAll(), ["- [ ] buy milk ", "- [ ] buy milk", "buy milk", "buy ", ""])
        }
        session { h, window, undoAll in
            type("so ", in: window)
            h.editor.textView.formatBold(nil)
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            type("bold", in: window)
            t.expect(h.text, "so **bold**")
            t.expect(undoAll(), ["so ****", "so ", ""])
        }
    }
}
