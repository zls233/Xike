import Foundation
import XCTest
@testable import Xike

@MainActor
final class SessionEngineTests: XCTestCase {
    private let origin = Date(timeIntervalSinceReferenceDate: 1_000_000)

    func testStartUsesAbsoluteDeadlineAndInjectedRandomInterval() {
        var clock = origin
        var receivedRanges: [ClosedRange<TimeInterval>] = []
        var events: [SessionEvent] = []
        let engine = SessionEngine(
            now: { clock },
            randomInterval: {
                receivedRanges.append($0)
                return 240
            }
        )
        engine.onEvent = { events.append($0) }

        XCTAssertTrue(engine.start())
        XCTAssertEqual(engine.phase, .focusing)
        XCTAssertEqual(engine.startedAt, origin)
        XCTAssertEqual(engine.focusDeadline, origin.addingTimeInterval(5_400))
        XCTAssertEqual(engine.nextPromptAt, origin.addingTimeInterval(240))
        XCTAssertEqual(receivedRanges, [180 ... 300])
        XCTAssertEqual(events, [
            .sessionStarted(at: origin, focusDeadline: origin.addingTimeInterval(5_400))
        ])

        clock = origin.addingTimeInterval(12)
        XCTAssertEqual(engine.remainingTime, 5_388)
    }

    func testInvalidConfigurationCannotStartAndEmitsReason() {
        let invalid = FocusConfiguration(focusMinutes: 10)
        let engine = SessionEngine(configuration: invalid, now: { self.origin })
        var events: [SessionEvent] = []
        engine.onEvent = { events.append($0) }

        XCTAssertFalse(engine.start())
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertEqual(events, [.invalidConfiguration(.focusMinutesOutOfRange(10))])
    }

    func testMicroBreakIsIncludedWithinFocusDeadline() throws {
        var clock = origin
        let engine = SessionEngine(
            now: { clock },
            randomInterval: { _ in 180 }
        )
        XCTAssertTrue(engine.start())
        let originalFocusDeadline = try XCTUnwrap(engine.focusDeadline)

        clock = origin.addingTimeInterval(180)
        engine.tick()
        XCTAssertEqual(engine.phase, .microBreak)
        XCTAssertEqual(engine.phaseDeadline, origin.addingTimeInterval(190))
        XCTAssertEqual(engine.focusDeadline, originalFocusDeadline)
        XCTAssertEqual(engine.microBreaksTriggered, 1)

        clock = origin.addingTimeInterval(190)
        engine.tick()
        XCTAssertEqual(engine.phase, .focusing)
        XCTAssertEqual(engine.microBreaksCompleted, 1)
        XCTAssertEqual(engine.focusDeadline, originalFocusDeadline)
        XCTAssertEqual(engine.nextPromptAt, origin.addingTimeInterval(370))

        clock = originalFocusDeadline
        engine.tick()
        XCTAssertEqual(engine.phase, .longBreak)
        XCTAssertEqual(engine.phaseDeadline, origin.addingTimeInterval(6_600))
    }

    func testSkippingMicroBreakRecordsSkipAndReschedules() {
        let engine = SessionEngine(
            now: { self.origin },
            randomInterval: { _ in 60 }
        )
        var events: [SessionEvent] = []
        engine.onEvent = { events.append($0) }
        XCTAssertTrue(engine.start())
        XCTAssertTrue(engine.triggerMicroBreak(at: origin.addingTimeInterval(100)))
        XCTAssertTrue(engine.skipMicroBreak(at: origin.addingTimeInterval(102)))

        XCTAssertEqual(engine.phase, .focusing)
        XCTAssertEqual(engine.microBreaksTriggered, 1)
        XCTAssertEqual(engine.microBreaksSkipped, 1)
        XCTAssertEqual(engine.microBreaksCompleted, 0)
        XCTAssertEqual(engine.nextPromptAt, origin.addingTimeInterval(162))
        XCTAssertTrue(events.contains(.microBreakSkipped(at: origin.addingTimeInterval(102))))
    }

