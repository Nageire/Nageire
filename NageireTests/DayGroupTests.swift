import Foundation
import Testing
@testable import Nageire

@MainActor
struct DayGroupTests {
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tokyo
        return calendar
    }
    /// 2025-10-05 14:40 in Tokyo, the afternoon of the prototype's sample.
    private let now = Date(timeIntervalSince1970: 1_759_642_800)

    @Test func theSampleFallsIntoTodayYesterdayAndADatedDay() {
        let groups = SampleData.notes(asOf: now, calendar: calendar).groupedByDay(calendar: calendar)

        #expect(groups.map { $0.label(now: now, calendar: calendar) } == [.today, .yesterday, .day(Date(timeIntervalSince1970: 1_759_244_400))])
        #expect(groups.map { $0.notes.map(\.displayTitle) } == [
            ["来週の火曜は稽古と重なる。", "雨の前のあの灰色に近い。"],
            ["読みかけの本のメモ", "夕飯の買い物", "稽古の記録 — 投げ入れ"],
            ["引っ越しの見積もり", "庭の金木犀が咲いた"],
        ])
    }

    @Test func aDayEndsAtMidnightOfTheCalendarsTimeZone() {
        let justBefore = Date(timeIntervalSince1970: 1_759_590_000 - 60)
        let justAfter = Date(timeIntervalSince1970: 1_759_590_000)
        let notes = [justAfter, justBefore].map {
            let note = Note(body: "x", createdAt: $0, timeZone: tokyo, suffix: "0001")
            return NoteEntry(path: note.repositoryPath, contents: note.contents, isPending: false)
        }

        let groups = notes.groupedByDay(calendar: calendar)

        #expect(groups.count == 2)
        #expect(groups.map { $0.label(now: now, calendar: calendar) } == [.today, .yesterday])
    }

    @Test func aNoteWithoutATimeComesLastUnderNoDate() {
        let timed = SampleData.notes(asOf: now, calendar: calendar).last!
        let undated = NoteEntry(path: "notes/readme.md", contents: "A file the app did not write\n", isPending: false)

        let groups = [timed, undated].groupedByDay(calendar: calendar)

        #expect(groups.count == 2)
        #expect(groups.last?.label(now: now, calendar: calendar) == .undated)
    }
}
