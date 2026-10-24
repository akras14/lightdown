import Foundation

/// One app-wide zoom level shared by the editor and the preview, persisted across launches.
enum Zoom {
    static let didChange = Notification.Name("LightdownZoomDidChange")

    private static let key = "zoomLevel"
    private static let steps: [Double] = [0.5, 0.67, 0.75, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]
    static let baseEditorFontSize: Double = 14

    static var level: Double {
        get {
            let v = UserDefaults.standard.double(forKey: key)
            return v > 0 ? v : 1.0
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    static func zoomIn() {
        level = steps.first(where: { $0 > level + 0.001 }) ?? steps.last!
    }

    static func zoomOut() {
        level = steps.last(where: { $0 < level - 0.001 }) ?? steps.first!
    }

    static func reset() {
        level = 1.0
    }
}
