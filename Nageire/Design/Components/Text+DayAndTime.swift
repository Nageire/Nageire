import SwiftUI

extension Text {
    /// 昨日 18:40 for a day close by, the date otherwise, so that a moment of today reads as such.
    init(dayAndTime date: Date) {
        switch DayGroup.Label(date) {
        case .today: self = Text("Today \(date, format: .dateTime.hour().minute())")
        case .yesterday: self = Text("Yesterday \(date, format: .dateTime.hour().minute())")
        case .day, .undated: self = Text(date, format: .dateTime.month().day().hour().minute())
        }
    }
}
