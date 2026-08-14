import Foundation
import Observation

@MainActor
@Observable
final class AppStore {
    static let shared = AppStore()

    let preferences: PreferencesStore
    let history: HistoryStore
    let tasks: TaskStore
    let engine: SessionEngine
    let soundService: SoundService
    let notificationService: NotificationService
    let loginItemService: LoginItemService
    let globalHotKeyService: GlobalHotKeyService

    private(set) var displayDate = Date()
    private(set) var statisticsDate = Date()
    private(set) var recoverySnapshot: SessionSnapshot?
    private(set) var shouldOfferResume = false
    private(set) var notificationPermission: NotificationPermissionState = .notDetermined
    private(set) var loginItemState: LoginItemState = .disabled
    var alertMessage: String?
    var showEndConfirmation = false
    var showHistoryClearConfirmation = false
    var selectedTaskID: UUID?
    var focusGoal = ""
    var reflection = ""

    @ObservationIgnored private let snapshotStore: SnapshotStore
    @ObservationIgnored private let workspaceMonitor: WorkspaceActivityMonitor
    @ObservationIgnored private let microBreakPanel: MicroBreakPanelController
    @ObservationIgnored private var tickerTask: Task<Void, Never>?
    @ObservationIgnored private var lastSnapshotWrite = Date.distantPast
    @ObservationIgnored private var pausedAutomatically = false

    init(
        preferences: PreferencesStore = PreferencesStore(),
        history: HistoryStore = HistoryStore(),
        tasks: TaskStore = TaskStore(),
        engine: SessionEngine? = nil,
        soundService: SoundService = SoundService(),
        notificationService: NotificationService = NotificationService(),
        loginItemService: LoginItemService = LoginItemService(),
        globalHotKeyService: GlobalHotKeyService = GlobalHotKeyService(),
        snapshotStore: SnapshotStore = SnapshotStore(),
        workspaceMonitor: WorkspaceActivityMonitor = WorkspaceActivityMonitor(),
        microBreakPanel: MicroBreakPanelController = MicroBreakPanelController()
    ) {
        self.preferences = preferences
        self.history = history
        self.tasks = tasks
        self.engine = engine ?? SessionEngine(configuration: preferences.configuration)
        self.soundService = soundService
        self.notificationService = notificationService
        self.loginItemService = loginItemService
        self.globalHotKeyService = globalHotKeyService
        self.snapshotStore = snapshotStore
        self.workspaceMonitor = workspaceMonitor
        self.microBreakPanel = microBreakPanel
        recoverySnapshot = snapshotStore.load()

        self.engine.onEvent = { [weak self] event in
            self?.handle(event)
        }
        workspaceMonitor.onInterruptionStarted = { [weak self] reason in
            self?.pauseForWorkspaceInterruption(reason)
        }
        workspaceMonitor.onInterruptionEnded = { [weak self] _ in
            self?.offerResumeAfterWorkspaceInterruption()
        }
    }

    var remainingTime: TimeInterval {
        let rawValue = engine.remainingTime(at: displayDate)
        return Self.cappedRemainingTime(
            rawValue,
            phase: engine.phase,
            configuration: engine.configuration
        )
    }

    nonisolated static func cappedRemainingTime(
        _ rawValue: TimeInterval,
        phase: SessionPhase,
        configuration: FocusConfiguration
    ) -> TimeInterval {
        switch phase {
        case .focusing:
            return min(rawValue, configuration.focusDuration)
        case .microBreak:
            return min(rawValue, configuration.microBreakPresentationDuration)
        case .longBreak:
            return min(rawValue, configuration.longBreakDuration)
        case .idle, .awaitingNextCycle:
            return rawValue
        }
    }

    var focusProgress: Double {
        guard engine.phase == .focusing || engine.phase == .microBreak else {
            return engine.phase == .longBreak || engine.phase == .awaitingNextCycle ? 1 : 0
        }
        let duration = max(engine.configuration.focusDuration, 1)
        return min(max(1 - engine.focusRemainingTime / duration, 0), 1)
    }

    var phaseProgress: Double {
        switch engine.phase {
        case .focusing:
            return focusProgress
        case .microBreak:
            let duration = max(engine.configuration.microBreakDuration, 1)
            return min(max(1 - engine.microBreakCountdownRemaining(at: displayDate) / duration, 0), 1)
        case .longBreak:
            let duration = max(engine.configuration.longBreakDuration, 1)
            return min(max(1 - remainingTime / duration, 0), 1)
        case .idle:
            return 0
        case .awaitingNextCycle:
            return 1
        }
    }

