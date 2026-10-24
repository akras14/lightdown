import AppKit

/// App appearance (System / Light / Dark) and the colours the editor shares with the preview.
enum Theme {
    enum Appearance: Int, CaseIterable {
        case system, light, dark

        var title: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }

        var nsAppearance: NSAppearance? {
            switch self {
            case .system: return nil
            case .light: return NSAppearance(named: .aqua)
            case .dark: return NSAppearance(named: .darkAqua)
            }
        }
    }

    private static let appearanceKey = "appearance"

    static var appearance: Appearance {
        get { Appearance(rawValue: UserDefaults.standard.integer(forKey: appearanceKey)) ?? .system }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: appearanceKey)
            NSApp.appearance = newValue.nsAppearance
        }
    }

    static func applySavedAppearance() {
        NSApp.appearance = appearance.nsAppearance
    }

    /// Matches `--bg` in preview.css so the editor and preview read as one surface.
    static let background = NSColor(name: "LightdownBackground") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0x0d / 255, green: 0x11 / 255, blue: 0x17 / 255, alpha: 1)
            : .white
    }
}
