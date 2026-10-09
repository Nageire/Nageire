import SwiftUI

/// The text of a note in a TextKit 2 text view, with its Markdown styled in place.
///
/// The view's string is the note's text as the file holds it; what a mark means is shown through
/// attributes on the paragraph that is laid out, never by changing the characters.
struct MarkdownTextView {
    @Binding var text: String
    var serif = false
    /// Changes each time the cursor should go to the view: when it appears, and again on request.
    var focusRequest = 0
    /// What the Format menu holds to reach the view; the view's coordinator goes into it.
    var requests: EditorRequests?
    /// Whether the view has the keyboard, for the Format menu to be offered only then.
    var isFocused: Binding<Bool> = .constant(false)
    /// The note column on macOS centers its text at the reading width; the toss column keeps the gutter.
    var isNoteColumn = false
    /// Laid out above the text inside the view, so that it scrolls with the text.
    var header: AnyView?
    /// The file an image line links to, for its thumbnail. Nil while the device does not have the file.
    var attachment: (String) -> Data? = { _ in nil }

    func makeCoordinator() -> MarkdownTextCoordinator {
        MarkdownTextCoordinator(text: $text)
    }
}

/// The delegate of the text view on both platforms: it styles each paragraph as it is laid out, draws the
/// decorations, carries out the commands, and reports the selection and the focus.
final class MarkdownTextCoordinator: NSObject, NSTextContentStorageDelegate, NSTextLayoutManagerDelegate {
    var text: Binding<String>
    var isFocused: Binding<Bool> = .constant(false)
    var serif = false
    var focusRequest = 0
    /// Set with the view, since the fonts follow its text size.
    var styler: MarkdownStyler?
    /// Set with the view: a fragment keeps the palette it was laid out with.
    var palette = DecorationPalette(accent: .ink)
    /// The screen's, for the thumbnails and the one device pixel a thumbnail's frame is drawn with.
    var scale: CGFloat = 1 {
        didSet { thumbnails.scale = scale }
    }
    var pixelLength: CGFloat { 1 / scale }
    /// The thumbnails decoded so far, and the files they are made from; a line whose thumbnail arrives is styled again to show it.
    let thumbnails = ThumbnailCache()
    /// Where the caret is, for the paragraph being laid out to know whether it holds it.
    weak var view: NoteTextView?
    /// The start of the paragraph that held the caret when the selection last moved, to restyle when it leaves.
    private var lastCaretParagraphStart: Int?
    /// Whether the view has the keyboard. Without it there is no caret, and no line shows its raw marks.
    private var hasFocus = false

    init(text: Binding<String>) {
        self.text = text
        super.init()
        thumbnails.onDecode = { [weak self] link in self?.restyleImageLines(linking: link) }
    }

    func textContentStorage(_ textContentStorage: NSTextContentStorage, textParagraphWith range: NSRange) -> NSTextParagraph? {
        guard let styler, let storage = textContentStorage.textStorage else { return nil }
        let paragraph = (storage.string as NSString).substring(with: range)
        // The paragraphs an edit touched are asked for before the selection follows it, and a stale caret is still on the paragraph being edited.
        let holdsCaret = hasFocus && range.location == caretParagraphStart(in: storage)
        return NSTextParagraph(attributedString: styler.styled(paragraph, isFirst: range.location == 0, holdsCaret: holdsCaret))
    }

    /// Restyles the paragraph the caret left and the one it entered, if it moved to another.
    func selectionDidChange() {
        guard let storage = view?.contentStorage?.textStorage, caretParagraphStart(in: storage) != lastCaretParagraphStart else { return }
        restyleCaretParagraph()
    }

    /// Restyles the paragraph that held the caret and the one that holds it now.
    private func restyleCaretParagraph() {
        guard let storage = view?.contentStorage?.textStorage else { return }
        let start = caretParagraphStart(in: storage)
        let left = lastCaretParagraphStart
        lastCaretParagraphStart = start
        for location in [left, start].compactMap({ $0 }) {
            restyle(paragraph(at: location, in: storage), in: storage)
        }
    }

