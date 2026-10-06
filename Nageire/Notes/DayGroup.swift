import Foundation

/// The notes written on one day, for a section of the stream.
struct DayGroup: Identifiable {
    /// The start of the day. Nil for notes whose time is not known, which come last.
    let day: Date?
    /// Newest first.
    fileprivate(set) var notes: [NoteEntry]

    var id: Date? { day }

    enum Label: Equatable {
        case today
        case yesterday
        case day(Date)
        /// Notes whose time is not known.
        case undated
    }

    /// What the section is called: 今日, 昨日, or the day itself.
    func label(now: Date = .now, calendar: Calendar = .current) -> Label {
        guard let day else { return .undated }
        if calendar.isDate(day, inSameDayAs: now) { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
            return .yesterday
        }
        return .day(day)
    }
}

extension [NoteEntry] {
    /// The notes by day, in the order they come: a day is a run of notes, so the list is sorted newest first, as the library gives it.
    func groupedByDay(calendar: Calendar = .current) -> [DayGroup] {
        var groups: [DayGroup] = []
        for note in self {
            let day = note.createdAt.map(calendar.startOfDay(for:))
            if let last = groups.indices.last, groups[last].day == day {
                groups[last].notes.append(note)
            } else {
                groups.append(DayGroup(day: day, notes: [note]))
            }
        }
        return groups
    }
}
