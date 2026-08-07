import Foundation
import OSLog

enum XikeLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.xike.app"

    static let audio = Logger(subsystem: subsystem, category: "Audio")
    static let notifications = Logger(subsystem: subsystem, category: "Notifications")
    static let loginItem = Logger(subsystem: subsystem, category: "LoginItem")
    static let workspace = Logger(subsystem: subsystem, category: "Workspace")
    static let microBreakPanel = Logger(subsystem: subsystem, category: "MicroBreakPanel")
}
