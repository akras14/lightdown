import AppKit
import UniformTypeIdentifiers

/// Pasting and dropping images: files are linked (copied into `images/` when they live outside
/// the document's folder) and pasted image data is saved there as PNG.
extension EditorTextView {
    static let imageFolderName = "images"

    /// Whether `pasteboard` holds images we can paste: image files, or image data without text.
    static func hasImages(_ pasteboard: NSPasteboard) -> Bool {
        let files = pasteboard.canReadObject(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ])
        return files || (pasteboard.string(forType: .string) == nil && pasteboard.availableType(from: [.png, .tiff]) != nil)
    }

    /// Inserts Markdown image links for the images on `pasteboard` at `range`.
    /// Returns false when the pasteboard holds no images, so the caller can fall back to the default.
    func insertImages(from pasteboard: NSPasteboard, at range: NSRange) -> Bool {
        let files = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]) as? [URL] ?? []
        // Rich text copied from other apps often carries a picture of itself; only take raw image data
        // when there's no text to paste.
        let imageData = files.isEmpty && pasteboard.string(forType: .string) == nil
            ? (pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff)) : nil
        guard !files.isEmpty || imageData != nil else { return false }

        guard let documentFolder = documentURL?.deletingLastPathComponent() else {
            let alert = NSAlert()
            alert.messageText = "Save the document first"
            alert.informativeText = "Images are stored next to the document, so it needs a folder before you can add them."
            if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
            return true
        }

        do {
            var links: [String] = []
            for file in files {
                let target = try place(file, in: documentFolder)
                links.append(Self.imageLink(for: target, relativeTo: documentFolder))
            }
            if let imageData {
                let target = try savePNG(imageData, in: documentFolder)
                links.append(Self.imageLink(for: target, relativeTo: documentFolder))
            }
            insertText(links.joined(separator: "\n"), replacementRange: range)
        } catch {
            presentError(error)
        }
        return true
    }

    private var documentURL: URL? {
        (window?.windowController?.document as? NSDocument)?.fileURL
    }

    /// Images already inside the document's folder are used where they are; others are copied in.
    private func place(_ file: URL, in folder: URL) throws -> URL {
        let file = file.standardizedFileURL.resolvingSymlinksInPath()
        let folderPath = folder.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        if file.path.hasPrefix(folderPath) { return file }

        let target = try uniqueURL(in: folder, name: file.deletingPathExtension().lastPathComponent, ext: file.pathExtension)
        try FileManager.default.copyItem(at: file, to: target)
        return target
    }

    private func savePNG(_ data: Data, in folder: URL) throws -> URL {
        guard let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let stamp = Self.timestamp.string(from: Date())
        let target = try uniqueURL(in: folder, name: "pasted-\(stamp)", ext: "png")
        try png.write(to: target)
        return target
    }

    private func uniqueURL(in folder: URL, name: String, ext: String) throws -> URL {
        let images = folder.appendingPathComponent(Self.imageFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        var candidate = images.appendingPathComponent(name).appendingPathExtension(ext)
        var n = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = images.appendingPathComponent("\(name)-\(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }

    private static let timestamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    /// `![name](relative/path.png)`, with characters that would break the link percent-encoded.
    static func imageLink(for file: URL, relativeTo folder: URL) -> String {
        let folderPath = folder.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        let filePath = file.standardizedFileURL.resolvingSymlinksInPath().path
        let relative = filePath.hasPrefix(folderPath) ? String(filePath.dropFirst(folderPath.count)) : filePath
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "()")
        let encoded = relative.addingPercentEncoding(withAllowedCharacters: allowed) ?? relative
        let alt = file.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "]", with: "")
        return "![\(alt)](\(encoded))"
    }
}
