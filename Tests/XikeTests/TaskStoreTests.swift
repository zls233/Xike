import Foundation
import XCTest
@testable import Xike

@MainActor
final class TaskStoreTests: XCTestCase {
    func testCreateUpdateCompleteArchiveFilterAndReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("tasks.json")
        let store = TaskStore(storageURL: url)

        let created = try XCTUnwrap(store.create(title: "  写 Redis 笔记  ", tag: "学习", estimatedMinutes: 45))
        XCTAssertEqual(created.title, "写 Redis 笔记")
        XCTAssertEqual(store.activeTasks.count, 1)
        XCTAssertEqual(store.filtered(search: "redis", status: .active, tag: "学习").map(\.id), [created.id])

        store.setCompleted(created.id, completed: true, at: Date(timeIntervalSinceReferenceDate: 10))
        XCTAssertTrue(try XCTUnwrap(store.task(id: created.id)).isCompleted)
        XCTAssertTrue(store.activeTasks.isEmpty)

        store.setCompleted(created.id, completed: false)
        store.setArchived(created.id, archived: true)
        XCTAssertEqual(store.filtered(search: "", status: .archived, tag: nil).count, 1)

        let reloaded = TaskStore(storageURL: url)
        XCTAssertEqual(reloaded.tasks, store.tasks)
    }

    func testTaskDeletionDoesNotChangeSessionTitleSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = TaskStore(storageURL: directory.appendingPathComponent("tasks.json"))
        let task = try XCTUnwrap(store.create(title: "实现任务记录"))
        let record = SessionRecordValue(
            startedAt: .distantPast,
            endedAt: .distantFuture,
            plannedFocusDuration: 900,
            activeFocusDuration: 600,
            outcome: .aborted,
            microBreaksTriggered: 1,
            microBreaksCompleted: 1,
            microBreaksSkipped: 0,
            longBreakCompleted: false,
            focusContext: FocusContext(taskID: task.id, taskTitleSnapshot: task.title)
        )

        store.delete(task.id)
        XCTAssertNil(store.task(id: task.id))
        XCTAssertEqual(record.focusContext?.taskTitleSnapshot, "实现任务记录")
    }

    func testOldSessionRecordJSONDecodesWithoutFocusContext() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","startedAt":0,"endedAt":60,"plannedFocusDuration":900,"activeFocusDuration":60,"outcome":"aborted","microBreaksTriggered":0,"microBreaksCompleted":0,"microBreaksSkipped":0,"longBreakCompleted":false}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let record = try decoder.decode(SessionRecordValue.self, from: Data(json.utf8))
        XCTAssertNil(record.focusContext)
    }
}
