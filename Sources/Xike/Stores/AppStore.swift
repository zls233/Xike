import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppStore {
    static let shared = AppStore()

    let preferences: PreferencesStore
    let history: HistoryStore
    let engine: SessionEngine
    let soundService: SoundService
    let notificationService: NotificationService
    let loginItemService: LoginItemService

    private(set) var displayDate = Date()
    private(set) var recoverySnapshot: SessionSnapshot?
    private(set) var shouldOfferResume = false
    private(set) var notificationPermission: NotificationPermissionState = .notDetermined
    private(set) var loginItemState: LoginItemState = .disabled
    var alertMessage: String?
    var showEndConfirmation = false
    var showHistoryClearConfirmation = false

    @ObservationIgnored private let snapshotStore: SnapshotStore
    @ObservationIgnored private let workspaceMonitor: WorkspaceActivityMonitor
    @ObservationIgnored private let microBreakPanel: MicroBreakPanelController
    @ObservationIgnored private var tickerTask: Task<Void, Never>?
    @ObservationIgnored private var lastSnapshotWrite = Date.distantPast
    @ObservationIgnored private var pausedAutomatically = false

    init(
        preferences: PreferencesStore = PreferencesStore(),
        history: HistoryStore = HistoryStore(),
        engine: SessionEngine? = nil,
        soundService: SoundService = SoundService(),
        notificationService: NotificationService = NotificationService(),
        loginItemService: LoginItemService = LoginItemService(),
        snapshotStore: SnapshotStore = SnapshotStore(),
        workspaceMonitor: WorkspaceActivityMonitor = WorkspaceActivityMonitor(),
        microBreakPanel: MicroBreakPanelController = MicroBreakPanelController()
    ) {
        self.preferences = preferences
        self.history = history
        self.engine = engine ?? SessionEngine(configuration: preferences.configuration)
        self.soundService = soundService
        self.notificationService = notificationService
        self.loginItemService = loginItemService
        self.snapshotStore = snapshotStore
        self.workspaceMonitor = workspaceMonitor
        self.microBreakPanel = microBreakPanel
        recoverySnapshot = snapshotStore.load()

        self.engine.onEvent = { [weak self] event in
            self?.handle(event)
        }
        workspaceMonitor.onPauseRequested = { [weak self] reason in
            self?.pauseForWorkspace(reason)
        }
        workspaceMonitor.onResumePromptRequested = { [weak self] _ in
            self?.offerResumeAfterWorkspaceInterruption()
        }
    }

    var remainingTime: TimeInterval {
        engine.remainingTime(at: displayDate)
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
        if recoverySnapshot != nil { return "待恢复专注" }
        if engine.isPaused { return "已暂停" }
        return switch engine.phase {
        case .idle: "准备专注"
        case .focusing: "专注中"
        case .microBreak: engine.isMicroBreakIntro(at: displayDate) ? "短休息开始" : "短休息"
        case .longBreak: "长休息"
        case .awaitingNextCycle: "本轮完成"
        }
    }

    var phaseSubtitle: String {
        if engine.isPaused {
            return engine.pauseReason == .manual ? "由你决定何时继续" : "回来后继续本轮"
        }
        return switch engine.phase {
        case .idle: "用 \(preferences.configuration.focusMinutes) 分钟进入自己的节奏"
        case .focusing: "提示会在合适的时候出现"
        case .microBreak: engine.isMicroBreakIntro(at: displayDate) ? "请暂时离开屏幕" : "望向远处，放松肩颈"
        case .longBreak: "离开屏幕，好好恢复"
        case .awaitingNextCycle: "准备好后再开始下一轮"
        }
    }

    var statusSystemImage: String {
        if recoverySnapshot != nil { return "arrow.counterclockwise.circle" }
        return engine.phase.systemImage
    }

    var isMicroBreakIntro: Bool {
        engine.isMicroBreakIntro(at: displayDate)
    }

    func start() {
        guard tickerTask == nil else { return }
        workspaceMonitor.start()
        loginItemState = loginItemService.state
        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
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
        soundService.stop()
        microBreakPanel.dismiss(animated: false)
    }

    @discardableResult
    func startSession() -> Bool {
        microBreakPanel.dismiss()
        recoverySnapshot = nil
        shouldOfferResume = false
        snapshotStore.clear()
        engine.configuration = preferences.configuration
        let started = engine.start()
        persistSnapshot(force: true)
        return started
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
            alertMessage = "上次的计时状态无法恢复，已安全清除。"
            return
        }
        recoverySnapshot = nil
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
                alertMessage = "请在系统设置的“登录项”中允许息刻。"
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

    private func advanceClock() {
        displayDate = Date()
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

    private func pauseForWorkspace(_ reason: WorkspaceInterruptionReason) {
        guard engine.canPause else { return }
        pausedAutomatically = engine.pause(reason: reason.pauseReason)
        if pausedAutomatically {
            persistSnapshot(force: true)
        }
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