    var phaseTitle: String {
        if recoverySnapshot != nil { return "待恢复专注".xikeLocalized }
        if engine.isPaused { return "已暂停".xikeLocalized }
        return switch engine.phase {
        case .idle: "准备专注".xikeLocalized
        case .focusing: "专注中".xikeLocalized
        case .microBreak: engine.isMicroBreakIntro(at: displayDate) ? "短休息开始".xikeLocalized : "短休息".xikeLocalized
        case .longBreak: "长休息".xikeLocalized
        case .awaitingNextCycle: "本轮完成".xikeLocalized
        }
    }

    var phaseSubtitle: String {
        if engine.isPaused {
            return engine.pauseReason == .manual ? "由你决定何时继续".xikeLocalized : "回来后继续本轮".xikeLocalized
        }
        return switch engine.phase {
        case .idle: XikeText.format("用 %lld 分钟进入自己的节奏", preferences.configuration.focusMinutes)
        case .focusing: "提示会在合适的时候出现".xikeLocalized
        case .microBreak: engine.isMicroBreakIntro(at: displayDate) ? "请暂时离开屏幕".xikeLocalized : "望向远处，放松肩颈".xikeLocalized
        case .longBreak: "离开屏幕，好好恢复".xikeLocalized
        case .awaitingNextCycle: "准备好后再开始下一轮".xikeLocalized
        }
    }

    var statusSystemImage: String {
        if recoverySnapshot != nil { return "arrow.counterclockwise.circle" }
        // Paused is an overlay state, not a SessionPhase. It must win here so
        // the menu-bar label does not keep showing the previous phase's icon.
        if engine.isPaused { return "pause.circle.fill" }
        return engine.phase.systemImage
    }

    var isMicroBreakIntro: Bool {
        engine.isMicroBreakIntro(at: displayDate)
    }

    var todayStatistics: TodayStatistics {
        history.statistics(for: statisticsDate)
    }

    /// The dashboard and menu-bar surfaces share this single, live total.
    /// Records are attributed to their start day, matching the existing
    /// history and seven-day chart semantics.
    var todayActiveFocusDuration: TimeInterval {
        Self.totalFocusDuration(
            recordedDuration: history.activeFocusDuration(for: statisticsDate),
            sessionStartedAt: engine.startedAt,
            liveSessionDuration: engine.activeFocusDuration(at: displayDate),
            for: statisticsDate
        )
    }

    var recentDailyFocusSummaries: [DailyFocusSummary] {
        let summaries = history.summaries(endingAt: statisticsDate)
        guard let sessionStartedAt = engine.startedAt,
              Calendar.current.isDate(sessionStartedAt, inSameDayAs: statisticsDate)
        else {
            return summaries
        }

        let liveDuration = engine.activeFocusDuration(at: displayDate)
        return summaries.map { summary in
            guard Calendar.current.isDate(summary.date, inSameDayAs: statisticsDate) else {
                return summary
            }
            var updated = summary
            updated.activeFocusDuration += liveDuration
            return updated
        }
    }

    static func totalFocusDuration(
        recordedDuration: TimeInterval,
        sessionStartedAt: Date?,
        liveSessionDuration: TimeInterval,
        for date: Date,
        calendar: Calendar = .current
    ) -> TimeInterval {
        guard let sessionStartedAt,
              calendar.isDate(sessionStartedAt, inSameDayAs: date)
        else {
            return recordedDuration
        }
        return recordedDuration + max(0, liveSessionDuration)
    }

