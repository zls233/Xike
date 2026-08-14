import Foundation
import Observation

@MainActor
@Observable
public final class SessionEngine {
    public typealias NowProvider = @MainActor () -> Date
    public typealias RandomIntervalProvider = @MainActor (ClosedRange<TimeInterval>) -> TimeInterval

    public var configuration: FocusConfiguration
    public private(set) var phase: SessionPhase = .idle
    public private(set) var isPaused = false
    public private(set) var pauseReason: PauseReason?
    public private(set) var startedAt: Date?
    public private(set) var focusDeadline: Date?
    public private(set) var phaseDeadline: Date?
    public private(set) var microBreakIntroDeadline: Date?
    public private(set) var nextPromptAt: Date?
    public private(set) var pausedAt: Date?
    public private(set) var accumulatedPausedDuration: TimeInterval = 0
    public private(set) var focusCompletedAt: Date?
    public private(set) var microBreaksTriggered = 0
    public private(set) var microBreaksCompleted = 0
    public private(set) var microBreaksSkipped = 0
    public private(set) var lastRecord: SessionRecordValue?
    public private(set) var focusContext: FocusContext?

    /// The host uses this single callback to bridge state transitions to sound,
    /// notifications, persistence, and the micro-break panel.
    @ObservationIgnored
    public var onEvent: (@MainActor (SessionEvent) -> Void)?

    @ObservationIgnored
    private let nowProvider: NowProvider
    @ObservationIgnored
    private let randomIntervalProvider: RandomIntervalProvider

    public init(
        configuration: FocusConfiguration = .default,
        now: @escaping NowProvider = { Date() },
        randomInterval: @escaping RandomIntervalProvider = { Double.random(in: $0) }
    ) {
        self.configuration = configuration
        self.nowProvider = now
        self.randomIntervalProvider = randomInterval
    }

    public var canStart: Bool {
        phase == .idle || phase == .awaitingNextCycle
    }

    public var canPause: Bool {
        phase.isRunning && !isPaused
    }

    public var canResume: Bool {
        phase.isRunning && isPaused
    }

    public var canEnd: Bool {
        phase.isRunning
    }

    /// Remaining time for the phase currently presented to the user.
    public var remainingTime: TimeInterval {
        remainingTime(at: nowProvider())
    }

    public func isMicroBreakIntro(at date: Date? = nil) -> Bool {
        guard phase == .microBreak, let microBreakIntroDeadline else { return false }
        let reference = isPaused ? pausedAt ?? date ?? nowProvider() : date ?? nowProvider()
        return reference < microBreakIntroDeadline
    }

    /// Countdown-only time: it stays at the configured duration while the
    /// 1.5-second introductory message is visible.
    public func microBreakCountdownRemaining(at date: Date? = nil) -> TimeInterval {
        guard phase == .microBreak, let phaseDeadline else { return 0 }
        let requestedDate = date ?? nowProvider()
        let reference = isPaused ? pausedAt ?? requestedDate : requestedDate
        let countdownStart = microBreakIntroDeadline ?? phaseDeadline.addingTimeInterval(-configuration.microBreakDuration)
        return max(0, phaseDeadline.timeIntervalSince(max(reference, countdownStart)))
    }

    /// Remaining time until the end of the focus interval. Micro-break time is
    /// included because its deadline never replaces or extends this deadline.
    public var focusRemainingTime: TimeInterval {
        guard let focusDeadline else { return 0 }
        let reference = isPaused ? pausedAt ?? nowProvider() : nowProvider()
        return max(0, focusDeadline.timeIntervalSince(reference))
    }

