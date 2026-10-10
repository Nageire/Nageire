import Foundation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// A file handed to the editor from the file picker, the clipboard, or a drop, known by its name and size before it is read.
nonisolated struct IncomingFile: Sendable {
    /// Nil for an image with no name of its own, as one copied from a page or a screenshot.
    let name: String?
    let size: Int
    /// Reads the file. Called once it is decided that the file is kept, since a file can be large.
    let read: @Sendable () throws -> Data
}

nonisolated extension IncomingFile {
    /// Reads the file off the main actor: it can be up to 100 MB, and a file in the cloud is fetched as it is read.
    @concurrent
    func contents() async throws -> Data {
        try read()
    }

    init(contents: Data, name: String?) {
        self.init(name: name, size: contents.count) { contents }
    }

    /// A file at a URL, which may be outside the app's sandbox, as one from the file picker or a drop.
    init(url: URL) throws {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        self.init(name: url.lastPathComponent, size: size) {
            let isScoped = url.startAccessingSecurityScopedResource()
            defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
            return try Data(contentsOf: url, options: .mappedIfSafe)
        }
    }

    /// Whether an item of the clipboard or a drop is a file rather than text. Text goes in as text, as before; a file
    /// that is text, as a `.txt` or a `.md`, does as well, since the system offers its contents as text.
    static func isFile(_ types: [UTType]) -> Bool {
        !types.contains { $0.conforms(to: .text) } && types.contains { $0.conforms(to: .data) || $0.conforms(to: .fileURL) }
    }

    /// The file an item provider holds, copied out of the system's place for it, which is gone once the provider has handed it over.
    static func load(from provider: NSItemProvider) async throws -> IncomingFile {
        guard let type = provider.registeredContentTypes.first(where: { $0.conforms(to: .data) }) else {
            throw CocoaError(.fileReadUnknown)
        }
        let suggested = provider.suggestedName
        let copy: URL = try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadFileRepresentation(for: type, openInPlace: false) { url, _, error in
                guard let url else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                    return
                }
                do {
                    // The system's copy is already a copy of its own, so it is moved, not copied again.
                    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let copy = folder.appending(path: url.lastPathComponent)
                    try FileManager.default.moveItem(at: url, to: copy)
                    continuation.resume(returning: copy)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        let file = try IncomingFile(url: copy)
        // An image with no name of its own is named as a photo is; a file keeps the name it was handed over with.
        let name: String? = if let suggested {
            (suggested as NSString).pathExtension.isEmpty ? type.preferredFilenameExtension.map { "\(suggested).\($0)" } ?? suggested : suggested
        } else if type.conforms(to: .image) {
            nil
        } else {
            file.name
        }
        // The copy goes when the file does, read or not: a file refused or cancelled is never read.
        let folder = TemporaryFolder(url: copy.deletingLastPathComponent())
        return IncomingFile(name: name, size: file.size) {
            _ = folder
            return try file.read()
        }
    }

    #if os(macOS)
    /// The types of a pasteboard that hold a file rather than text.
    static let pasteboardTypes: [NSPasteboard.PasteboardType] = [.fileURL, .png, .tiff]

    /// Whether the pasteboard holds files, without reading them: asked on each move of a drag.
    static func holdsFiles(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            || pasteboard.availableType(from: [.string]) == nil && pasteboard.availableType(from: [.png, .tiff]) != nil
    }

    /// The files on a pasteboard: files copied in the Finder or dragged, or an image copied without a file. Empty when the
    /// pasteboard holds text, which is pasted as text.
    static func files(on pasteboard: NSPasteboard) -> [IncomingFile] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !urls.isEmpty {
            return urls.compactMap { try? IncomingFile(url: $0) }
        }
        guard pasteboard.availableType(from: [.string]) == nil, let image = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) else {
            return []
        }
        return [IncomingFile(contents: image, name: nil)]
    }
    #endif
}

/// A folder of the app's own under the temporary directory, removed when nothing holds it any more.
private nonisolated final class TemporaryFolder: Sendable {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
