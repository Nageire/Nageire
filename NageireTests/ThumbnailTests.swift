import CoreGraphics
import Foundation
import Testing
@testable import Nageire

struct ThumbnailTests {
    private let frame = CGSize(width: 164, height: 123)

    @Test func aLandscapeImageIsReducedToTheFrameAndAPortraitOneToTheFrameWidthWithHeightToSpare() {
        let landscape = Thumbnail(contents: pngData(width: 800, height: 600), filling: frame, scale: 1)
        let portrait = Thumbnail(contents: pngData(width: 600, height: 800), filling: frame, scale: 2)

        #expect(landscape.image?.width == 164)
        #expect(landscape.image?.height == 123)
        // The shorter side follows the longer one's reduction, rounded as ImageIO rounds it.
        #expect([328, 329].contains(portrait.image?.width))
        #expect(portrait.image?.height == 438)
    }

    @Test func aSmallImageIsNotEnlarged() {
        let thumbnail = Thumbnail(contents: pngData(width: 100, height: 80), filling: frame, scale: 3)

        #expect(thumbnail.image?.width == 100)
        #expect(thumbnail.image?.height == 80)
    }

    @Test func aFileThatIsNotAnImageHasNoImageAndItsSizeReadsAsTheCaptionShowsIt() {
        let thumbnail = Thumbnail(contents: Data(count: 1_234_567), filling: frame, scale: 2)

        #expect(thumbnail.image == nil)
        #expect(thumbnail.size == 1_234_567.formatted(.byteCount(style: .file)))
    }
}