    /// Active focus time for the running cycle at a given instant. The focus
    /// interval includes its scheduled micro-breaks, matching the duration
    /// stored in ``SessionRecordValue``. Pauses and the long-break interval do
    /// not add time.
    public func activeFocusDuration(at date: Date? = nil) -> TimeInterval {
        guard phase.isRunning, let startedAt else { return 0 }

        if phase == .longBreak || focusCompletedAt != nil {
            return configuration.focusDuration
        }

        let requestedDate = date ?? nowProvider()
        let reference = isPaused ? pausedAt ?? requestedDate : requestedDate
        return min(
            configuration.focusDuration,
            max(0, reference.timeIntervalSince(startedAt) - accumulatedPausedDuration)
        )
    }

    public func remainingTime(at date: Date) -> TimeInterval {
        let referenceDate = isPaused ? pausedAt ?? date : date
        let deadline: Date?
        switch phase {
        case .focusing:
            deadline = focusDeadline
        case .microBreak, .longBreak:
            deadline = phaseDeadline
        case .idle, .awaitingNextCycle:
            deadline = nil
        }
        return max(0, deadline?.timeIntervalSince(referenceDate) ?? 0)
    }

    @discardableResult
    public func start(context: FocusContext? = nil, at date: Date? = nil) -> Bool {
        guard canStart else { return false }

        do {
            try configuration.validate()
        } catch let error as FocusConfigurationError {
            emit(.invalidConfiguration(error))
            return false
        } catch {
            return false
        }

        let startDate = date ?? nowProvider()
        resetRuntimeState()
        focusContext = context?.isEmpty == false ? context : nil
        phase = .focusing
        startedAt = startDate
        focusDeadline = startDate.addingTimeInterval(configuration.focusDuration)
        scheduleNextPrompt(from: startDate)
        emit(.sessionStarted(at: startDate, focusDeadline: focusDeadline!))
        return true
    }

    @discardableResult
    public func pause(reason: PauseReason = .manual, at date: Date? = nil) -> Bool {
        guard canPause else { return false }
        let pauseDate = date ?? nowProvider()
        // Honor an already-reached absolute deadline before freezing state.
        // This prevents a late sleep/lock notification from extending a phase.
        tick(at: pauseDate)
        guard canPause else { return false }
        isPaused = true
        pauseReason = reason
        pausedAt = pauseDate
        emit(.sessionPaused(reason: reason, at: pauseDate))
        return true
    }

    @discardableResult
    public func resume(at date: Date? = nil) -> Bool {
        guard canResume, let pausedAt else { return false }
        let resumeDate = date ?? nowProvider()
        let pausedDuration = max(0, resumeDate.timeIntervalSince(pausedAt))

        if phase == .focusing || phase == .microBreak {
            focusDeadline = focusDeadline?.addingTimeInterval(pausedDuration)
        }
        phaseDeadline = phaseDeadline?.addingTimeInterval(pausedDuration)
        microBreakIntroDeadline = microBreakIntroDeadline?.addingTimeInterval(pausedDuration)
        nextPromptAt = nextPromptAt?.addingTimeInterval(pausedDuration)
        accumulatedPausedDuration += pausedDuration
        self.pausedAt = nil
        pauseReason = nil
        isPaused = false
        emit(.sessionResumed(at: resumeDate, pausedDuration: pausedDuration))
        return true
    }

    /// Advances state from absolute deadlines. A delayed UI timer never adds
    /// time to the focus interval or long break.
    public func tick(at date: Date? = nil) {
        guard phase.isRunning, !isPaused else { return }
        let currentDate = date ?? nowProvider()

        // A single delayed tick may legitimately cross focus and long-break
        // deadlines, so allow the state machine to catch up without recursion.
        for _ in 0 ..< 4 {
            switch phase {
            case .focusing:
                guard let focusDeadline else { return }
                if currentDate >= focusDeadline {
                    beginLongBreak(at: focusDeadline)
                    continue
                }
                if let nextPromptAt, currentDate >= nextPromptAt {
                    // The sound is heard now, so a delayed prompt only starts if
                    // a complete micro-break still fits before focus ends.
                    guard currentDate.addingTimeInterval(configuration.microBreakPresentationDuration) <= focusDeadline else {
                        self.nextPromptAt = nil
                        return
                    }
                    beginMicroBreak(at: currentDate)
                }
                return

            case .microBreak:
                guard let focusDeadline else { return }
                if let phaseDeadline,
                   phaseDeadline <= focusDeadline,
                   currentDate >= phaseDeadline
                {
                    // Count a break that completed exactly at the focus
                    // boundary before moving into the long break.
                    completeMicroBreak(skipped: false, at: phaseDeadline)
                    continue
                }
                if currentDate >= focusDeadline {
                    beginLongBreak(at: focusDeadline)
                    continue
                }
                return

            case .longBreak:
                guard let phaseDeadline, currentDate >= phaseDeadline else { return }
                completeLongBreak(at: phaseDeadline)
                return

            case .idle, .awaitingNextCycle:
                return
            }
        }
    }