    func testNoPromptIsScheduledWhenAFullMicroBreakCannotFit() {
        let configuration = FocusConfiguration(
            focusMinutes: 15,
            longBreakMinutes: 1,
            microBreakSeconds: 60,
            minimumPromptMinutes: 1,
            maximumPromptMinutes: 1
        )
        let engine = SessionEngine(
            configuration: configuration,
            now: { self.origin },
            randomInterval: { _ in 60 }
        )
        XCTAssertTrue(engine.start())
        XCTAssertTrue(engine.triggerMicroBreak(at: origin.addingTimeInterval(60)))

        XCTAssertTrue(engine.completeMicroBreak(at: origin.addingTimeInterval(850)))
        XCTAssertNil(engine.nextPromptAt)
    }

    func testMicroBreakEndingExactlyAtFocusDeadlineIsCompleted() {
        let configuration = FocusConfiguration(
            focusMinutes: 15,
            longBreakMinutes: 1,
            microBreakSeconds: 60,
            minimumPromptMinutes: 14,
            maximumPromptMinutes: 14
        )
        let engine = SessionEngine(
            configuration: configuration,
            now: { self.origin },
            randomInterval: { _ in 840 }
        )
        XCTAssertTrue(engine.start())

        engine.tick(at: origin.addingTimeInterval(840))
        XCTAssertEqual(engine.phase, .microBreak)
        engine.tick(at: origin.addingTimeInterval(900))

        XCTAssertEqual(engine.phase, .longBreak)
        XCTAssertEqual(engine.microBreaksTriggered, 1)
        XCTAssertEqual(engine.microBreaksCompleted, 1)
        XCTAssertEqual(engine.phaseDeadline, origin.addingTimeInterval(960))
    }

    func testPauseFreezesAndResumeMovesEveryRelevantDeadline() {
        var clock = origin
        let engine = SessionEngine(
            now: { clock },
            randomInterval: { _ in 180 }
        )
        XCTAssertTrue(engine.start())

        clock = origin.addingTimeInterval(100)
        XCTAssertTrue(engine.pause(reason: .systemSleep))
        let frozenRemaining = engine.remainingTime

        clock = origin.addingTimeInterval(700)
        engine.tick()
        XCTAssertEqual(engine.phase, .focusing)
        XCTAssertEqual(engine.remainingTime, frozenRemaining)
        XCTAssertEqual(engine.remainingTime(at: clock), frozenRemaining)
        XCTAssertEqual(engine.pauseReason, .systemSleep)

        XCTAssertTrue(engine.resume())
        XCTAssertEqual(engine.focusDeadline, origin.addingTimeInterval(6_000))
        XCTAssertEqual(engine.nextPromptAt, origin.addingTimeInterval(780))
        XCTAssertEqual(engine.accumulatedPausedDuration, 600)
        XCTAssertFalse(engine.isPaused)
    }

    func testPauseDuringMicroBreakMovesBothFocusAndBreakDeadlines() {
        let engine = SessionEngine(now: { self.origin }, randomInterval: { _ in 60 })
        XCTAssertTrue(engine.start())
        XCTAssertTrue(engine.triggerMicroBreak(at: origin.addingTimeInterval(100)))
        XCTAssertTrue(engine.pause(at: origin.addingTimeInterval(104)))
        XCTAssertTrue(engine.resume(at: origin.addingTimeInterval(124)))

        XCTAssertEqual(engine.focusDeadline, origin.addingTimeInterval(5_420))
        XCTAssertEqual(engine.phaseDeadline, origin.addingTimeInterval(130))
    }

