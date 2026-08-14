import Foundation
import Observation

#if XCODE_BUILD
import SwiftData

@Model
final class SessionRecordEntity {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date
    var plannedFocusDuration: Double
    var activeFocusDuration: Double
    var outcomeRawValue: String
    var microBreaksTriggered: Int
    var microBreaksCompleted: Int
    var microBreaksSkipped: Int
    var longBreakCompleted: Bool
    var taskID: UUID?
    var taskTitleSnapshot: String?
    var focusGoal: String?
    var reflection: String?

    init(_ value: SessionRecordValue) {
        id = value.id
        startedAt = value.startedAt
        endedAt = value.endedAt
        plannedFocusDuration = value.plannedFocusDuration
        activeFocusDuration = value.activeFocusDuration
        outcomeRawValue = value.outcome.rawValue
        microBreaksTriggered = value.microBreaksTriggered
        microBreaksCompleted = value.microBreaksCompleted
        microBreaksSkipped = value.microBreaksSkipped
        longBreakCompleted = value.longBreakCompleted
        taskID = value.focusContext?.taskID
        taskTitleSnapshot = value.focusContext?.taskTitleSnapshot
        focusGoal = value.focusContext?.goal
        reflection = value.focusContext?.reflection
    }

    var value: SessionRecordValue {
        let context = FocusContext(
            taskID: taskID,
            taskTitleSnapshot: taskTitleSnapshot,
            goal: focusGoal,
            reflection: reflection
        )
        return SessionRecordValue(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            plannedFocusDuration: plannedFocusDuration,
            activeFocusDuration: activeFocusDuration,
            outcome: SessionOutcome(rawValue: outcomeRawValue) ?? .aborted,
            microBreaksTriggered: microBreaksTriggered,
            microBreaksCompleted: microBreaksCompleted,
            microBreaksSkipped: microBreaksSkipped,
            longBreakCompleted: longBreakCompleted,
            focusContext: context.isEmpty ? nil : context
        )
    }
}

#endif

struct TodayStatistics: Equatable, Sendable {
    var completedCycles: Int
    var activeMinutes: Int
    var microBreakCompletionRate: Double

    static let empty = TodayStatistics(completedCycles: 0, activeMinutes: 0, microBreakCompletionRate: 0)
}

struct DailyFocusSummary: Identifiable, Equatable, Sendable {
    var date: Date
    var activeFocusDuration: TimeInterval
    var completedCycles: Int

    var id: Date { date }

    var minutes: Int {
        Int((activeFocusDuration / 60).rounded())
    }
}

@MainActor
@Observable
final class HistoryStore {
    private(set) var records: [SessionRecordValue] = []
    private(set) var persistenceError: String?

    @ObservationIgnored
    private let calendar: Calendar

#if XCODE_BUILD
    @ObservationIgnored
    private let container: ModelContainer?
#else
    @ObservationIgnored
    private let storageURL: URL
#endif

    init(calendar: Calendar = .current, storageURL: URL? = nil) {
        self.calendar = calendar
#if XCODE_BUILD
        do {
            // The newly added task context columns are optional, so SwiftData
            // can perform its inferred lightweight migration for existing stores.
            container = try ModelContainer(for: SessionRecordEntity.self)
        } catch {
            container = nil
            persistenceError = XikeText.format("无法打开专注记录：%@", error.localizedDescription)
        }
        reloadFromSwiftData()
#else
        self.storageURL = storageURL ?? Self.defaultStorageURL()
        loadJSON()
#endif
    }

    func add(_ record: SessionRecordValue) {
        guard !records.contains(where: { $0.id == record.id }) else { return }
        records.append(record)
        records.sort { $0.startedAt > $1.startedAt }
#if XCODE_BUILD
        guard let context = container?.mainContext else { return }
        context.insert(SessionRecordEntity(record))
        do {
            try context.save()
        } catch {
            persistenceError = XikeText.format("无法保存专注记录：%@", error.localizedDescription)
        }
#else
        saveJSON()
#endif
    }

