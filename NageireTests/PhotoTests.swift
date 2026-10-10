import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Nageire

struct PhotoTests {
    /// A camera's JPEG of one color: the pixels as stored, the orientation it was taken in, and where it was taken.
    private func cameraJPEG(width: Int, height: Int, orientation: Int = 1) throws -> Data {
        let source = try #require(CGImageSourceCreateWithData(pngData(width: width, height: height) as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: orientation,
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 35.3, kCGImagePropertyGPSLatitudeRef: "N"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:10:10 16:30:12"],
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    private func properties(of contents: Data) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithData(contents as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    @Test(arguments: [(PhotoSize.standard, 2048, 1536), (.large, 4096, 3072), (.original, 4800, 3600)])
    func aPhotoIsReducedToTheLongSideTheSettingGives(size photoSize: PhotoSize, width: Int, height: Int) async throws {
        let photo = try await Photo.jpeg(from: pngData(width: 4800, height: 3600), longSide: photoSize.longSide)

        _ = try properties(of: photo)
        let size = try pixelSize(of: photo)
        #expect(size.width == width)
        #expect(size.height == height)
    }

    @Test func aPhotoSmallerThanTheLongSideKeepsItsSize() async throws {
        let photo = try await Photo.jpeg(from: pngData(width: 640, height: 480), longSide: 2048)

        let size = try pixelSize(of: photo)
        #expect(size.width == 640)
        #expect(size.height == 480)
    }

    @Test func aPhotoTakenTurnedIsStoredTheRightWayUpWithoutTheTurn() async throws {
        // Orientation 6: the camera was held upright and stored the pixels on their side.
        let photo = try await Photo.jpeg(from: cameraJPEG(width: 300, height: 200, orientation: 6), longSide: 2048)

        let size = try pixelSize(of: photo)
        #expect(size.width == 200)
        #expect(size.height == 300)
        #expect((try properties(of: photo)[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
    }

    @Test func thePlaceAPhotoWasTakenIsTakenOutAndTheTimeStays() async throws {
        let photo = try await Photo.jpeg(from: cameraJPEG(width: 300, height: 200), longSide: 2048)

        let properties = try properties(of: photo)
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        let exif = try #require(properties[kCGImagePropertyExifDictionary] as? [CFString: Any])
        #expect(exif[kCGImagePropertyExifDateTimeOriginal] as? String == "2026:10:10 16:30:12")
    }

    @Test func aFileThatIsNotAnImageIsRefused() async {
        await #expect(throws: PhotoError.self) {
            try await Photo.jpeg(from: Data("not an image".utf8), longSide: 2048)
        }
    }

    @Test func aPhotoKeepsItsOwnNameAsAJPEGAndOneFromTheCameraIsNamedByTheTime() {
        let takenAt = Date(timeIntervalSince1970: 1_791_617_412)
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!

        #expect(Photo.fileName(for: "IMG_0421.HEIC", takenAt: takenAt, in: tokyo) == "IMG_0421.jpeg")
        #expect(Photo.fileName(for: nil, takenAt: takenAt, in: tokyo) == "IMG_20261010_163012.jpeg")
    }

    @Test func anImageIsReducedExceptAGIFOrAnSVGAndAFileWithoutANameIsTakenForAPhoto() {
        #expect(Photo.isReduced("IMG_0421.HEIC"))
        #expect(Photo.isReduced("screen.png"))
        #expect(Photo.isReduced(nil))
        #expect(!Photo.isReduced("loop.gif"))
        #expect(!Photo.isReduced("logo.svg"))
        #expect(!Photo.isReduced("scan.pdf"))
    }
}
