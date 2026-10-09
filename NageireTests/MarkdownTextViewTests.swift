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
    private func makeView(text: String, caret: Int) -> (view: NoteTextView, coordinator: MarkdownTextCoordinator, received: ReceivedText) {
        let received = ReceivedText(text)
        let coordinator = MarkdownTextCoordinator(text: Binding { received.text } set: { received.text = $0 })
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
}
