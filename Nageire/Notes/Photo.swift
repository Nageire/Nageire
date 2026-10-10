import Foundation
import ImageIO
import UniformTypeIdentifiers

/// How large a photo is kept and sent, the choice in Settings.
nonisolated enum PhotoSize: String, CaseIterable, Sendable {
    /// 2048 pixels on the long side, a few hundred kilobytes from a camera's 3 to 5 MB.
    case standard
    /// 4096 pixels on the long side.
    case large
    /// The photo's own pixels.
    case original

    /// The long side a photo is reduced to. Nil keeps the photo's own.
    var longSide: Int? {
        switch self {
        case .standard: 2048
        case .large: 4096
        case .original: nil
        }
    }
}

/// A photo as the app keeps it: a JPEG, reduced, turned the right way up, and without the place it was taken.
nonisolated enum Photo {
    /// The JPEG quality, which keeps a reduced photo to a few hundred kilobytes with no loss the eye sees on a phone.
    static let quality = 0.8

    /// The photo as a JPEG with its long side no longer than `longSide`, from any image the system reads, HEIC included.
    /// A photo smaller than that keeps its size. The location is taken out, since the repository may be public; the
    /// time it was taken and the camera stay.
    @concurrent
    static func jpeg(from contents: Data, longSide: Int?) async throws -> Data {
        guard let source = CGImageSourceCreateWithData(contents as CFData, nil),
              var properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { throw PhotoError.unreadable }
        let ownSide = max(width, height)
        // The pixels are turned as the camera's orientation says, so the file needs no orientation of its own.
        guard let image = reducedImage(source, longSide: min(longSide ?? ownSide, ownSide)) else { throw PhotoError.unreadable }
        properties[kCGImagePropertyGPSDictionary] = nil
        properties[kCGImagePropertyOrientation] = nil
        // The original's size would stay in the EXIF of a reduced photo.
        if var exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif[kCGImagePropertyExifPixelXDimension] = nil
            exif[kCGImagePropertyExifPixelYDimension] = nil
            properties[kCGImagePropertyExifDictionary] = exif
        }
        if var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = nil
            properties[kCGImagePropertyTIFFDictionary] = tiff
        }
        properties[kCGImageDestinationLossyCompressionQuality] = quality
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw PhotoError.unwritable
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PhotoError.unwritable }
        return output as Data
    }

    /// Whether a file of the name is reduced as a photo: an image the system reads, and one with no name, as from the
    /// camera or the clipboard. A GIF would lose its motion and an SVG is not pixels, so both are kept as they are.
    static func isReduced(_ name: String?) -> Bool {
        guard let name else { return true }
        guard let type = Attachment.type(of: name) else { return false }
        return type.conforms(to: .image) && !type.conforms(to: .gif) && !type.conforms(to: .svg)
    }

    /// The image turned the right way up with its long side at `longSide`, decoded at that size rather than whole.
    static func reducedImage(_ source: CGImageSource, longSide: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longSide,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The name a photo is kept under: its own with `.jpeg` for its extension, or, for a photo that has none, as one
    /// from the camera, the time it was taken in the camera's own form, as in `IMG_20261010_163012.jpeg`.
    static func fileName(for original: String?, takenAt date: Date, in timeZone: TimeZone = .current) -> String {
        if let original, case let stem = (original as NSString).deletingPathExtension, !stem.isEmpty {
            return "\(stem).jpeg"
        }
        let style = Date.VerbatimFormatStyle(
            format: "\(year: .defaultDigits)\(month: .twoDigits)\(day: .twoDigits)_\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits)",
            timeZone: timeZone,
            calendar: Calendar(identifier: .gregorian)
        )
        return "IMG_\(date.formatted(style)).jpeg"
    }
}

nonisolated enum PhotoError: Error {
    /// The file is not an image the system reads.
    case unreadable
    case unwritable
}
