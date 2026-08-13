import Foundation
import UserNotifications

enum NotificationPermissionState: Sendable, Equatable {
    case notDetermined
    case denied
    case authorized
}

enum NotificationServiceError: LocalizedError {
    case permissionDenied
    case unavailableOutsideApplicationBundle

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "通知权限未开启。提示音和休息浮层仍可正常使用。"
        case .unavailableOutsideApplicationBundle:
            "通知服务只能从 Xike.app 中使用。"
        }
    }
}

/// Local notifications are supplemental; callers must never use delivery as a timer signal.
@MainActor
final class NotificationService {
    private let center: UNUserNotificationCenter?

    init(center: UNUserNotificationCenter? = nil) {
        if let center {
            self.center = center
        } else if Self.supportsNotifications(
            bundleURL: Bundle.main.bundleURL,
            bundleIdentifier: Bundle.main.bundleIdentifier
        ) {
            // UNUserNotificationCenter raises an Objective-C exception when a
            // command-line debugger launches the Mach-O outside its app bundle.
            self.center = .current()
        } else {
            self.center = nil
            XikeLog.notifications.notice("Notification service unavailable outside an application bundle")
        }
    }

    func permissionState() async -> NotificationPermissionState {
        guard let center else { return .notDetermined }
        let settings = await center.notificationSettings()
        return Self.permissionState(for: settings.authorizationStatus)
    }

    @discardableResult
    func requestAuthorization() async throws -> Bool {
        guard let center else {
            throw NotificationServiceError.unavailableOutsideApplicationBundle
        }
        return try await center.requestAuthorization(options: [.alert, .sound])
    }

    @discardableResult
    func notifyLongBreakStarted(durationMinutes: Int) async throws -> Bool {
        let minutes = max(durationMinutes, 1)
        return try await send(
            identifier: "xike.long-break.started",
            title: "专注完成",
            body: "现在休息 \(minutes) 分钟吧。",
            interruptionLevel: .active
        )
    }

    @discardableResult
    func notifyLongBreakEnded() async throws -> Bool {
        try await send(
            identifier: "xike.long-break.ended",
            title: "长休息结束",
            body: "准备好后，可以开始下一轮专注。",
            interruptionLevel: .active
        )
    }

    @discardableResult
    func notifyResumeAvailable() async throws -> Bool {
        try await send(
            identifier: "xike.session.resume",
            title: "专注已暂停",
            body: "设备已经恢复，请选择继续本轮或结束本轮。",
            interruptionLevel: .active
        )
    }

    func removeDeliveredNotifications() {
        center?.removeDeliveredNotifications(withIdentifiers: [
            "xike.long-break.started",
            "xike.long-break.ended",
            "xike.session.resume",
        ])
    }

    @discardableResult
    private func send(
        identifier: String,
        title: String,
        body: String,
        interruptionLevel: UNNotificationInterruptionLevel
    ) async throws -> Bool {
        guard let center else { return false }
        let state = await permissionState()
        guard state == .authorized else {
            if state == .denied {
                XikeLog.notifications.notice("Notification skipped because permission is denied")
            }
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = interruptionLevel

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        try await center.add(request)
        return true
    }

    private static func permissionState(for status: UNAuthorizationStatus) -> NotificationPermissionState {
        switch status {
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .authorized, .provisional, .ephemeral:
            .authorized
        @unknown default:
            .denied
        }
    }

    nonisolated static func supportsNotifications(bundleURL: URL, bundleIdentifier: String?) -> Bool {
        bundleURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame
            && !(bundleIdentifier?.isEmpty ?? true)
    }
}
