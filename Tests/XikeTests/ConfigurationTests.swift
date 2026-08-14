import Foundation
import XCTest
@testable import Xike

final class ConfigurationTests: XCTestCase {
    @MainActor
    func testWorkspaceInterruptionTimingPreferenceDefaultsToContinuingAndPersists() {
        let suiteName = "PreferencesStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let freshStore = PreferencesStore(defaults: defaults)
        XCTAssertTrue(freshStore.continuesTimingDuringWorkspaceInterruption)

        freshStore.continuesTimingDuringWorkspaceInterruption = false
        let restoredStore = PreferencesStore(defaults: defaults)
        XCTAssertFalse(restoredStore.continuesTimingDuringWorkspaceInterruption)
    }

    func testDefaultsMatchProductContract() throws {
        let configuration = FocusConfiguration.default

        XCTAssertEqual(configuration.focusMinutes, 90)
        XCTAssertEqual(configuration.longBreakMinutes, 20)
        XCTAssertEqual(configuration.microBreakSeconds, 10)
        XCTAssertEqual(configuration.minimumPromptMinutes, 3)
        XCTAssertEqual(configuration.maximumPromptMinutes, 5)
        XCTAssertEqual(configuration.soundMode, .random)
        XCTAssertEqual(configuration.selectedSoundIDs, ["builtin:softBell"])
        XCTAssertEqual(configuration.volume, 0.7)
        XCTAssertNoThrow(try configuration.validate())
        XCTAssertTrue(configuration.isValid)
    }

    func testInclusiveBoundaryValuesAreValid() {
        let minimum = FocusConfiguration(
            focusMinutes: 15,
            longBreakMinutes: 1,
            microBreakSeconds: 5,
            minimumPromptMinutes: 1,
            maximumPromptMinutes: 14,
            volume: 0
        )
        let maximum = FocusConfiguration(
            focusMinutes: 240,
            longBreakMinutes: 60,
            microBreakSeconds: 60,
            minimumPromptMinutes: 30,
            maximumPromptMinutes: 30,
            volume: 1
        )

        XCTAssertNoThrow(try minimum.validate())
        XCTAssertNoThrow(try maximum.validate())
    }

    func testEveryNumericRangeRejectsValuesOutsideContract() {
        assertValidationError(
            FocusConfiguration(focusMinutes: 14),
            equals: .focusMinutesOutOfRange(14)
        )
        assertValidationError(
            FocusConfiguration(focusMinutes: 241),
            equals: .focusMinutesOutOfRange(241)
        )
        assertValidationError(
            FocusConfiguration(longBreakMinutes: 0),
            equals: .longBreakMinutesOutOfRange(0)
        )
        assertValidationError(
            FocusConfiguration(microBreakSeconds: 61),
            equals: .microBreakSecondsOutOfRange(61)
        )
        assertValidationError(
            FocusConfiguration(minimumPromptMinutes: 0),
            equals: .minimumPromptMinutesOutOfRange(0)
        )
        assertValidationError(
            FocusConfiguration(maximumPromptMinutes: 31),
            equals: .maximumPromptMinutesOutOfRange(31)
        )
        assertValidationError(
            FocusConfiguration(volume: -0.01),
            equals: .volumeOutOfRange(-0.01)
        )
        XCTAssertFalse(FocusConfiguration(volume: .nan).isValid)
    }

    func testPromptRangeMustBeOrderedAndShorterThanFocus() {
        assertValidationError(
            FocusConfiguration(minimumPromptMinutes: 6, maximumPromptMinutes: 5),
            equals: .promptRangeIsReversed(minimum: 6, maximum: 5)
        )
        assertValidationError(
            FocusConfiguration(focusMinutes: 15, minimumPromptMinutes: 1, maximumPromptMinutes: 15),
            equals: .promptIntervalNotShorterThanFocus(maximum: 15, focus: 15)
        )
    }

    func testDurationConversionsAndCodableRoundTrip() throws {
        let original = FocusConfiguration(
            focusMinutes: 45,
            longBreakMinutes: 8,
            microBreakSeconds: 15,
            minimumPromptMinutes: 2,
            maximumPromptMinutes: 7,
            soundMode: .fixed,
            selectedSoundIDs: ["system.Ping"],
            volume: 0.25
        )

        XCTAssertEqual(original.focusDuration, 2_700)
        XCTAssertEqual(original.longBreakDuration, 480)
        XCTAssertEqual(original.microBreakDuration, 15)
        XCTAssertEqual(original.promptIntervalRange, 120 ... 420)

        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(FocusConfiguration.self, from: data), original)
    }

    private func assertValidationError(
        _ configuration: FocusConfiguration,
        equals expected: FocusConfigurationError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try configuration.validate(), file: file, line: line) { error in
            XCTAssertEqual(error as? FocusConfigurationError, expected, file: file, line: line)
        }
        XCTAssertFalse(configuration.isValid, file: file, line: line)
    }
}
