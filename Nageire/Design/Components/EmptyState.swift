import SwiftUI

/// The stream before the first note.
struct EmptyState: View {
    var body: some View {
        ContentUnavailableView {
            VaseOutline()
                .stroke(.ink2, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                .frame(width: 60, height: 104)
                .accessibilityHidden(true)
                .padding(.bottom, 20)
            Text("Nothing here yet")
                .font(.title2.weight(.bold))
                .foregroundStyle(.ink)
        } description: {
            Text("Toss in whatever comes to mind, as it is.\nArranging it can wait.")
                .font(.subheadline)
                .foregroundStyle(.ink2)
                .frame(maxWidth: 280)
        }
    }
}

/// A tall vase, as a line: the lip, the neck, and the body.
nonisolated struct VaseOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: w * 0.3, y: 0))
        path.addLine(to: CGPoint(x: w * 0.7, y: 0))
        path.addLine(to: CGPoint(x: w * 0.7, y: h * 0.08))
        path.addLine(to: CGPoint(x: w * 0.62, y: h * 0.08))
        path.addLine(to: CGPoint(x: w * 0.62, y: h * 0.3))
        path.addCurve(to: CGPoint(x: w, y: h * 0.62), control1: CGPoint(x: w * 0.62, y: h * 0.42), control2: CGPoint(x: w, y: h * 0.46))
        path.addCurve(to: CGPoint(x: w * 0.5, y: h), control1: CGPoint(x: w, y: h * 0.86), control2: CGPoint(x: w * 0.78, y: h))
        path.addCurve(to: CGPoint(x: 0, y: h * 0.62), control1: CGPoint(x: w * 0.22, y: h), control2: CGPoint(x: 0, y: h * 0.86))
        path.addCurve(to: CGPoint(x: w * 0.38, y: h * 0.3), control1: CGPoint(x: 0, y: h * 0.46), control2: CGPoint(x: w * 0.38, y: h * 0.42))
        path.addLine(to: CGPoint(x: w * 0.38, y: h * 0.08))
        path.addLine(to: CGPoint(x: w * 0.3, y: h * 0.08))
        path.closeSubpath()
        return path
    }
}

#Preview {
    EmptyState()
        .background(.paper)
}