    /// Has the content storage ask for the paragraph anew, which styles it again.
    private func restyle(_ range: NSRange, in storage: NSTextStorage) {
        // The content storage keeps the paragraphs it made and hands them out again when the layout alone is
        // invalidated; only an edit of the storage makes it ask for one anew, and an edit of the attributes that
        // changes none is enough. Each paragraph is a session of its own: within one session the storage unites
        // the ranges, and every paragraph between two would be asked for; an edit outside a session reaches the
        // screen only with the next event after a click.
        storage.beginEditing()
        storage.edited(.editedAttributes, range: range, changeInLength: 0)
        storage.endEditing()
    }

    /// Styles the image lines that link the file again, now that their thumbnail is decoded.
    private func restyleImageLines(linking link: String) {
        guard let storage = view?.contentStorage?.textStorage else { return }
        let string = storage.string as NSString
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: .byParagraphs) { paragraph, _, range, _ in
            guard let paragraph, paragraph.hasPrefix("!["), case let .image(_, linked) = MarkdownLine(paragraph).kind, linked == link else { return }
            self.restyle(range, in: storage)
        }
    }

    private func caretParagraphStart(in storage: NSTextStorage) -> Int {
        paragraph(at: view?.selection.location ?? 0, in: storage).location
    }

    /// The view took or gave up the keyboard, and with it the caret, whose line shows its raw marks.
    /// It can do so inside a SwiftUI update, where state is not written.
    func focusDidChange(to isFocused: Bool) {
        hasFocus = isFocused
        restyleCaretParagraph()
        Task { @MainActor in
            self.isFocused.wrappedValue = isFocused
        }
    }

    /// Carries out what the accessory bar or the Format menu asks, at the selection.
    func perform(_ command: EditorCommand) {
        guard let view, let storage = view.contentStorage?.textStorage,
              let edit = MarkdownEditing.edit(for: command, in: storage.string, selection: view.selection) else { return }
        view.apply(edit)
    }

    /// The next marker, or the end of the list, when Return is pressed in a list; false where Return is a line break.
    func handleReturn(at selection: NSRange) -> Bool {
        guard let view, let storage = view.contentStorage?.textStorage,
              let edit = MarkdownEditing.returnEdit(in: storage.string, selection: selection) else { return false }
        view.apply(edit)
        return true
    }

    /// The box of a task under a point in the text container's coordinates, with the margin around it.
    func box(at point: CGPoint) -> (range: NSRange, done: Bool)? {
        guard let view, let layoutManager = view.textLayoutManager, let contentStorage = view.contentStorage,
              let fragment = layoutManager.textLayoutFragment(for: point) as? CheckboxLayoutFragment,
              let elementStart = fragment.textElement?.elementRange?.location,
              fragment.boxRect.offsetBy(dx: fragment.layoutFragmentFrame.minX, dy: fragment.layoutFragmentFrame.minY)
                  .insetBy(dx: -EditorMetrics.checkboxHitMargin, dy: -EditorMetrics.checkboxHitMargin).contains(point)
        else { return nil }
        let start = contentStorage.offset(from: contentStorage.documentRange.location, to: elementStart)
        return (NSRange(location: start + fragment.box.location, length: fragment.box.length), fragment.done)
    }

    /// Toggles the box under a point, an edit like any other, and says whether there was one.
    @discardableResult
    func toggleBox(at point: CGPoint) -> Bool {
        guard let view, let box = box(at: point) else { return false }
        view.apply(TextEdit(range: box.range, replacement: box.done ? "[ ]" : "[x]", selection: view.selection))
        return true
    }

    /// The paragraph around a location, which an edit since may have moved past the end.
    private func paragraph(at location: Int, in storage: NSTextStorage) -> NSRange {
        (storage.string as NSString).paragraphRange(for: NSRange(location: min(location, storage.length), length: 0))
    }

    func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation, in textElement: NSTextElement) -> NSTextLayoutFragment {
        guard let styler, let paragraph = textElement as? NSTextParagraph, paragraph.attributedString.length > 0,
              let decoration = paragraph.attributedString.attribute(.lineDecoration, at: 0, effectiveRange: nil) as? LineDecoration
        else {
            return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
        }
        switch decoration {
        case let .checkbox(done, box):
            return CheckboxLayoutFragment(textElement: textElement, done: done, box: box, capHeight: styler.fonts.body.capHeight, palette: palette)
        case let .thumbnail(file, link):
            return ThumbnailLayoutFragment(textElement: textElement, file: file, thumbnail: thumbnails.thumbnail(for: link), font: styler.fonts.caption, palette: palette, hairline: pixelLength)
        }
    }

    /// Takes the fonts into use: for typing, and for every paragraph laid out from now on.
    func apply(_ fonts: EditorFonts, to view: NoteTextView) {
        let styler = MarkdownStyler(fonts: fonts)
        self.styler = styler
        // The view's own font and color are what it gives new text and, on iOS, the typing attributes after the caret moves.
        view.font = fonts.body
        view.textColor = .ink
        view.typingAttributes = styler.base
        // Setting the attributes is an edit, and an edit makes the content storage ask for its paragraphs again.
        guard let storage = view.contentStorage?.textStorage else { return }
        storage.setAttributes(styler.base, range: NSRange(location: 0, length: storage.length))
    }
}

