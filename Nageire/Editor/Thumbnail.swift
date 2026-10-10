import CoreGraphics
import Foundation
import ImageIO

/// A file's image reduced to fill the thumbnail of the editor, and how large the file is, for the caption.
nonisolated struct Thumbnail: Sendable {
    /// Nil for a file that is not an image.
    let image: CGImage?
    /// The file's size as the caption shows it, as in 1.2 MB.
    let size: String

    /// Decodes the file reduced to what fills `size` at `scale`, the one work the editor does on the file's bytes.
    init(contents: Data, filling size: CGSize, scale: CGFloat) {
        self.size = contents.count.formatted(.byteCount(style: .file))
        image = Self.image(of: contents, filling: size, scale: scale)
    }

    private static func image(of contents: Data, filling size: CGSize, scale: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(contents as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              var width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              var height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              width > 0, height > 0
        else { return nil }
        // A photo taken with the camera turned is stored on its side and carries the turn; the thumbnail is made turned the right way up.
        if let orientation = properties[kCGImagePropertyOrientation] as? UInt32, orientation >= 5 {
            swap(&width, &height)
        }
        // The thumbnail fills its frame: the side that falls short of the frame's sets the reduction, and the other side overflows.
        let reduction = min(max(size.width * scale / width, size.height * scale / height), 1)
        return Photo.reducedImage(source, longSide: Int((max(width, height) * reduction).rounded(.up)))
    }
}

/// The thumbnails of the files a note links to, decoded off the main actor as the lines that show them are first laid out.
/// The file itself is read on the main actor, mapped rather than copied: a photo is reduced to a few hundred kilobytes
/// before it is kept, so the read is short, and the one with the originals setting is the one to measure.
@MainActor
final class ThumbnailCache {
    private var thumbnails: [String: Thumbnail] = [:]
    private var decoding: Set<String> = []
    /// The file a link names. Nil while the device does not have the file.
    var attachment: (String) -> Data? = { _ in nil }
    /// Called with the link of each thumbnail once it is decoded.
    var onDecode: (String) -> Void = { _ in }
    /// The screen's scale, which the thumbnails are decoded for.
    var scale: CGFloat = 1

    /// The thumbnail of the file a link names once it is decoded, and nil before that, or for good while the device does not have the file.
    /// A file that arrives later is asked for again at the next layout of its line; nothing tells the cache of it yet.
    func thumbnail(for link: String) -> Thumbnail? {
        if let thumbnail = thumbnails[link] {
            return thumbnail
        }
        guard !decoding.contains(link), let contents = attachment(link) else { return nil }
        decoding.insert(link)
        Task(name: "thumbnail") { [scale] in
            decoded(await Self.decode(contents, scale: scale), for: link)
        }
        return nil
    }

    @concurrent
    private nonisolated static func decode(_ contents: Data, scale: CGFloat) async -> Thumbnail {
        Thumbnail(contents: contents, filling: EditorMetrics.thumbnail, scale: scale)
    }

    private func decoded(_ thumbnail: Thumbnail, for link: String) {
        thumbnails[link] = thumbnail
        decoding.remove(link)
        onDecode(link)
    }
}
