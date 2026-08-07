import Foundation

public enum SoundSelectionMode: String, Codable, CaseIterable, Sendable {
    case fixed
    case random
}

public enum FocusConfigurationError: Error, Equatable, LocalizedError, Sendable {
    case focusMinutesOutOfRange(Int)
    case longBreakMinutesOutOfRange(Int)
    case microBreakSecondsOutOfRange(Int)
    case minimumPromptMinutesOutOfRange(Int)
    case maximumPromptMinutesOutOfRange(Int)
    case promptRangeIsReversed(minimum: Int, maximum: Int)
    case promptIntervalNotShorterThanFocus(maximum: Int, focus: Int)
    case volumeOutOfRange(Double)

    public var errorDescription: String? {
        switch self {
        case .focusMinutesOutOfRange:
            "专注时长必须在 15 到 240 分钟之间。"
        case .longBreakMinutesOutOfRange:
            "长休息必须在 1 到 60 分钟之间。"
        case .microBreakSecondsOutOfRange:
            "微休息必须在 5 到 60 秒之间。"
        case .minimumPromptMinutesOutOfRange, .maximumPromptMinutesOutOfRange:
            "随机提示间隔必须在 1 到 30 分钟之间。"
        case .promptRangeIsReversed:
            "随机提示的最小间隔不能大于最大间隔。"
        case .promptIntervalNotShorterThanFocus:
            "随机提示的最大间隔必须短于专注时长。"
        case .volumeOutOfRange:
            "音量必须在 0 到 1 之间。"
        }
    }
}

/// User-editable settings for one focus cycle.
///
/// Values are intentionally stored in the units shown by the UI. Call
/// ``validate()`` before starting a session; `SessionEngine.start()` performs
/// the same validation defensively.
public struct FocusConfiguration: Codable, Equatable, Sendable {
    public static let focusMinutesRange = 15 ... 240
    public static let longBreakMinutesRange = 1 ... 60
    public static let microBreakSecondsRange = 5 ... 60
    public static let promptMinutesRange = 1 ... 30
    public static let defaultSoundID = "builtin:softBell"

    public var focusMinutes: Int
    public var longBreakMinutes: Int
    public var microBreakSeconds: Int
    public var minimumPromptMinutes: Int
    public var maximumPromptMinutes: Int
    public var soundMode: SoundSelectionMode
    public var selectedSoundIDs: [String]
    public var volume: Double

    public init(
        focusMinutes: Int = 90,
        longBreakMinutes: Int = 20,
        microBreakSeconds: Int = 10,
        minimumPromptMinutes: Int = 3,
        maximumPromptMinutes: Int = 5,
        soundMode: SoundSelectionMode = .random,
        selectedSoundIDs: [String] = [FocusConfiguration.defaultSoundID],
        volume: Double = 0.7
    ) {
        self.focusMinutes = focusMinutes
        self.longBreakMinutes = longBreakMinutes
        self.microBreakSeconds = microBreakSeconds
        self.minimumPromptMinutes = minimumPromptMinutes
        self.maximumPromptMinutes = maximumPromptMinutes
        self.soundMode = soundMode
        self.selectedSoundIDs = selectedSoundIDs
        self.volume = volume
    }

    public static let `default` = FocusConfiguration()

    public var focusDuration: TimeInterval {
        TimeInterval(focusMinutes) * 60
    }

    public var longBreakDuration: TimeInterval {
        TimeInterval(longBreakMinutes) * 60
    }

    public var microBreakDuration: TimeInterval {
        TimeInterval(microBreakSeconds)
    }

    public var promptIntervalRange: ClosedRange<TimeInterval> {
        (TimeInterval(minimumPromptMinutes) * 60) ... (TimeInterval(maximumPromptMinutes) * 60)
    }

    public var isValid: Bool {
        (try? validate()) != nil
    }

    public func validate() throws {
        guard Self.focusMinutesRange.contains(focusMinutes) else {
            throw FocusConfigurationError.focusMinutesOutOfRange(focusMinutes)
        }
        guard Self.longBreakMinutesRange.contains(longBreakMinutes) else {
            throw FocusConfigurationError.longBreakMinutesOutOfRange(longBreakMinutes)
        }
        guard Self.microBreakSecondsRange.contains(microBreakSeconds) else {
            throw FocusConfigurationError.microBreakSecondsOutOfRange(microBreakSeconds)
        }
        guard Self.promptMinutesRange.contains(minimumPromptMinutes) else {
            throw FocusConfigurationError.minimumPromptMinutesOutOfRange(minimumPromptMinutes)
        }
        guard Self.promptMinutesRange.contains(maximumPromptMinutes) else {
            throw FocusConfigurationError.maximumPromptMinutesOutOfRange(maximumPromptMinutes)
        }
        guard minimumPromptMinutes <= maximumPromptMinutes else {
            throw FocusConfigurationError.promptRangeIsReversed(
                minimum: minimumPromptMinutes,
                maximum: maximumPromptMinutes
            )
        }
        guard maximumPromptMinutes < focusMinutes else {
            throw FocusConfigurationError.promptIntervalNotShorterThanFocus(
                maximum: maximumPromptMinutes,
                focus: focusMinutes
            )
        }
        guard volume.isFinite, (0.0 ... 1.0).contains(volume) else {
            throw FocusConfigurationError.volumeOutOfRange(volume)
        }
    }
}