#if canImport(UIKit)
extension MarkdownTextView: UIViewRepresentable {
    func makeUIView(context: Context) -> NoteTextView {
        let view = NoteTextView(usingTextLayoutManager: true)
        let coordinator = context.coordinator
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: Spacing.rowPadding, left: Spacing.gutter, bottom: Spacing.rowPadding, right: Spacing.gutter)
        view.textContainer.lineFragmentPadding = 0
        view.alwaysBounceVertical = true
        view.keyboardDismissMode = .interactive
        view.delegate = coordinator
        view.textLayoutManager?.delegate = coordinator
        view.contentStorage?.delegate = coordinator
        coordinator.view = view
        coordinator.isFocused = isFocused
        requests?.editor = coordinator
        coordinator.serif = serif
        coordinator.thumbnails.attachment = attachment
        coordinator.palette = DecorationPalette(accent: view.tintColor)
        coordinator.scale = view.traitCollection.displayScale
        coordinator.apply(EditorFonts(serif: serif, traits: view.traitCollection), to: view)
        view.text = text
        coordinator.selectionDidChange()
        view.onTextSizeChange = { [weak coordinator] view in
            coordinator?.apply(EditorFonts(serif: coordinator?.serif ?? false, traits: view.traitCollection), to: view)
        }
        // The design's bar, 44 on paper-raised with a hairline, is the view's own accessory: the keyboard
        // toolbar of SwiftUI draws its own bar around what is put in it.
        let bar = UIHostingController(rootView: AccessoryBar(
            perform: { [weak coordinator] in coordinator?.perform($0) },
            hideKeyboard: { [weak view] in view?.resignFirstResponder() }
        ))
        bar.sizingOptions = .intrinsicContentSize
        bar.view.backgroundColor = .clear
        // The keyboard takes an accessory's height from its frame, which a hosted view leaves at zero.
        bar.view.frame.size.height = Spacing.control
        bar.view.autoresizingMask = .flexibleWidth
        view.inputAccessoryView = bar.view
        view.accessoryBar = bar
        if let header {
            let controller = UIHostingController(rootView: header)
            controller.view.backgroundColor = .clear
            view.addSubview(controller.view)
            view.header = controller
        }
        return view
    }

    func updateUIView(_ view: NoteTextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.text = $text
        coordinator.isFocused = isFocused
        coordinator.thumbnails.attachment = attachment
        if let header {
            view.header?.rootView = header
            view.headerNeedsLayout = true
        }
        if view.text != text {
            view.text = text
        }
        if coordinator.serif != serif {
            coordinator.serif = serif
            coordinator.apply(EditorFonts(serif: serif, traits: view.traitCollection), to: view)
        }
        if coordinator.focusRequest != focusRequest {
            coordinator.focusRequest = focusRequest
            view.focus()
        }
    }
}

