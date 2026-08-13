import Foundation

public struct FocusContext: Codable, Equatable, Sendable {
    public var taskID: UUID?
    public var taskTitleSnapshot: String?
    public var goal: String?
    public var reflection: String?

    public init(
        taskID: UUID? = nil,
        taskTitleSnapshot: String? = nil,
        goal: String? = nil,
        reflection: String? = nil
    ) {
        self.taskID = taskID
        self.taskTitleSnapshot = taskTitleSnapshot?.nilIfBlank
        self.goal = goal?.nilIfBlank
        self.reflection = reflection?.nilIfBlank
    }

    public var isEmpty: Bool {
        taskID == nil && taskTitleSnapshot == nil && goal == nil && reflection == nil
    }
}

public struct TaskItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var tag: String?
    public var estimatedMinutes: Int?
    public var createdAt: Date
    public var completedAt: Date?
    public var isArchived: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        tag: String? = nil,
        estimatedMinutes: Int? = nil,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        isArchived: Bool = false
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tag = tag?.nilIfBlank
        self.estimatedMinutes = estimatedMinutes.flatMap { $0 > 0 ? $0 : nil }
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.isArchived = isArchived
    }

    public var isCompleted: Bool { completedAt != nil }
}

extension String {
    fileprivate var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