    func start() {
        guard tickerTask == nil else { return }
        workspaceMonitor.start()
        refreshGlobalShortcut()
        refreshBreakOverlayPreferences()
        loginItemState = loginItemService.state
        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.advanceClock()
            }
        }
        Task { [weak self] in
            guard let self else { return }
            self.notificationPermission = await self.notificationService.permissionState()
        }
    }

    func shutdown() {
        persistSnapshot(force: true)
        tickerTask?.cancel()
        tickerTask = nil
        workspaceMonitor.stop()
        globalHotKeyService.unregister()
        soundService.stop()
        microBreakPanel.dismiss(animated: false)
    }

    @discardableResult
    func startSession(taskID: UUID? = nil, goal: String? = nil) -> Bool {
        microBreakPanel.dismiss()
        recoverySnapshot = nil
        shouldOfferResume = false
        snapshotStore.clear()
        engine.configuration = preferences.configuration
        let resolvedTaskID = taskID ?? selectedTaskID
        let selectedTask = tasks.task(id: resolvedTaskID)
        let resolvedGoal = goal ?? focusGoal
        let context = FocusContext(
            taskID: selectedTask?.id,
            taskTitleSnapshot: selectedTask?.title,
            goal: resolvedGoal,
            reflection: reflection
        )
        let startDate = Date()
        displayDate = startDate
        let started = engine.start(context: context, at: startDate)
        persistSnapshot(force: true)
        return started
    }

    func updateCurrentReflection(_ value: String) {
        reflection = value
        guard var context = engine.focusContext else { return }
        context.reflection = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
        engine.updateFocusContext(context)
        persistSnapshot(force: true)
    }

    func pauseSession() {
        guard engine.pause(reason: .manual) else { return }
        persistSnapshot(force: true)
    }

    func resumeSession() {
        guard engine.resume() else { return }
        shouldOfferResume = false
        pausedAutomatically = false
        persistSnapshot(force: true)
    }

    func endSession() {
        _ = engine.end()
        shouldOfferResume = false
        recoverySnapshot = nil
        pausedAutomatically = false
        microBreakPanel.dismiss()
        snapshotStore.clear()
    }

    func skipMicroBreak() {
        guard engine.skipMicroBreak() else { return }
        microBreakPanel.dismiss()
        persistSnapshot(force: true)
    }

    func skipLongBreak() {
        guard engine.skipLongBreak() else { return }
        shouldOfferResume = false
        persistSnapshot(force: true)
    }

    /// Long break is post-focus recovery, not an unfinished focus session.
    /// Its end control must therefore never use the abort confirmation.
    func requestEndSession() {
        if engine.phase == .longBreak {
            skipLongBreak()
        } else {
            showEndConfirmation = true
        }
    }

    func restoreSavedSession() {
        guard let snapshot = recoverySnapshot else { return }
        guard engine.restore(from: snapshot) else {
            discardSavedSession()
            alertMessage = "上次的计时状态无法恢复，已安全清除。".xikeLocalized
            return
        }
        recoverySnapshot = nil
        selectedTaskID = engine.focusContext?.taskID
        focusGoal = engine.focusContext?.goal ?? ""
        reflection = engine.focusContext?.reflection ?? ""
        shouldOfferResume = true
        persistSnapshot(force: true)
    }

    func discardSavedSession() {
        recoverySnapshot = nil
        shouldOfferResume = false
        snapshotStore.clear()
    }

    func resetCompletedCycle() {
        microBreakPanel.dismiss()
        engine.resetToIdle()
        reflection = ""
    }

    func previewSound(_ soundID: String) {
        do {
            _ = try soundService.preview(soundID: soundID, volume: preferences.configuration.volume)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func requestNotificationPermission() async {
        do {
            _ = try await notificationService.requestAuthorization()
            notificationPermission = await notificationService.permissionState()
        } catch {
            notificationPermission = await notificationService.permissionState()
            alertMessage = error.localizedDescription
        }
    }

    func completeOnboarding() async {
        if preferences.notificationsEnabled, notificationPermission == .notDetermined {
            await requestNotificationPermission()
        }
        preferences.markOnboardingCompleted()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            loginItemState = try loginItemService.setEnabled(enabled)
            preferences.launchAtLogin = enabled
            if loginItemState == .requiresApproval {
                alertMessage = "请在系统设置的“登录项”中允许息刻。".xikeLocalized
            }
        } catch {
            preferences.launchAtLogin = loginItemService.isEnabled
            loginItemState = loginItemService.state
            alertMessage = error.localizedDescription
        }
    }

    func clearAlert() {
        alertMessage = nil
    }

    func refreshGlobalShortcut() {
        guard preferences.globalShortcutEnabled else {
            globalHotKeyService.unregister()
            return
        }
        globalHotKeyService.register(shortcut: preferences.globalShortcut) { [weak self] in
            self?.performPrimarySessionAction()
        }
    }

    func refreshBreakOverlayPreferences() {
        microBreakPanel.configure(
            isEnabled: preferences.breakOverlayEnabled,
            position: preferences.breakOverlayPosition
        )
    }

    func previewBreakOverlay() {
        refreshBreakOverlayPreferences()
        microBreakPanel.showPreview()
    }

    func performPrimarySessionAction() {
        if engine.canPause { pauseSession() }
        else if engine.canResume { resumeSession() }
        else if engine.canStart { _ = startSession() }
    }

    private func advanceClock() {
        let now = Date()
        displayDate = now
        if !Calendar.current.isDate(now, inSameDayAs: statisticsDate) {
            statisticsDate = now
        }
        engine.tick(at: displayDate)
        if engine.phase == .microBreak, !engine.isPaused {
            microBreakPanel.updateMicroBreak(
                isShowingCountdown: !engine.isMicroBreakIntro(at: displayDate),
                remainingSeconds: Int(ceil(engine.microBreakCountdownRemaining(at: displayDate)))
            )
        }
        persistSnapshot(force: false)
    }

    private func handle(_ event: SessionEvent) {
        switch event {
        case .sessionStarted:
            break

        case .sessionPaused:
            soundService.stop()
            if engine.phase == .microBreak {
                microBreakPanel.dismiss()
            }

        case .sessionResumed:
            if engine.phase == .microBreak {
                showMicroBreakPanel()
            }

        case .microBreakStarted:
            playConfiguredSound()
            showMicroBreakPanel()

        case .microBreakCompleted:
            microBreakPanel.dismiss()
            playConfiguredSound()

        case .microBreakSkipped:
            microBreakPanel.dismiss()

        case .longBreakStarted:
            microBreakPanel.dismiss()
            playConfiguredSound()
            microBreakPanel.showLongBreak()
            if preferences.notificationsEnabled {
                Task { [notificationService, minutes = engine.configuration.longBreakMinutes] in
                    _ = try? await notificationService.notifyLongBreakStarted(durationMinutes: minutes)
                }
            }

        case .longBreakCompleted:
            playConfiguredSound()
            microBreakPanel.showLongBreakCompletion(
                onStartNextFocus: { [weak self] in
                    _ = self?.startSession()
                },
                onEndFocus: { [weak self] in
                    self?.resetCompletedCycle()
                }
            )
            if preferences.notificationsEnabled {
                Task { [notificationService] in
                    _ = try? await notificationService.notifyLongBreakEnded()
                }
            }

        case .longBreakSkipped:
            break

        case .sessionEnded(let record):
            history.add(record)
            reflection = ""
            snapshotStore.clear()

        case .snapshotRestored:
            break

        case .invalidConfiguration(let error):
            alertMessage = error.localizedDescription
        }
    }

    private func playConfiguredSound() {
        do {
            _ = try soundService.playAlert(configuration: engine.configuration)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func showMicroBreakPanel() {
        microBreakPanel.showMicroBreak(
            isShowingCountdown: !engine.isMicroBreakIntro(at: displayDate),
            remainingSeconds: Int(ceil(engine.microBreakCountdownRemaining(at: displayDate))),
            onSkip: { [weak self] in self?.skipMicroBreak() }
        )
    }

    private func pauseForWorkspaceInterruption(_ reason: WorkspaceInterruptionReason) {
        guard !preferences.continuesTimingDuringWorkspaceInterruption,
              engine.canPause
        else { return }
        pausedAutomatically = engine.pause(reason: reason.pauseReason)
        if pausedAutomatically { persistSnapshot(force: true) }
    }

    private func offerResumeAfterWorkspaceInterruption() {
        guard pausedAutomatically, engine.canResume else { return }
        shouldOfferResume = true
        if preferences.notificationsEnabled {
            Task { [notificationService] in
                _ = try? await notificationService.notifyResumeAvailable()
            }
        }
    }

    private func persistSnapshot(force: Bool) {
        // Until the user explicitly restores or discards a recovered session,
        // the in-memory engine is intentionally idle. Never let its nil
        // snapshot erase the still-actionable disk snapshot.
        if recoverySnapshot != nil, !engine.phase.isRunning {
            return
        }
        let now = Date()
        guard force || now.timeIntervalSince(lastSnapshotWrite) >= 2 else { return }
        lastSnapshotWrite = now
        snapshotStore.save(engine.makeSnapshot(at: now))
    }
}
