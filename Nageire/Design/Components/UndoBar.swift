import SwiftUI

/// Floats over the stream for ten seconds after a deletion, in place of a confirmation before it.
struct UndoBar: View {
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("Deleted")
                .font(.subheadline)
                .foregroundStyle(.ink)
            Spacer(minLength: 0)
            Button("Undo", action: undo)
                .buttonStyle(.text(compact: true))
        }
        .padding(.leading, 20)
        .padding(.trailing, 6)
        .frame(minHeight: 48)
        .background(.paperRaised.floating, in: .capsule)
    }
}

#Preview {
    UndoBar {}
        .padding(Spacing.gutter)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .background(.paper)
}
