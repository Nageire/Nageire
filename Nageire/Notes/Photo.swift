import Foundation
import ImageIO

/// A photo as the app keeps it.
nonisolated enum Photo {
    /// The image turned the right way up with its long side at `longSide`, decoded at that size rather than whole.
    static func reducedImage(_ source: CGImageSource, longSide: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longSide,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