    /// Starts a micro-break immediately, primarily for UI preview/manual test
    /// controls. Normal sessions reach this transition through ``tick(at:)``.
    @discardableResult
    public func triggerMicroBreak(at date: Date? = nil) -> Bool {
        guard phase == .focusing, !isPaused, let focusDeadline else { return false }
        let triggerDate = date ?? nowProvider()
        guard triggerDate < focusDeadline,
              triggerDate.addingTimeInterval(configuration.microBreakPresentationDuration) <= focusDeadline
        else {
            nextPromptAt = nil
            return false
        }
        beginMicroBreak(at: triggerDate)
        return true
    }

    @discardableResult
    public func completeMicroBreak(skipped: Bool = false, at date: Date? = nil) -> Bool {
        guard phase == .microBreak, !isPaused, let focusDeadline else { return false }
        let completionDate = date ?? nowProvider()
        guard completionDate <= focusDeadline else {
            tick(at: completionDate)
            return false
        }

        let event: SessionEvent
        if skipped {
            microBreaksSkipped += 1
            event = .microBreakSkipped(at: completionDate)
        } else {
            microBreaksCompleted += 1
            event = .microBreakCompleted(at: completionDate)
        }

        phase = .focusing
        phaseDeadline = nil
        microBreakIntroDeadline = nil
        scheduleNextPrompt(from: completionDate)
        emit(event)
        if completionDate == focusDeadline {
            beginLongBreak(at: focusDeadline)
        }
        return true
    }

    @discardableResult
    public func skipMicroBreak(at date: Date? = nil) -> Bool {
        completeMicroBreak(skipped: true, at: date)
    }

    /// Finishes a completed focus cycle without waiting for the optional long
    /// break. The cycle remains in its explicit waiting state and never starts
    /// another focus interval automatically.
    @discardableResult
    public func skipLongBreak(at date: Date? = nil) -> Bool {
        // Focus has already completed, so ending its optional recovery phase is
        // valid even if the user paused during that phase.
        guard phase == .longBreak else { return false }
        completeLongBreak(at: date ?? nowProvider(), skipped: true)
        return true
    }

    /// Ends a running cycle and returns the immutable value that should be
    /// inserted into SwiftData by the persistence layer.
    @discardableResult
    public func end(at date: Date? = nil) -> SessionRecordValue? {
        guard phase.isRunning, let startedAt else { return nil }
        let endDate = date ?? nowProvider()
        let focusWasCompleted = focusCompletedAt != nil || phase == .longBreak
        let record = makeRecord(
            startedAt: startedAt,
            endedAt: endDate,
            outcome: focusWasCompleted ? .completed : .aborted,
            longBreakCompleted: false
        )
        lastRecord = record
        phase = .idle
        clearActiveState()
        emit(.sessionEnded(record))
        return record
    }

