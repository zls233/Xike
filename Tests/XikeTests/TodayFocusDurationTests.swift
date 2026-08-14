import Foundation
import XCTest
@testable import Xike

@MainActor
final class TodayFocusDurationTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 14, hour: 9))!
    }

    func testRecordedDurationIncludesOnlyRecordsStartedToday() {
        let records = [
            record(startedAt: today, duration: 20 * 60),
            record(startedAt: today.addingTimeInterval(3_600), duration: 40 * 60),
            record(startedAt: today.addingTimeInterval(86_400), duration: 60 * 60)
        ]

        XCTAssertEqual(
            HistoryStore.activeFocusDuration(in: records, for: today, calendar: calendar),
            60 * 60
        )
    }

    func testLiveTotalAddsOnlyTodaySessionAndDoesNotDuplicateEndedSession() {
        XCTAssertEqual(
            AppStore.totalFocusDuration(
                recordedDuration: 40 * 60,
                sessionStartedAt: today,
                liveSessionDuration: 20 * 60,
                for: today,
                calendar: calendar
            ),
            60 * 60
        )
        XCTAssertEqual(
            AppStore.totalFocusDuration(
                recordedDuration: 60 * 60,
                sessionStartedAt: today,
                liveSessionDuration: 0,
                for: today,
                calendar: calendar
            ),
            60 * 60
        )
        XCTAssertEqual(
            AppStore.totalFocusDuration(
                recordedDuration: 40 * 60,
                sessionStartedAt: today.addingTimeInterval(-86_400),
                liveSessionDuration: 20 * 60,
                for: today,
                calendar: calendar
            ),
            40 * 60
        )
    }

    func testFocusDurationFormattingUsesQuietNaturalLanguage() {
        XCTAssertEqual(TimeDisplay.focusDuration(0), "0 分钟")
        XCTAssertEqual(TimeDisplay.focusDuration(59), "不足 1 分钟")
        XCTAssertEqual(TimeDisplay.focusDuration(60), "1 分钟")
        XCTAssertEqual(TimeDisplay.focusDuration(84 * 60), "1 小时 24 分")
        XCTAssertEqual(TimeDisplay.focusDuration(120 * 60), "2 小时")
    }

    private func record(startedAt: Date, duration: TimeInterval) -> SessionRecordValue {
        SessionRecordValue(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(duration),
            plannedFocusDuration: duration,
            activeFocusDuration: duration,
            outcome: .completed,
            microBreaksTriggered: 0,
            microBreaksCompleted: 0,
            microBreaksSkipped: 0,
            longBreakCompleted: false
        )
    }
}
