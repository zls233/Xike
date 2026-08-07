import AppKit
import Foundation

enum WorkspaceInterruptionReason: String, Hashable, Sendable {
    case systemSleep
    case screenSleep
    case sessionInactive

    var pauseReason: PauseReason {
        switch self {
        case .systemSleep, .screenSleep:
            .systemSleep
        case .sessionInactive:
            .sessionInactive
        }
    }
}

/// Converts overlapping AppKit workspace notifications into one pause and one resume prompt.
/// It never resumes a session itself.
@MainActor
final class WorkspaceActivityMonitor: NSObject {
    typealias PauseHandler = @MainActor (WorkspaceInterruptionReason) -> Void
    typealias ResumePromptHandler = @MainActor (Set<WorkspaceInterruptionReason>) -> Void

    private let notificationCenter: NotificationCenter
    private var activeInterruptions: Set<WorkspaceInterruptionReason> = []
    private var interruptionCycle: Set<WorkspaceInterruptionReason> = []
    private var isMonitoring = false

    var onPauseRequested: PauseHandler?
    var onResumePromptRequested: ResumePromptHandler?

    init(
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        onPauseRequested: PauseHandler? = nil,
        onResumePromptRequested: ResumePromptHandler? = nil
    ) {
        self.notificationCenter = notificationCenter
        self.onPauseRequested = onPauseRequested
        self.onResumePromptRequested = onResumePromptRequested
        super.init()
    }

    deinit {
        notificationCenter.removeObserver(self)
    }

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true

        notificationCenter.addObserver(
            self,
            selector: #selector(workspaceWillSleep(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(screensDidSleep(_:)),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(screensDidWake(_:)),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(sessionDidResignActive(_:)),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(sessionDidBecomeActive(_:)),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
    }

    func stop() {
        guard isMonitoring else { return }
        notificationCenter.removeObserver(self)
        activeInterruptions.removeAll()
        interruptionCycle.removeAll()
        isMonitoring = false
    }

    private func beginInterruption(_ reason: WorkspaceInterruptionReason) {
        guard activeInterruptions.insert(reason).inserted else { return }
        interruptionCycle.insert(reason)
        XikeLog.workspace.info("Workspace interruption began: \(reason.rawValue, privacy: .public)")

        if activeInterruptions.count == 1 {
            onPauseRequested?(reason)
        }
    }

    private func endInterruption(_ reason: WorkspaceInterruptionReason) {
        guard activeInterruptions.remove(reason) != nil else { return }
        XikeLog.workspace.info("Workspace interruption ended: \(reason.rawValue, privacy: .public)")

        guard activeInterruptions.isEmpty else { return }
        let completedCycle = interruptionCycle
        interruptionCycle.removeAll()
        onResumePromptRequested?(completedCycle)
    }

    @objc private func workspaceWillSleep(_ notification: Notification) {
        beginInterruption(.systemSleep)
    }

    @objc private func workspaceDidWake(_ notification: Notification) {
        endInterruption(.systemSleep)
    }

    @objc private func screensDidSleep(_ notification: Notification) {
        beginInterruption(.screenSleep)
    }

    @objc private func screensDidWake(_ notification: Notification) {
        endInterruption(.screenSleep)
    }

    @objc private func sessionDidResignActive(_ notification: Notification) {
        beginInterruption(.sessionInactive)
    }

    @objc private func sessionDidBecomeActive(_ notification: Notification) {
        endInterruption(.sessionInactive)
    }
}
