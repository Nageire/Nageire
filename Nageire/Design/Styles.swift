import SwiftUI

/// The one filled button of a screen.
struct PrimaryButtonStyle: ButtonStyle {
    var isCompact = false

    func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration, isCompact: isCompact)
            .foregroundStyle(.onAccent)
            .background(.tint.floating, in: .capsule)
            .modifier(Dimming(isPressed: configuration.isPressed))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var isCompact = false

    func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration, isCompact: isCompact)
            .foregroundStyle(.ink)
            .background(.paperRaised, in: .capsule)
            .hairlineBorder(.capsule)
            .modifier(Dimming(isPressed: configuration.isPressed))
    }
}

/// A button that is its label alone.
struct TextButtonStyle: ButtonStyle {
    var isCompact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(isCompact ? .subheadline.weight(.semibold) : .body.weight(.semibold))
            .padding(isCompact ? 8 : 12)
            .foregroundStyle(.accentText)
            .contentShape(.rect)
            .modifier(Dimming(isPressed: configuration.isPressed))
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static func primary(compact: Bool) -> PrimaryButtonStyle { PrimaryButtonStyle(isCompact: compact) }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
    static func secondary(compact: Bool) -> SecondaryButtonStyle { SecondaryButtonStyle(isCompact: compact) }
}

extension ButtonStyle where Self == TextButtonStyle {
    static var text: TextButtonStyle { TextButtonStyle() }
    static func text(compact: Bool) -> TextButtonStyle { TextButtonStyle(isCompact: compact) }
}

/// The label of a primary or secondary button at its size, before the fill.
private struct Pill: View {
    let configuration: ButtonStyleConfiguration
    let isCompact: Bool

    var body: some View {
        configuration.label
            .labelStyle(PillLabelStyle(isCompact: isCompact))
            .font(isCompact ? .subheadline.weight(.semibold) : .body.weight(.semibold))
            .padding(.horizontal, isCompact ? 14 : 20)
            // The least height, not the height: a label at an accessibility text size is taller.
            .padding(.vertical, isCompact ? 6 : 10)
            .frame(minHeight: isCompact ? Spacing.controlCompact : Spacing.control)
            .contentShape(.capsule)
    }
}

private struct PillLabelStyle: LabelStyle {
    let isCompact: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: isCompact ? 5 : 7) {
            configuration.icon
                // A glyph carries its own white space, so the side that holds one is padded less.
                .padding(.leading, isCompact ? -2 : -4)
            configuration.title
        }
    }
}

/// A glyph against its text, as a count sits against its paperclip. The default style sets them a word apart.
struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}

extension LabelStyle where Self == TightLabelStyle {
    static var tight: TightLabelStyle { TightLabelStyle() }
}

/// Dims a button, fill and label together, while it is pressed, and halves it while it is disabled.
private struct Dimming: ViewModifier {
    let isPressed: Bool

    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.opacity(!isEnabled ? 0.5 : isPressed ? 0.6 : 1)
    }
}

/// A rule one physical pixel thick, across the width it is given, or down the height when vertical.
struct Hairline: View {
    var axis = Axis.horizontal

    @Environment(\.pixelLength) private var pixelLength

    var body: some View {
        Rectangle()
            .fill(.hairline)
            .frame(width: axis == .vertical ? pixelLength : nil, height: axis == .horizontal ? pixelLength : nil)
    }
}

extension View {
    /// Draws a line one physical pixel thick just inside the shape.
    func hairlineBorder(_ shape: some InsettableShape) -> some View {
        modifier(HairlineBorder(shape: shape))
    }

}

extension ShapeStyle {
    /// The fill with the shadow of what floats over the screen: the primary button, the undo bar, a panel.
    /// The shadow belongs to the fill, so what is drawn on top of it does not redraw the shadow.
    var floating: some ShapeStyle { Floating(fill: self, ink: .ink) }
}

private struct HairlineBorder<S: InsettableShape>: ViewModifier {
    let shape: S

    @Environment(\.pixelLength) private var pixelLength

    func body(content: Content) -> some View {
        content.overlay { shape.strokeBorder(.hairline, lineWidth: pixelLength) }
    }
}

private struct Floating<Fill: ShapeStyle>: ShapeStyle {
    let fill: Fill
    /// Handed in because the color sets belong to the main actor and a style is resolved off it.
    let ink: Color

    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        // Ink would be a light shadow on dark paper, so the dark appearance uses black.
        let isDark = environment.colorScheme == .dark
        let color = isDark ? .black : ink
        return fill
            .shadow(.drop(color: color.opacity(isDark ? 0.45 : 0.14), radius: 12, y: 8))
            .shadow(.drop(color: color.opacity(isDark ? 0.3 : 0.06), radius: 1, y: 1))
    }
}

#Preview("Buttons") {
    VStack(spacing: 16) {
        Button { } label: { Text(verbatim: "GitHub でサインイン").frame(maxWidth: .infinity) }
            .buttonStyle(.primary)
        Button { } label: { Label { Text(verbatim: "GitHub を開く") } icon: { Image(systemName: "arrow.up.right.square") }.frame(maxWidth: .infinity) }
            .buttonStyle(.primary)
        Button { } label: { Label { Text(verbatim: "コードをコピー") } icon: { Image(systemName: "doc.on.doc") }.frame(maxWidth: .infinity) }
            .buttonStyle(.secondary)
        HStack(spacing: 16) {
            Button { } label: { Text(verbatim: "完了") }
                .buttonStyle(.primary(compact: true))
            Button { } label: { Text(verbatim: "完了") }
                .buttonStyle(.primary(compact: true))
                .disabled(true)
            Button { } label: { Text(verbatim: "取り消す") }
                .buttonStyle(.text)
        }
        Hairline()
    }
    .padding(Spacing.gutter)
    .frame(maxHeight: .infinity)
    .background(.paper)
}
