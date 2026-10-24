import AppKit

/// Start offsets of each line, rebuilt lazily after edits so scroll sync can map
/// character positions to line numbers without rescanning the text.
final class LineIndex {
    private weak var storage: NSTextStorage?
    private var starts: [Int]?

    init(storage: NSTextStorage) {
        self.storage = storage
        NotificationCenter.default.addObserver(self, selector: #selector(invalidate),
                                               name: NSTextStorage.didProcessEditingNotification, object: storage)
    }

    @objc private func invalidate() { starts = nil }

    private var lineStarts: [Int] {
        if let starts { return starts }
        let text = (storage?.string ?? "") as NSString
        var buffer = [unichar](repeating: 0, count: text.length)
        text.getCharacters(&buffer, range: NSRange(location: 0, length: text.length))
        var result = [0]
        for (i, c) in buffer.enumerated() where c == 0x0A { result.append(i + 1) }
        starts = result
        return result
    }

    var count: Int { lineStarts.count }

    /// 0-based line containing the character at `location`.
    func line(containing location: Int) -> Int {
        let starts = lineStarts
        var lo = 0, hi = starts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if starts[mid] <= location { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// Character range of a 0-based line, including its newline.
    func range(ofLine line: Int) -> NSRange {
        let starts = lineStarts
        let start = starts[line]
        let end = line + 1 < starts.count ? starts[line + 1] : (storage?.length ?? start)
        return NSRange(location: start, length: end - start)
    }
}

/// Scroll positions in terms of source lines, for syncing with the preview. Lines are 1-based and
/// fractional (12.5 is halfway through line 12); values below 1 cover the inset above the first line.
extension EditorTextView {
    var lineIndex: LineIndex {
        if let index = objc_getAssociatedObject(self, &lineIndexKey) as? LineIndex { return index }
        let index = LineIndex(storage: textStorage!)
        objc_setAssociatedObject(self, &lineIndexKey, index, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return index
    }

    func topVisibleLine() -> Double {
        guard let layoutManager, let textContainer, let clip = enclosingScrollView?.contentView else { return 1 }
        let inset = textContainerOrigin.y
        let y = clip.bounds.minY - inset
        if y < 0 { return inset > 0 ? max(0, 1 + Double(y / inset)) : 1 }

        let glyph = layoutManager.glyphIndex(for: NSPoint(x: 0, y: y), in: textContainer)
        let line = lineIndex.line(containing: layoutManager.characterIndexForGlyph(at: glyph))
        let rect = self.rect(ofLine: line)
        let fraction = rect.height > 0 ? min(1, max(0, (y - rect.minY) / rect.height)) : 0
        return Double(line + 1) + Double(fraction)
    }

    func scrollToLine(_ line: Double) {
        guard let clip = enclosingScrollView?.contentView, let documentView = enclosingScrollView?.documentView else { return }
        let inset = textContainerOrigin.y
        var y: CGFloat
        if line < 1 {
            y = CGFloat(line) * inset
        } else {
            let index = min(Int(line) - 1, lineIndex.count - 1)
            let rect = self.rect(ofLine: index)
            y = rect.minY + CGFloat(line - Double(index + 1)) * rect.height + inset
        }
        y = min(max(0, y), max(0, documentView.frame.height - clip.bounds.height))
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: y))
        enclosingScrollView?.reflectScrolledClipView(clip)
    }

    var isScrolledToBottom: Bool {
        guard let clip = enclosingScrollView?.contentView, let documentView = enclosingScrollView?.documentView else { return false }
        return documentView.frame.height > clip.bounds.height + 1 && clip.bounds.maxY >= documentView.frame.height - 1
    }

    func scrollToBottom() {
        guard let clip = enclosingScrollView?.contentView, let documentView = enclosingScrollView?.documentView else { return }
        // Layout is non-contiguous, so the full height is only known once the end is laid out.
        if let layoutManager, let textContainer { layoutManager.ensureLayout(for: textContainer) }
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: max(0, documentView.frame.height - clip.bounds.height)))
        enclosingScrollView?.reflectScrolledClipView(clip)
    }

    /// Vertical extent of a source line in text container coordinates, across all of its wrapped fragments.
    private func rect(ofLine line: Int) -> NSRect {
        guard let layoutManager else { return .zero }
        let chars = lineIndex.range(ofLine: line)
        let glyphs = layoutManager.glyphRange(forCharacterRange: chars, actualCharacterRange: nil)
        if glyphs.length == 0 {
            return layoutManager.extraLineFragmentRect.isEmpty
                ? layoutManager.lineFragmentRect(forGlyphAt: max(0, layoutManager.numberOfGlyphs - 1), effectiveRange: nil)
                : layoutManager.extraLineFragmentRect
        }
        let first = layoutManager.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        let last = layoutManager.lineFragmentRect(forGlyphAt: NSMaxRange(glyphs) - 1, effectiveRange: nil)
        return NSRect(x: first.minX, y: first.minY, width: first.width, height: last.maxY - first.minY)
    }
}

private var lineIndexKey = 0