    func testPauseDuringLongBreakDoesNotChangeCompletedFocusDeadline() {
        let configuration = FocusConfiguration(
            focusMinutes: 15,
            longBreakMinutes: 5,
            minimumPromptMinutes: 1,
            maximumPromptMinutes: 1
        )
        let engine = SessionEngine(configuration: configuration, now: { self.origin })
        XCTAssertTrue(engine.start())
        engine.tick(at: origin.addingTimeInterval(900))
        XCTAssertEqual(engine.phase, .longBreak)

        XCTAssertTrue(engine.pause(at: origin.addingTimeInterval(910)))
        XCTAssertTrue(engine.resume(at: origin.addingTimeInterval(970)))

        XCTAssertEqual(engine.focusDeadline, origin.addingTimeInterval(900))
        XCTAssertEqual(engine.phaseDeadline, origin.addingTimeInterval(1_260))
    }

    func testDelayedTickCrossesFocusAndLongBreakWithoutDrift() {
        let configuration = FocusConfiguration(
            focusMinutes: 15,
            longBreakMinutes: 1,
            microBreakSeconds: 10,
            minimumPromptMinutes: 1,
            maximumPromptMinutes: 1
        )
        let engine = SessionEngine(
            configuration: configuration,
            now: { self.origin },
            randomInterval: { _ in 60 }
        )
        var events: [SessionEvent] = []
        engine.onEvent = { events.append($0) }
        XCTAssertTrue(engine.start())

        engine.tick(at: origin.addingTimeInterval(1_100))

        XCTAssertEqual(engine.phase, .awaitingNextCycle)
        XCTAssertEqual(engine.lastRecord?.outcome, .completed)
        XCTAssertEqual(engine.lastRecord?.activeFocusDuration, 900)
        XCTAssertEqual(engine.lastRecord?.endedAt, origin.addingTimeInterval(960))
        XCTAssertEqual(engine.lastRecord?.longBreakCompleted, true)
        XCTAssertTrue(events.contains(
            .longBreakStarted(
                at: origin.addingTimeInterval(900),
                deadline: origin.addingTimeInterval(960)
            )
        ))
        XCTAssertTrue(events.contains(.longBreakCompleted(at: origin.addingTimeInterval(960))))
    }

    func testEndingEarlyReturnsAbortedRecordWithPausedTimeRemoved() throws {
        let engine = SessionEngine(now: { self.origin }, randomInterval: { _ in 180 })
        XCTAssertTrue(engine.start())
        XCTAssertTrue(engine.pause(at: origin.addingTimeInterval(300)))

        let record = try XCTUnwrap(engine.end(at: origin.addingTimeInterval(900)))

        XCTAssertEqual(record.outcome, .aborted)
        XCTAssertEqual(record.activeFocusDuration, 300)
        XCTAssertEqual(record.plannedFocusDuration, 5_400)
        XCTAssertFalse(record.longBreakCompleted)
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertEqual(engine.lastRecord, record)
    }

    func testEndingDuringLongBreakPreservesCompletedFocusOutcome() throws {
        let configuration = FocusConfiguration(
            focusMinutes: 15,
            longBreakMinutes: 5,
            minimumPromptMinutes: 1,
            maximumPromptMinutes: 1
        )
        let engine = SessionEngine(configuration: configuration, now: { self.origin })
        XCTAssertTrue(engine.start())
        engine.tick(at: origin.addingTimeInterval(900))
        XCTAssertEqual(engine.phase, .longBreak)

        let record = try XCTUnwrap(engine.end(at: origin.addingTimeInterval(910)))
        XCTAssertEqual(record.outcome, .completed)
        XCTAssertEqual(record.activeFocusDuration, 900)
        XCTAssertFalse(record.longBreakCompleted)
    }

    func testSnapshotRoundTripRestoresPausedAndExcludesOfflineTime() throws {
        var firstClock = origin
        let original = SessionEngine(
            now: { firstClock },
            randomInterval: { _ in 180 }
        )
        XCTAssertTrue(original.start())
        firstClock = origin.addingTimeInterval(120)
        let snapshot = try XCTUnwrap(original.makeSnapshot())

        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: encoded)
        var restoredEvents: [SessionEvent] = []
        let restored = SessionEngine(now: { self.origin.addingTimeInterval(720) })
        restored.onEvent = { restoredEvents.append($0) }

