import AppKit
import Foundation

MainActor.assumeIsolated {
    _ = NSApplication.shared
    let args = CommandLine.arguments
    if args.count >= 4, args[1] == "--snapshot" {
        snapshot(markdown: URL(fileURLWithPath: args[2]), to: URL(fileURLWithPath: args[3]),
                 dark: args.contains("dark"))
        exit(0)
    }
    let t = Checker()
    todoListChecks(t)
    listMoveChecks(t)
    reloadChecks(t)
    formattingChecks(t)
    listChecks(t)
    previewChecks(t)
    imageChecks(t)
    exportChecks(t)
    headingChecks(t)
    scrollSyncChecks(t)
    outlineChecks(t)
    wordCountChecks(t)
    themeChecks(t)
    menuChecks(t)
    editStabilityChecks(t)
    sessionChecks(t)
    layoutChecks(t)
    undoChecks(t)

    print(t.failures == 0 ? "✔ \(t.count) checks passed" : "✘ \(t.failures) of \(t.count) checks failed")
    exit(t.failures == 0 ? 0 : 1)
}
