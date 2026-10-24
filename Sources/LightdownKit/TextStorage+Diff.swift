import AppKit

extension NSTextStorage {
    /// Replaces only the span between the common prefix and suffix of the old and new text,
    /// so selections and scroll positions outside the change stay where they were.
    func replaceChangedRange(with newText: String) {
        let old = string as NSString
        let new = newText as NSString
        let oldLength = old.length, newLength = new.length

        var prefix = 0
        let maxPrefix = min(oldLength, newLength)
        while prefix < maxPrefix, old.character(at: prefix) == new.character(at: prefix) { prefix += 1 }
        var suffix = 0
        let maxSuffix = maxPrefix - prefix
        while suffix < maxSuffix,
              old.character(at: oldLength - 1 - suffix) == new.character(at: newLength - 1 - suffix) { suffix += 1 }

        // Don't split a surrogate pair at either edge.
        if prefix > 0, prefix < oldLength, UTF16.isTrailSurrogate(old.character(at: prefix)) { prefix -= 1 }
        if suffix > 0, oldLength - suffix > 0, UTF16.isTrailSurrogate(old.character(at: oldLength - suffix)) { suffix -= 1 }

        let oldRange = NSRange(location: prefix, length: oldLength - prefix - suffix)
        let replacement = new.substring(with: NSRange(location: prefix, length: newLength - prefix - suffix))
        replaceCharacters(in: oldRange, with: replacement)
    }
}
