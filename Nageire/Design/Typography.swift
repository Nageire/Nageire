import SwiftUI

/// A heading inside a note, by the number of its `#` marks.
enum NoteHeading {
    case first, second, third

    /// The size at the default text size.
    var size: CGFloat {
        switch self {
        case .first: 24
        case .second: 20
        case .third: 17
        }
    }
}

extension View {
    /// The text of a note. The line is taller than the system's because Japanese set solid is hard to read past a few lines.
    func noteBodyStyle(serif: Bool = false) -> some View {
        font(.system(.body, design: serif ? .serif : .default))
            .lineHeight(.multiple(factor: 1.65))
    }

    func noteHeadingStyle(_ heading: NoteHeading) -> some View {
        modifier(ScaledFont(size: heading.size, weight: .semibold))
            .lineHeight(.multiple(factor: 1.35))
    }

    /// A title the on-device model proposed, in a list row: set apart from the person's own words.
    func derivedTitleStyle() -> some View {
        font(.body.weight(.semibold))
            .italic()
            .foregroundStyle(.textDerived)
    }

    /// A title the on-device model proposed, where the first heading of a note would be.
    func derivedHeadingStyle() -> some View {
        noteHeadingStyle(.first)
            .italic()
            .foregroundStyle(.textDerived)
    }

    /// The code of the device flow, spaced so that it can be read out and typed character by character.
    func deviceCodeStyle() -> some View {
        modifier(ScaledFont(size: 38, weight: .medium, design: .monospaced, tracking: 0.14))
    }
}

/// A font of a size the system has no text style for, which still follows Dynamic Type.
private struct ScaledFont: ViewModifier {
    // The size itself is scaled. A factor of 1 scaled and multiplied in would move in whole
    // pixels of 1, and the size would stay put across most of the text sizes.
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design
    /// As a fraction of the size.
    private let tracking: CGFloat

    init(size: CGFloat, weight: Font.Weight, design: Font.Design = .default, tracking: CGFloat = 0) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
        self.weight = weight
        self.design = design
        self.tracking = tracking
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: weight, design: design))
            .tracking(size * tracking)
    }
}

#Preview("Type") {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: "稽古の記録 — 投げ入れ").noteHeadingStyle(.first)
            Text(verbatim: "枝の向き").noteHeadingStyle(.second)
            Text(verbatim: "来週まで").noteHeadingStyle(.third)
            Text(verbatim: "今日は枝を二本だけ。器の口を見てから枝の向きを決めると、先生に言われた。").noteBodyStyle()
            Text(verbatim: "今日は枝を二本だけ。器の口を見てから枝の向きを決めると、先生に言われた。").noteBodyStyle(serif: true)
            Text(verbatim: "歯医者の予約を変える").derivedTitleStyle()
            Text(verbatim: "歯医者の予約を変える").derivedHeadingStyle()
            Text(verbatim: "WDJB-MJHT").deviceCodeStyle()
        }
        .foregroundStyle(.ink)
        .padding(Spacing.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(.paper)
}
