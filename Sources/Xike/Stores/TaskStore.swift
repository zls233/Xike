import Foundation
import Observation

enum TaskStatusFilter: String, CaseIterable, Identifiable {
    case active
    case completed
    case archived
    case all

    var id: String { rawValue }
    var title: String {
        switch self {
        case .active: "待完成"
        case .completed: "已完成"
        case .archived: "已归档"
        case .all: "全部"
        }
    }
}

@MainActor
@Observable
final class TaskStore {
    private(set) var tasks: [TaskItem] = []
    private(set) var persistenceError: String?

    @ObservationIgnored private let storageURL: URL

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? Self.defaultStorageURL()
        load()
    }

    var activeTasks: [TaskItem] {
        tasks.filter { !$0.isArchived && !$0.isCompleted }
    }

    var tags: [String] {
        Array(Set(tasks.compactMap(\.tag))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    @discardableResult
    func create(title: String, tag: String? = nil, estimatedMinutes: Int? = nil) -> TaskItem? {
        let item = TaskItem(title: title, tag: tag, estimatedMinutes: estimatedMinutes)
        guard !item.title.isEmpty else { return nil }
        tasks.insert(item, at: 0)
        save()
        return item
    }

    func update(_ item: TaskItem) {
        guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let index = tasks.firstIndex(where: { $0.id == item.id }) else { return }
        tasks[index] = item
        sort()
        save()
    }

    func setCompleted(_ id: UUID, completed: Bool, at date: Date = Date()) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].completedAt = completed ? date : nil
        if !completed { tasks[index].isArchived = false }
        sort()
        save()
    }

    func setArchived(_ id: UUID, archived: Bool) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].isArchived = archived
        sort()
        save()
    }

    func delete(_ id: UUID) {
        tasks.removeAll { $0.id == id }
        save()
    }

    func task(id: UUID?) -> TaskItem? {
        guard let id else { return nil }
        return tasks.first { $0.id == id }
    }

    func filtered(search: String, status: TaskStatusFilter, tag: String?) -> [TaskItem] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return tasks.filter { item in
            let statusMatches = switch status {
            case .active: !item.isArchived && !item.isCompleted
            case .completed: !item.isArchived && item.isCompleted
            case .archived: item.isArchived
            case .all: true
            }
            let tagMatches = tag == nil || item.tag == tag
            let searchMatches = query.isEmpty
                || item.title.localizedCaseInsensitiveContains(query)
                || (item.tag?.localizedCaseInsensitiveContains(query) ?? false)
            return statusMatches && tagMatches && searchMatches
        }
    }

    private func sort() {
        tasks.sort {
            if $0.isArchived != $1.isArchived { return !$0.isArchived }
            if $0.isCompleted != $1.isCompleted { return !$0.isCompleted }
            return $0.createdAt > $1.createdAt
        }
    }

    private static func defaultStorageURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("com.zhanglishan.Xike", isDirectory: true)
            .appendingPathComponent("tasks.json")
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            tasks = try JSONDecoder().decode([TaskItem].self, from: Data(contentsOf: storageURL))
            sort()
        } catch {
            persistenceError = "无法读取任务：\(error.localizedDescription)"
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(tasks).write(to: storageURL, options: .atomic)
            persistenceError = nil
        } catch {
            persistenceError = "无法保存任务：\(error.localizedDescription)"
        }
    }
}
