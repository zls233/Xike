import Foundation
import ServiceManagement

enum LoginItemState: String, Sendable, Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
}

enum LoginItemServiceError: LocalizedError {
    case unavailable
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "登录项服务当前不可用。请确认 App 位于“应用程序”文件夹中。"
        case .operationFailed(let details):
            "无法更新登录时启动设置：\(details)"
        }
    }
}

@MainActor
final class LoginItemService {
    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    var state: LoginItemState {
        switch service.status {
        case .notRegistered:
            .disabled
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .unavailable
        @unknown default:
            .unavailable
        }
    }

    var isEnabled: Bool { state == .enabled }

    /// Returns the status reported by ServiceManagement after the operation.
    @discardableResult
    func setEnabled(_ enabled: Bool) throws -> LoginItemState {
        do {
            if enabled {
                if service.status == .notFound {
                    throw LoginItemServiceError.unavailable
                }
                if service.status == .notRegistered {
                    try service.register()
                }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
        } catch let error as LoginItemServiceError {
            throw error
        } catch {
            XikeLog.loginItem.error("Login item operation failed: \(error.localizedDescription, privacy: .public)")
            throw LoginItemServiceError.operationFailed(error.localizedDescription)
        }

        return state
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
