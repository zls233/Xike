import Foundation
import XCTest
@testable import Xike

final class NotificationServiceTests: XCTestCase {
    func testNotificationsAreUnavailableForBareBuildProductDirectory() {
        let buildDirectory = URL(fileURLWithPath: "/tmp/Xike/Build/Products/Debug/", isDirectory: true)

        XCTAssertFalse(
            NotificationService.supportsNotifications(
                bundleURL: buildDirectory,
                bundleIdentifier: nil
            )
        )
    }

    func testNotificationsAreAvailableForIdentifiedApplicationBundle() {
        let appURL = URL(fileURLWithPath: "/Applications/Xike.app", isDirectory: true)

        XCTAssertTrue(
            NotificationService.supportsNotifications(
                bundleURL: appURL,
                bundleIdentifier: "com.zhanglishan.Xike"
            )
        )
    }
}