    public func makeSnapshot(at date: Date? = nil) -> SessionSnapshot? {
        guard phase.isRunning,
              let startedAt,
              let focusDeadline
        else {
            return nil
        }

        return SessionSnapshot(
            capturedAt: date ?? nowProvider(),
            configuration: configuration,
            phase: phase,
            isPaused: isPaused,
            pauseReason: pauseReason,
            startedAt: startedAt,
            focusDeadline: focusDeadline,
            phaseDeadline: phaseDeadline,
            microBreakIntroDeadline: microBreakIntroDeadline,
            nextPromptAt: nextPromptAt,
            pausedAt: pausedAt,
            accumulatedPausedDuration: accumulatedPausedDuration,
            focusCompletedAt: focusCompletedAt,
            microBreaksTriggered: microBreaksTriggered,
            microBreaksCompleted: microBreaksCompleted,
            microBreaksSkipped: microBreaksSkipped,
            focusContext: focusContext
        )
    }

    /// Restores a running snapshot into a paused state. If the App terminated
    /// while running, the pause starts at `capturedAt`; consequently the entire
    /// offline interval is removed when the user explicitly resumes.
    @discardableResult
    public func restore(from snapshot: SessionSnapshot, at date: Date? = nil) -> Bool {
        guard canStart,
              snapshot.version == SessionSnapshot.currentVersion,
              snapshot.phase.isRunning,
              snapshot.configuration.isValid,
              snapshot.focusDeadline >= snapshot.startedAt,
              snapshot.accumulatedPausedDuration >= 0,
              snapshot.microBreaksTriggered >= 0,
              snapshot.microBreaksCompleted >= 0,
              snapshot.microBreaksSkipped >= 0,
              snapshot.microBreaksCompleted + snapshot.microBreaksSkipped <= snapshot.microBreaksTriggered,
              snapshotIsConsistent(snapshot)
        else {
            return false
        }

        let restoreDate = date ?? nowProvider()
        configuration = snapshot.configuration
        phase = snapshot.phase
        startedAt = snapshot.startedAt
        focusDeadline = snapshot.focusDeadline
        phaseDeadline = snapshot.phaseDeadline
        microBreakIntroDeadline = snapshot.microBreakIntroDeadline
        nextPromptAt = snapshot.nextPromptAt
        accumulatedPausedDuration = snapshot.accumulatedPausedDuration
        focusCompletedAt = snapshot.focusCompletedAt
        microBreaksTriggered = snapshot.microBreaksTriggered
        microBreaksCompleted = snapshot.microBreaksCompleted
        microBreaksSkipped = snapshot.microBreaksSkipped
        focusContext = snapshot.focusContext
        lastRecord = nil

        isPaused = true
        pauseReason = snapshot.isPaused ? snapshot.pauseReason ?? .sessionInactive : .sessionInactive
        pausedAt = snapshot.isPaused ? snapshot.pausedAt ?? snapshot.capturedAt : snapshot.capturedAt
        emit(.snapshotRestored(at: restoreDate))
        return true
    }

    /// Clears the completed waiting state without generating a record.
    public func resetToIdle() {
        guard phase == .awaitingNextCycle else { return }
        phase = .idle
        clearActiveState()
    }

    public func updateFocusContext(_ context: FocusContext?) {
        guard phase.isRunning else { return }
        focusContext = context?.isEmpty == false ? context : nil
    }

    private func scheduleNextPrompt(from date: Date) {
        guard phase == .focusing, let focusDeadline else {
            nextPromptAt = nil
            return
        }
        let range = configuration.promptIntervalRange
        let generatedInterval = randomIntervalProvider(range)
        let safeInterval = min(max(generatedInterval, range.lowerBound), range.upperBound)
        let candidate = date.addingTimeInterval(safeInterval)
        nextPromptAt = candidate.addingTimeInterval(configuration.microBreakPresentationDuration) <= focusDeadline
            ? candidate
            : nil
    }

