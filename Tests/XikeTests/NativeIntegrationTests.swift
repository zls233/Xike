import Carbon
import XCTest
@testable import Xike

final class NativeIntegrationTests: XCTestCase {
    func testGlobalShortcutMappingsUseExpectedSystemHotKeys() {
        XCTAssertEqual(GlobalShortcut.commandOptionReturn.keyCode, UInt32(kVK_Return))
        XCTAssertEqual(GlobalShortcut.commandOptionReturn.modifiers, UInt32(cmdKey | optionKey))
        XCTAssertEqual(GlobalShortcut.controlOptionSpace.keyCode, UInt32(kVK_Space))
        XCTAssertEqual(GlobalShortcut.controlOptionSpace.modifiers, UInt32(controlKey | optionKey))
        XCTAssertEqual(GlobalShortcut.commandShiftSpace.modifiers, UInt32(cmdKey | shiftKey))
    }

    func testFocusFilterPresetsCreateValidConfigurations() throws {
        let balanced = RhythmPreset.balanced.configuration
        let deepWork = RhythmPreset.deepWork.configuration
        let gentle = RhythmPreset.gentle.configuration

        XCTAssertEqual(balanced.focusMinutes, 90)
        XCTAssertEqual(deepWork.focusMinutes, 120)
        XCTAssertEqual(deepWork.longBreakMinutes, 25)
        XCTAssertEqual(gentle.focusMinutes, 45)
        XCTAssertEqual(gentle.longBreakMinutes, 10)
        try [balanced, deepWork, gentle].forEach { try $0.validate() }
    }

    func testInitialFocusDisplayNeverFlashesPastConfiguredDuration() {
        let configuration = FocusConfiguration.default
        let staleDisplayClockValue = configuration.focusDuration + 0.24

        let capped = AppStore.cappedRemainingTime(
            staleDisplayClockValue,
            phase: .focusing,
            configuration: configuration
        )

        XCTAssertEqual(TimeDisplay.clock(capped), "90:00")
    }

    func testBreakOverlayPositionsRespectVisibleFrameAndMargin() {
        let frame = CGRect(x: 100, y: 80, width: 1_200, height: 800)
        let size = CGSize(width: 400, height: 140)

        XCTAssertEqual(
            BreakOverlayPosition.center.origin(panelSize: size, in: frame),
            CGPoint(x: 500, y: 410)
        )
        XCTAssertEqual(
            BreakOverlayPosition.topTrailing.origin(panelSize: size, in: frame),
            CGPoint(x: 872, y: 712)
        )
        XCTAssertEqual(
            BreakOverlayPosition.bottomLeading.origin(panelSize: size, in: frame),
            CGPoint(x: 128, y: 108)
        )
    }
}
