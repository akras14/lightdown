import Foundation

/// Bundled preview resources (CSS, scripts, the preview page). Tests point `directory`
/// at the repo's Resources folder since they don't run from the app bundle.
enum AppResources {
    static var directory = Bundle.main.resourceURL

    static func url(_ name: String) -> URL? {
        guard let url = directory?.appendingPathComponent(name),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    static func text(_ name: String) -> String {
        url(name).flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }
}