    private func beginMicroBreak(at date: Date) {
        phase = .microBreak
        nextPromptAt = nil
        microBreakIntroDeadline = date.addingTimeInterval(FocusConfiguration.microBreakIntroDuration)
        phaseDeadline = microBreakIntroDeadline!.addingTimeInterval(configuration.microBreakDuration)
        microBreaksTriggered += 1
        emit(.microBreakStarted(at: date, deadline: phaseDeadline!))
    }

    private func beginLongBreak(at focusEndDate: Date) {
        phase = .longBreak
        isPaused = false
        pauseReason = nil
        pausedAt = nil
        focusCompletedAt = focusEndDate
        focusDeadline = focusEndDate
        nextPromptAt = nil
        phaseDeadline = focusEndDate.addingTimeInterval(configuration.longBreakDuration)
        emit(.longBreakStarted(at: focusEndDate, deadline: phaseDeadline!))
    }

    private func completeLongBreak(at date: Date, skipped: Bool = false) {
        guard let startedAt else { return }
        let record = makeRecord(
            startedAt: startedAt,
            endedAt: date,
            outcome: .completed,
            longBreakCompleted: !skipped
        )
        lastRecord = record
        phase = .awaitingNextCycle
        clearActiveState(keepingLastRecord: true)
        emit(skipped ? .longBreakSkipped(at: date) : .longBreakCompleted(at: date))
        emit(.sessionEnded(record))
    }

    private func makeRecord(
        startedAt: Date,
        endedAt: Date,
        outcome: SessionOutcome,
        longBreakCompleted: Bool
    ) -> SessionRecordValue {
        let activeFocusDuration: TimeInterval
        if outcome == .completed {
            activeFocusDuration = configuration.focusDuration
        } else {
            let reference = isPaused ? pausedAt ?? endedAt : endedAt
            activeFocusDuration = min(
                configuration.focusDuration,
                max(0, reference.timeIntervalSince(startedAt) - accumulatedPausedDuration)
            )
        }

        return SessionRecordValue(
            startedAt: startedAt,
            endedAt: endedAt,
            plannedFocusDuration: configuration.focusDuration,
            activeFocusDuration: activeFocusDuration,
            outcome: outcome,
            microBreaksTriggered: microBreaksTriggered,
            microBreaksCompleted: microBreaksCompleted,
            microBreaksSkipped: microBreaksSkipped,
            longBreakCompleted: longBreakCompleted,
            focusContext: focusContext
        )
    }

    private func snapshotIsConsistent(_ snapshot: SessionSnapshot) -> Bool {
        switch snapshot.phase {
        case .focusing:
            snapshot.phaseDeadline == nil && snapshot.focusCompletedAt == nil
        case .microBreak:
            snapshot.phaseDeadline != nil && snapshot.focusCompletedAt == nil
        case .longBreak:
            snapshot.phaseDeadline != nil && snapshot.focusCompletedAt != nil
        case .idle, .awaitingNextCycle:
            false
        }
    }

    private func emit(_ event: SessionEvent) {
        onEvent?(event)
    }

    private func resetRuntimeState() {
        isPaused = false
        pauseReason = nil
        startedAt = nil
        focusDeadline = nil
        phaseDeadline = nil
        microBreakIntroDeadline = nil
        nextPromptAt = nil
        pausedAt = nil
        accumulatedPausedDuration = 0
        focusCompletedAt = nil
        microBreaksTriggered = 0
        microBreaksCompleted = 0
        microBreaksSkipped = 0
        focusContext = nil
        lastRecord = nil
    }

    private func clearActiveState(keepingLastRecord: Bool = true) {
        isPaused = false
        pauseReason = nil
        startedAt = nil
        focusDeadline = nil
        phaseDeadline = nil
        microBreakIntroDeadline = nil
        nextPromptAt = nil
        pausedAt = nil
        accumulatedPausedDuration = 0
        focusCompletedAt = nil
        microBreaksTriggered = 0
        microBreaksCompleted = 0
        microBreaksSkipped = 0
        focusContext = nil
        if !keepingLastRecord {
            lastRecord = nil
        }
    }
}
