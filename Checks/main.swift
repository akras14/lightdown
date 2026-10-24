import AppKit
import Foundation

MainActor.assumeIsolated {
    _ = NSApplication.shared
    let t = Checker()
    todoListChecks(t)
    listMoveChecks(t)
    reloadChecks(t)
    formattingChecks(t)
    listChecks(t)
    previewChecks(t)

    print(t.failures == 0 ? "✔ \(t.count) checks passed" : "✘ \(t.failures) of \(t.count) checks failed")
    exit(t.failures == 0 ? 0 : 1)
}