extension MarkdownTextCoordinator: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        text.wrappedValue = textView.text
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        selectionDidChange()
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        focusDidChange(to: true)
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        focusDidChange(to: false)
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
        // While kana are being composed, Return settles them; the view handles that.
        guard replacement == "\n", textView.markedTextRange == nil else { return true }
        return !handleReturn(at: range)
    }
}

final class NoteTextView: UITextView {
    var onTextSizeChange: ((NoteTextView) -> Void)?
    /// The controller of the accessory bar, which its view does not keep alive.
    var accessoryBar: UIViewController?
    /// The note's header, a subview above the text that scrolls with it; the text starts under it.
    var header: UIHostingController<AnyView>?
    /// Set when the header's content or the width changed; the header is measured again at the next layout.
    var headerNeedsLayout = true
    /// One name over both platforms' selection, for the coordinator.
    var selection: NSRange { selectedRange }
    /// A request that came before the view was in a window, where it could not take the cursor.
    private var wantsFocus = false
    private lazy var boxTap = UITapGestureRecognizer(target: self, action: #selector(tapBox))

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: Self, _) in
            view.onTextSizeChange?(view)
        }
        addGestureRecognizer(boxTap)
    }

    private var coordinator: MarkdownTextCoordinator? { delegate as? MarkdownTextCoordinator }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let header else { return }
        let width = bounds.width - 2 * Spacing.gutter
        if headerNeedsLayout || header.view.frame.width != width {
            headerNeedsLayout = false
            let height = header.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
            header.view.frame = CGRect(x: Spacing.gutter, y: Spacing.rowPadding, width: width, height: height)
            // Set only when it changes: the inset invalidates the whole layout.
            if textContainerInset.top != Spacing.rowPadding + height {
                textContainerInset.top = Spacing.rowPadding + height
            }
        }
    }

    /// A tap on a box is the box's, not the text's: it toggles the task and neither moves the caret nor raises
    /// the keyboard. A drag that starts on a box still scrolls.
    override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        let overBox = coordinator?.box(at: containerPoint(recognizer.location(in: self))) != nil
        if recognizer === boxTap {
            return overBox
        }
        let isTextTouch = recognizer is UITapGestureRecognizer || recognizer is UILongPressGestureRecognizer
        return !(overBox && isTextTouch) && super.gestureRecognizerShouldBegin(recognizer)
    }

    @objc private func tapBox(_ recognizer: UITapGestureRecognizer) {
        coordinator?.toggleBox(at: containerPoint(recognizer.location(in: self)))
    }

    private func containerPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - textContainerInset.left, y: point.y - textContainerInset.top)
    }

    required init?(coder: NSCoder) {
        fatalError("The view is made in code, never decoded.")
    }

    var contentStorage: NSTextContentStorage? {
        textLayoutManager?.textContentManager as? NSTextContentStorage
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, wantsFocus {
            wantsFocus = false
            becomeFirstResponder()
        }
    }

    func focus() {
        if window != nil {
            becomeFirstResponder()
        } else {
            wantsFocus = true
        }
    }

    /// Replaces through the text input system, which registers the undo and tells the delegate.
    func apply(_ edit: TextEdit) {
        guard let start = position(from: beginningOfDocument, offset: edit.range.location),
              let end = position(from: start, offset: edit.range.length),
              let range = textRange(from: start, to: end) else { return }
        replace(range, withText: edit.replacement)
        selectedRange = edit.selection
    }
}
#else
extension MarkdownTextView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSScrollView {
        let view = NoteTextView(usingTextLayoutManager: true)
        let coordinator = context.coordinator
        view.isRichText = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.textContainerInset = NSSize(width: Spacing.gutter, height: Spacing.rowPadding)
        view.textContainer?.lineFragmentPadding = 0
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = .width
        view.textContainer?.widthTracksTextView = true
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.delegate = coordinator
        view.textLayoutManager?.delegate = coordinator
        view.contentStorage?.delegate = coordinator
        view.isNoteColumn = isNoteColumn
        if let header {
            let controller = NSHostingController(rootView: header)
            view.addSubview(controller.view)
            view.header = controller
        }
        coordinator.view = view
        coordinator.isFocused = isFocused
        requests?.editor = coordinator
        coordinator.serif = serif
        coordinator.thumbnails.attachment = attachment
        coordinator.palette = DecorationPalette(accent: .controlAccentColor)
        // The view has no window yet; the main screen's scale is the one it will almost always get.
        coordinator.scale = NSScreen.main?.backingScaleFactor ?? 2
        coordinator.apply(EditorFonts(serif: serif), to: view)
        view.string = text
        coordinator.selectionDidChange()
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = view
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let view = scrollView.documentView as? NoteTextView else { return }
        let coordinator = context.coordinator
        coordinator.text = $text
        coordinator.isFocused = isFocused
        coordinator.thumbnails.attachment = attachment
        if let header {
            view.header?.rootView = header
            view.headerNeedsLayout = true
            view.needsLayout = true
        }
        if view.string != text {
            view.string = text
        }
        if coordinator.serif != serif {
            coordinator.serif = serif
            coordinator.apply(EditorFonts(serif: serif), to: view)
        }
        if coordinator.focusRequest != focusRequest {
            coordinator.focusRequest = focusRequest
            view.focus()
        }
    }
}

