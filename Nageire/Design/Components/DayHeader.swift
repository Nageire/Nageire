import SwiftUI

/// The heading of a day's section in the stream.
struct DayHeader: View {
    let label: DayGroup.Label

    var body: some View {
        text
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.ink2)
            .padding(.top, 20)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    private var text: Text {
        switch label {
        case .today: Text("Today")
        case .yesterday: Text("Yesterday")
        case .day(let day): Text(day, format: .dateTime.month().day().weekday(.wide))
        case .undated: Text("No date")
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 0) {
        DayHeader(label: .today)
        DayHeader(label: .yesterday)
        DayHeader(label: .day(.now.addingTimeInterval(-4 * 86_400)))
        DayHeader(label: .undated)
    }
    .padding(.horizontal, Spacing.gutter)
    .background(.paper)
}
