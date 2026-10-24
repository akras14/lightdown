import Foundation

enum WordCount {
    /// Words as the system's word boundaries see them, so Markdown symbols (#, -, [ ]) don't count.
    static func count(in text: String) -> Int {
        var count = 0
        (text as NSString).enumerateSubstrings(in: NSRange(location: 0, length: (text as NSString).length),
                                               options: [.byWords, .substringNotRequired]) { _, _, _, _ in count += 1 }
        return count
    }

    static func label(_ count: Int, of total: Int? = nil) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        func format(_ n: Int) -> String { formatter.string(from: NSNumber(value: n)) ?? "\(n)" }
        if let total { return "\(format(count)) of \(format(total)) words" }
        return count == 1 ? "1 word" : "\(format(count)) words"
    }
}