extension MarkdownTextCoordinator: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard let view = notification.object as? NSTextView else { return }
        text.wrappedValue = view.string
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        selectionDidChange()
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        // While kana are being composed, Return settles them; the view handles that.
        guard selector == #selector(NSResponder.insertNewline(_:)), !textView.hasMarkedText() else { return false }
        return handleReturn(at: textView.selectedRange())
    }
}

final class NoteTextView: NSTextView {
    /// A request that came before the view was in a window, where it could not take the cursor.
    private var wantsFocus = false
    /// The note's header, a subview above the text that scrolls with it; the text starts under it.
    var header: NSHostingController<AnyView>?
    /// Set when the header's content changed; the header is measured again at the next layout.
    var headerNeedsLayout = true
    /// The note column centers its text at the reading width under the column's top; the toss column keeps the gutter.
    var isNoteColumn = false
    /// One name over both platforms' selection, for the coordinator.
    var selection: NSRange { selectedRange() }

    var contentStorage: NSTextContentStorage? {
        textContentStorage
    }

    private var coordinator: MarkdownTextCoordinator? { delegate as? MarkdownTextCoordinator }

    override func layout() {
        let side = isNoteColumn ? max(Spacing.columnSide, (bounds.width - Spacing.readingWidth) / 2) : Spacing.gutter
        let top = isNoteColumn ? Spacing.columnTop : Spacing.rowPadding
        let width = bounds.width - 2 * side
        if let header, headerNeedsLayout || header.view.frame.width != width {
            headerNeedsLayout = false
            let height = header.sizeThatFits(in: NSSize(width: width, height: .greatestFiniteMagnitude)).height
            header.view.frame = NSRect(x: side, y: top, width: width, height: height)
        }
        // The inset is the same above and below; the text ends with the room the header takes above it.
        let inset = NSSize(width: side, height: top + (header?.view.frame.height ?? 0))
        if textContainerInset != inset {
            textContainerInset = inset
        }
        super.layout()
    }

    /// A click on a box is the box's, not the text's: it toggles the task and does not move the caret.
    /// The second click of a double click is nobody's, so that it does not toggle the task back.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let origin = textContainerOrigin
        let container = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        if event.clickCount > 1, coordinator?.box(at: container) != nil {
            return
        }
        if coordinator?.toggleBox(at: container) == true {
            return
        }
        super.mouseDown(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, wantsFocus {
            wantsFocus = false
            window?.makeFirstResponder(self)
        }
    }

    // The text delegate hears of editing beginning with the first change, not with the keyboard.
    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            coordinator?.focusDidChange(to: true)
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            coordinator?.focusDidChange(to: false)
        }
        return resigned
    }

    func focus() {
        if let window {
            window.makeFirstResponder(self)
        } else {
            wantsFocus = true
        }
    }

    /// Replaces as the input system does, which registers the undo and tells the delegate.
    func apply(_ edit: TextEdit) {
        insertText(edit.replacement, replacementRange: edit.range)
        setSelectedRange(edit.selection)
    }
}
#endif