        XCTAssertTrue(restored.restore(from: decoded, at: origin.addingTimeInterval(720)))
        XCTAssertTrue(restored.isPaused)
        XCTAssertEqual(restored.pauseReason, .sessionInactive)
        XCTAssertEqual(restored.pausedAt, origin.addingTimeInterval(120))
        XCTAssertEqual(restoredEvents, [.snapshotRestored(at: origin.addingTimeInterval(720))])

        XCTAssertTrue(restored.resume(at: origin.addingTimeInterval(720)))
        XCTAssertEqual(restored.focusDeadline, origin.addingTimeInterval(6_000))
        XCTAssertEqual(restored.nextPromptAt, origin.addingTimeInterval(780))
        XCTAssertEqual(restored.accumulatedPausedDuration, 600)
    }

    func testRestoringAnAlreadyPausedSnapshotKeepsOriginalPauseStart() throws {
        let original = SessionEngine(now: { self.origin }, randomInterval: { _ in 180 })
        XCTAssertTrue(original.start())
        XCTAssertTrue(original.pause(reason: .manual, at: origin.addingTimeInterval(100)))
        let snapshot = try XCTUnwrap(original.makeSnapshot(at: origin.addingTimeInterval(200)))

        let restored = SessionEngine(now: { self.origin.addingTimeInterval(500) })
        XCTAssertTrue(restored.restore(from: snapshot))
        XCTAssertEqual(restored.pauseReason, .manual)
        XCTAssertEqual(restored.pausedAt, origin.addingTimeInterval(100))
        XCTAssertTrue(restored.resume(at: origin.addingTimeInterval(500)))
        XCTAssertEqual(restored.accumulatedPausedDuration, 400)
        XCTAssertEqual(restored.focusDeadline, origin.addingTimeInterval(5_800))
    }

    func testRestoreRejectsUnsupportedOrInconsistentSnapshots() throws {
        let source = SessionEngine(now: { self.origin })
        XCTAssertTrue(source.start())
        var snapshot = try XCTUnwrap(source.makeSnapshot())
        snapshot.version += 1

        let destination = SessionEngine(now: { self.origin })
        XCTAssertFalse(destination.restore(from: snapshot))
        XCTAssertEqual(destination.phase, .idle)

        snapshot.version = SessionSnapshot.currentVersion
        snapshot.phase = .microBreak
        snapshot.phaseDeadline = nil
        XCTAssertFalse(destination.restore(from: snapshot))
    }

    func testInjectedRandomValueIsClampedToConfiguredRange() {
        let lowerClamped = SessionEngine(
            now: { self.origin },
            randomInterval: { _ in -1_000 }
        )
        XCTAssertTrue(lowerClamped.start())
        XCTAssertEqual(lowerClamped.nextPromptAt, origin.addingTimeInterval(180))

        let upperClamped = SessionEngine(
            now: { self.origin },
            randomInterval: { _ in 10_000 }
        )
        XCTAssertTrue(upperClamped.start())
        XCTAssertEqual(upperClamped.nextPromptAt, origin.addingTimeInterval(300))
    }

    func testInvalidTransitionsAreSafeNoOps() {
        let engine = SessionEngine(now: { self.origin })

        XCTAssertFalse(engine.pause())
        XCTAssertFalse(engine.resume())
        XCTAssertFalse(engine.triggerMicroBreak())
        XCTAssertFalse(engine.completeMicroBreak())
        XCTAssertNil(engine.end())
        XCTAssertNil(engine.makeSnapshot())

        XCTAssertTrue(engine.start())
        XCTAssertFalse(engine.start())
        XCTAssertFalse(engine.resume())
    }
}