    func clearAll() {
#if XCODE_BUILD
        if let context = container?.mainContext {
            do {
                try context.delete(model: SessionRecordEntity.self)
                try context.save()
            } catch {
                persistenceError = XikeText.format("无法清除专注记录：%@", error.localizedDescription)
                return
            }
        }
#endif
        records.removeAll()
#if !XCODE_BUILD
        saveJSON()
#endif
    }

    func records(for taskID: UUID) -> [SessionRecordValue] {
        records.filter { $0.focusContext?.taskID == taskID }
    }

    func activeMinutes(for taskID: UUID) -> Int {
        Int((records(for: taskID).reduce(0) { $0 + $1.activeFocusDuration } / 60).rounded())
    }

    func activeFocusDuration(for date: Date = Date()) -> TimeInterval {
        Self.activeFocusDuration(in: records, for: date, calendar: calendar)
    }

    static func activeFocusDuration(
        in records: [SessionRecordValue],
        for date: Date,
        calendar: Calendar = .current
    ) -> TimeInterval {
        records
            .filter { calendar.isDate($0.startedAt, inSameDayAs: date) }
            .reduce(0) { $0 + $1.activeFocusDuration }
    }

    func statistics(for date: Date = Date()) -> TodayStatistics {
        let todayRecords = records.filter { calendar.isDate($0.startedAt, inSameDayAs: date) }
        guard !todayRecords.isEmpty else { return .empty }
        let completed = todayRecords.filter { $0.outcome == .completed }.count
        let activeSeconds = Self.activeFocusDuration(in: todayRecords, for: date, calendar: calendar)
        let triggered = todayRecords.reduce(0) { $0 + $1.microBreaksTriggered }
        let completedBreaks = todayRecords.reduce(0) { $0 + $1.microBreaksCompleted }
        let rate = triggered == 0 ? 0 : Double(completedBreaks) / Double(triggered)
        return TodayStatistics(
            completedCycles: completed,
            activeMinutes: Int((activeSeconds / 60).rounded()),
            microBreakCompletionRate: rate
        )
    }

    func summaries(endingAt date: Date = Date(), days: Int = 7) -> [DailyFocusSummary] {
        guard days > 0 else { return [] }
        let end = calendar.startOfDay(for: date)
        return (0 ..< days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: end) else { return nil }
            let matching = records.filter { calendar.isDate($0.startedAt, inSameDayAs: day) }
            let seconds = matching.reduce(0) { $0 + $1.activeFocusDuration }
            return DailyFocusSummary(
                date: day,
                activeFocusDuration: seconds,
                completedCycles: matching.filter { $0.outcome == .completed }.count
            )
        }
    }

#if XCODE_BUILD
    private func reloadFromSwiftData() {
        guard let context = container?.mainContext else { return }
        var descriptor = FetchDescriptor<SessionRecordEntity>()
        descriptor.sortBy = [SortDescriptor(\SessionRecordEntity.startedAt, order: .reverse)]
        do {
            records = try context.fetch(descriptor).map(\.value)
        } catch {
            persistenceError = XikeText.format("无法读取专注记录：%@", error.localizedDescription)
        }
    }
#else
    private static func defaultStorageURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("com.zhanglishan.Xike", isDirectory: true)
            .appendingPathComponent("session-history.json", isDirectory: false)
    }

    private func loadJSON() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            records = try JSONDecoder().decode([SessionRecordValue].self, from: data)
                .sorted { $0.startedAt > $1.startedAt }
        } catch {
            persistenceError = XikeText.format("无法读取专注记录：%@", error.localizedDescription)
        }
    }

    private func saveJSON() {
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(records)
            try data.write(to: storageURL, options: .atomic)
            persistenceError = nil
        } catch {
            persistenceError = XikeText.format("无法保存专注记录：%@", error.localizedDescription)
        }
    }
#endif
}
