import AppKit

/// Which build is running. build.sh stamps the commit count as CFBundleVersion and the short
/// commit hash as LightdownCommit, so About tells apart builds that share a marketing version.
enum AppVersion {
    static func build(from info: [String: Any]) -> String {
        let number = info["CFBundleVersion"] as? String ?? "?"
        guard let commit = info["LightdownCommit"] as? String else { return number }
        return "\(number) · \(commit)"
    }

    @MainActor static func showAboutPanel() {
        NSApp.orderFrontStandardAboutPanel(options: [.version: build(from: Bundle.main.infoDictionary ?? [:])])
    }
}
