import Foundation

public enum SessionPhase: String, Codable, CaseIterable, Sendable {
    case idle
    case focusing
    case microBreak
    case longBreak
    case awaitingNextCycle

    public var isRunning: Bool {
        switch self {
        case .focusing, .microBreak, .longBreak:
            true
        case .idle, .awaitingNextCycle:
            false
        }
    }
}

public enum PauseReason: String, Codable, CaseIterable, Sendable {
    case manual
    case systemSleep
    case sessionInactive
}

public enum SessionOutcome: String, Codable, Sendable {
    /// The configured focus interval reached its deadline. Long-break
    /// completion is recorded independently.
    case completed
    case aborted
}

public struct SessionRecordValue: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date
    public var plannedFocusDuration: TimeInterval
    public var activeFocusDuration: TimeInterval
    public var outcome: SessionOutcome
    public var microBreaksTriggered: Int
    public var microBreaksCompleted: Int
    public var microBreaksSkipped: Int
    public var longBreakCompleted: Bool

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date,
        plannedFocusDuration: TimeInterval,
        activeFocusDuration: TimeInterval,
        outcome: SessionOutcome,
        microBreaksTriggered: Int,
        microBreaksCompleted: Int,
        microBreaksSkipped: Int,
        longBreakCompleted: Bool
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.plannedFocusDuration = plannedFocusDuration
        self.activeFocusDuration = activeFocusDuration
        self.outcome = outcome
        self.microBreaksTriggered = microBreaksTriggered
        self.microBreaksCompleted = microBreaksCompleted
        self.microBreaksSkipped = microBreaksSkipped
        self.longBreakCompleted = longBreakCompleted
    }
}

/// Versioned, JSON-friendly representation of a running cycle.
public struct SessionSnapshot: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var capturedAt: Date
    public var configuration: FocusConfiguration
    public var phase: SessionPhase
    public var isPaused: Bool
    public var pauseReason: PauseReason?
    public var startedAt: Date
    public var focusDeadline: Date
    public var phaseDeadline: Date?
    public var nextPromptAt: Date?
    public var pausedAt: Date?
    public var accumulatedPausedDuration: TimeInterval
    public var focusCompletedAt: Date?
    public var microBreaksTriggered: Int
    public var microBreaksCompleted: Int
    public var microBreaksSkipped: Int

    public init(
        version: Int = SessionSnapshot.currentVersion,
        capturedAt: Date,
        configuration: FocusConfiguration,
        phase: SessionPhase,
        isPaused: Bool,
        pauseReason: PauseReason?,
        startedAt: Date,
        focusDeadline: Date,
        phaseDeadline: Date?,
        nextPromptAt: Date?,
        pausedAt: Date?,
        accumulatedPausedDuration: TimeInterval,
        focusCompletedAt: Date?,
        microBreaksTriggered: Int,
        microBreaksCompleted: Int,
        microBreaksSkipped: Int
    ) {
        self.version = version
        self.capturedAt = capturedAt
        self.configuration = configuration
        self.phase = phase
        self.isPaused = isPaused
        self.pauseReason = pauseReason
        self.startedAt = startedAt
        self.focusDeadline = focusDeadline
        self.phaseDeadline = phaseDeadline
        self.nextPromptAt = nextPromptAt
        self.pausedAt = pausedAt
        self.accumulatedPausedDuration = accumulatedPausedDuration
        self.focusCompletedAt = focusCompletedAt
        self.microBreaksTriggered = microBreaksTriggered
        self.microBreaksCompleted = microBreaksCompleted
        self.microBreaksSkipped = microBreaksSkipped
    }
}

public enum SessionEvent: Equatable, Sendable {
    case sessionStarted(at: Date, focusDeadline: Date)
    case sessionPaused(reason: PauseReason, at: Date)
    case sessionResumed(at: Date, pausedDuration: TimeInterval)
    case microBreakStarted(at: Date, deadline: Date)
    case microBreakCompleted(at: Date)
    case microBreakSkipped(at: Date)
    case longBreakStarted(at: Date, deadline: Date)
    case longBreakCompleted(at: Date)
    case sessionEnded(SessionRecordValue)
    case snapshotRestored(at: Date)
    case invalidConfiguration(FocusConfigurationError)
}
