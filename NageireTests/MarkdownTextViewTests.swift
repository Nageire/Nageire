import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import Nageire

/// What the binding of the editor received last.
@MainActor
private final class ReceivedText {
    var text: String

    init(_ text: String) {
        self.text = text
    }
}

@MainActor
struct MarkdownTextViewTests {
    /// A text view with its coordinator as its delegate, the caret where asked, and what its binding received.
    private func makeView(text: String, caret: Int, attachment: @escaping (String) -> Data? = { _ in nil }) -> (view: NoteTextView, coordinator: MarkdownTextCoordinator, received: ReceivedText) {
        let received = ReceivedText(text)
        let coordinator = MarkdownTextCoordinator(text: Binding { received.text } set: { received.text = $0 })
        // Before the text, as the view does: the first layout of an image line is what starts its decode.
        coordinator.thumbnails.attachment = attachment
        let view = NoteTextView(usingTextLayoutManager: true)
        view.delegate = coordinator
        view.textLayoutManager?.delegate = coordinator
        view.contentStorage?.delegate = coordinator
        coordinator.view = view
        #if canImport(UIKit)
        coordinator.apply(EditorFonts(serif: false, traits: view.traitCollection), to: view)
        view.text = text
        view.selectedRange = NSRange(location: caret, length: 0)
        #else
        coordinator.apply(EditorFonts(serif: false), to: view)
        view.string = text
        view.setSelectedRange(NSRange(location: caret, length: 0))
        #endif
        return (view, coordinator, received)
    }

    #if canImport(UIKit)
    @Test func returnInAListGoesThroughTheDelegateToTheBindingAndUndo() {
        let (view, coordinator, received) = makeView(text: "- a", caret: 3)

        let handled = !coordinator.textView(view, shouldChangeTextIn: NSRange(location: 3, length: 0), replacementText: "\n")

        #expect(handled)
        #expect(view.text == "- a\n- ")
        #expect(received.text == "- a\n- ")
        #expect(view.undoManager?.canUndo == true)
    }

    @Test func returnOutsideAListIsLeftToTheView() {
        let (view, coordinator, received) = makeView(text: "a", caret: 1)

        #expect(coordinator.textView(view, shouldChangeTextIn: NSRange(location: 1, length: 0), replacementText: "\n"))
        #expect(received.text == "a")
    }
    #else
    @Test func returnInAListGoesThroughTheDelegateToTheBinding() {
        let (view, coordinator, received) = makeView(text: "- a", caret: 3)

        let handled = coordinator.textView(view, doCommandBy: #selector(NSResponder.insertNewline(_:)))

        #expect(handled)
        #expect(view.string == "- a\n- ")
        #expect(received.text == "- a\n- ")
    }

    @Test func returnOutsideAListIsLeftToTheView() {
        let (view, coordinator, received) = makeView(text: "a", caret: 1)

        #expect(!coordinator.textView(view, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(received.text == "a")
    }
    #endif

    @Test func aTapOnTheBoxOfATaskTogglesItAndATapBesideItDoesNot() throws {
        let (view, coordinator, received) = makeView(text: "- [ ] a", caret: 7)
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
        let layoutManager = try #require(view.textLayoutManager)
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        let fragment = try #require(layoutManager.textLayoutFragment(for: .zero) as? CheckboxLayoutFragment)
        let box = fragment.boxRect.offsetBy(dx: fragment.layoutFragmentFrame.minX, dy: fragment.layoutFragmentFrame.minY)

        #expect(!coordinator.toggleBox(at: CGPoint(x: box.maxX + 40, y: box.midY)))
        #expect(received.text == "- [ ] a")
        #expect(coordinator.toggleBox(at: CGPoint(x: box.midX, y: box.midY)))
        #expect(received.text == "- [x] a")
        #expect(view.selection == NSRange(location: 7, length: 0))
    }

    @Test func aCommandEditsTheViewAndReachesTheBinding() {
        let (view, coordinator, received) = makeView(text: "- a", caret: 3)

        coordinator.perform(.bold)

        #expect(received.text == "- a****")
        #expect(view.selection == NSRange(location: 5, length: 0))
    }

    @Test func anImageLineIsItsFrameUntilTheFileIsDecodedAndThenShowsTheImage() async throws {
        let png = pngData(width: 400, height: 300)
        let (view, coordinator, _) = makeView(text: "![a.png](f/a.png)", caret: 0) { link in link == "f/a.png" ? png : nil }
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 400)
        let layoutManager = try #require(view.textLayoutManager)
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        let before = try #require(layoutManager.textLayoutFragment(for: .zero) as? ThumbnailLayoutFragment)

        #expect(before.image == nil)

        await withCheckedContinuation { continuation in
            let restyle = coordinator.thumbnails.onDecode
            coordinator.thumbnails.onDecode = {
                restyle($0)
                continuation.resume()
            }
        }
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        let after = try #require(layoutManager.textLayoutFragment(for: .zero) as? ThumbnailLayoutFragment)

        #expect(after.image != nil)
    }

