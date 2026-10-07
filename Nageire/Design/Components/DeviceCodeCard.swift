import SwiftUI

/// The code GitHub asks for, on a card of its own so that it can be read across the room and selected.
struct DeviceCodeCard: View {
    let code: String

    var body: some View {
        Text(verbatim: code)
            .deviceCodeStyle()
            .foregroundStyle(.ink)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .padding(.horizontal, 20)
            .background(.surfaceCard, in: .rect(cornerRadius: Radius.card))
            .hairlineBorder(.rect(cornerRadius: Radius.card))
    }
}

#Preview {
    DeviceCodeCard(code: SampleData.deviceCode.userCode)
        .padding(Spacing.gutter)
        .background(.paper)
}