    @Test func aTapOnAThumbnailOrOnALineThatLinksAFileGivesItsLinkAndATapElsewhereNone() throws {
        let (view, coordinator, _) = makeView(text: "![a.png](f/a.png)\n[scan.pdf](f/scan.pdf)\ntext", caret: 0)
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 600)
        let layoutManager = try #require(view.textLayoutManager)
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        let image = try #require(layoutManager.textLayoutFragment(for: .zero) as? ThumbnailLayoutFragment)
        let thumbnail = image.thumbnailRect.offsetBy(dx: image.layoutFragmentFrame.minX, dy: image.layoutFragmentFrame.minY)
        let fileLine = CGPoint(x: 10, y: image.layoutFragmentFrame.maxY + 5)

        #expect(coordinator.thumbnailLink(at: CGPoint(x: thumbnail.midX, y: thumbnail.midY)) == "f/a.png")
        #expect(coordinator.thumbnailLink(at: CGPoint(x: thumbnail.maxX + 40, y: thumbnail.midY)) == nil)
        #expect(coordinator.fileLink(at: fileLine) == "f/scan.pdf")
        #expect(coordinator.fileLink(at: CGPoint(x: 10, y: image.layoutFragmentFrame.maxY + 60)) == nil)
    }

    /// The file the editor has for a link, which a test makes available after the first layout.
    private final class Files {
        var files: [String: Data] = [:]
    }

    @Test func aFileThatArrivesAfterItsLineWasLaidOutIsShownOnceTheEditorIsToldOfArrivals() async throws {
        let files = Files()
        let (view, coordinator, _) = makeView(text: "![a.png](f/a.png)", caret: 0) { files.files[$0] }
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 400)
        let layoutManager = try #require(view.textLayoutManager)
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        files.files["f/a.png"] = pngData(width: 400, height: 300)

        coordinator.noteArrivals(1)
        // Polled rather than awaited on the decode: without the arrival the line is never asked for again, and a wait would not end.
        var image: CGImage?
        for _ in 0..<200 where image == nil {
            layoutManager.ensureLayout(for: layoutManager.documentRange)
            image = (layoutManager.textLayoutFragment(for: .zero) as? ThumbnailLayoutFragment)?.image
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(image != nil)
    }

    @Test func aLineThatLinksAFileOpensOnlyWhereTheTapIsNotTheCaretsAndAThumbnailAlways() throws {
        let (view, coordinator, _) = makeView(text: "![a.png](f/a.png)\n[scan.pdf](f/scan.pdf)", caret: 0)
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 600)
        let layoutManager = try #require(view.textLayoutManager)
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        let image = try #require(layoutManager.textLayoutFragment(for: .zero) as? ThumbnailLayoutFragment)
        let thumbnail = image.thumbnailRect.offsetBy(dx: image.layoutFragmentFrame.minX, dy: image.layoutFragmentFrame.minY)
        let fileLine = CGPoint(x: 10, y: image.layoutFragmentFrame.maxY + 5)

        #expect(coordinator.decorationTap(at: fileLine, opensFileLink: false) == nil)
        #expect(coordinator.decorationTap(at: fileLine, opensFileLink: true) != nil)
        #expect(coordinator.decorationTap(at: CGPoint(x: thumbnail.midX, y: thumbnail.midY), opensFileLink: false) != nil)
    }
}
