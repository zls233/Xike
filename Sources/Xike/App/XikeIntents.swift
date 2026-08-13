import AppIntents
import AppKit
import Foundation

struct XikeTaskEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "息刻任务")
    static let defaultQuery = XikeTaskQuery()

    let id: UUID
    let title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "息刻任务")
    }
}

struct XikeTaskQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [XikeTaskEntity] {
        await MainActor.run {
            identifiers.compactMap { AppStore.shared.tasks.task(id: $0) }.map(XikeTaskEntity.init)
        }
    }

    func suggestedEntities() async throws -> [XikeTaskEntity] {
        await MainActor.run { AppStore.shared.tasks.activeTasks.prefix(12).map(XikeTaskEntity.init) }
    }
}

private extension XikeTaskEntity {
    init(_ task: TaskItem) {
        id = task.id
        title = task.title
    }
}

struct StartFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "开始息刻专注"
    static let description = IntentDescription("开始一轮专注，可选择一个待完成任务。")
    static let openAppWhenRun = false

    @Parameter(title: "任务") var task: XikeTaskEntity?
    @Parameter(title: "本轮目标") var goal: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let started = await MainActor.run { AppStore.shared.startSession(taskID: task?.id, goal: goal) }
        return .result(dialog: IntentDialog(started ? "专注已经开始。" : "当前已有一轮专注正在进行。"))
    }
}

struct PauseResumeFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "暂停或继续息刻"
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await MainActor.run { () -> String in
            let store = AppStore.shared
            if store.engine.canPause { store.pauseSession(); return "专注已暂停。" }
            if store.engine.canResume { store.resumeSession(); return "专注已继续。" }
            return "目前没有可暂停或继续的专注。"
        }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct EndFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "结束息刻专注"
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ended = await MainActor.run { () -> Bool in
            guard AppStore.shared.engine.canEnd else { return false }
            AppStore.shared.endSession()
            return true
        }
        return .result(dialog: IntentDialog(ended ? "本轮专注已经结束并记录。" : "目前没有正在进行的专注。"))
    }
}

enum XikeWindowDestination: String, AppEnum {
    case tasks
    case history

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "息刻窗口")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .tasks: "任务",
        .history: "专注记录",
    ]
}

struct OpenXikeWindowIntent: AppIntent {
    static let title: LocalizedStringResource = "打开息刻窗口"
    static let openAppWhenRun = true

    @Parameter(title: "窗口") var destination: XikeWindowDestination

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(name: .openXikeWindow, object: destination.rawValue)
            NSApp.activate(ignoringOtherApps: true)
        }
        return .result()
    }
}

enum RhythmPreset: String, AppEnum {
    case balanced
    case deepWork
    case gentle

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "息刻节律")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .balanced: "均衡（90 分钟）",
        .deepWork: "深度工作（120 分钟）",
        .gentle: "轻节律（45 分钟）",
    ]

    var configuration: FocusConfiguration {
        var value = FocusConfiguration.default
        switch self {
        case .balanced: break
        case .deepWork:
            value.focusMinutes = 120
            value.longBreakMinutes = 25
            value.minimumPromptMinutes = 5
            value.maximumPromptMinutes = 8
        case .gentle:
            value.focusMinutes = 45
            value.longBreakMinutes = 10
            value.minimumPromptMinutes = 3
            value.maximumPromptMinutes = 5
        }
        return value
    }
}

struct XikeFocusFilterIntent: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "息刻节律"
    static let description = IntentDescription("专注模式启用时，为下一轮息刻专注选择节律。")

    @Parameter(title: "节律") var preset: RhythmPreset?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(preset ?? .balanced)")
    }

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            let current = AppStore.shared.preferences.configuration
            var configured = (preset ?? .balanced).configuration
            configured.soundMode = current.soundMode
            configured.selectedSoundIDs = current.selectedSoundIDs
            configured.volume = current.volume
            AppStore.shared.preferences.configuration = configured
        }
        return .result()
    }

    static func suggestedFocusFilters(for context: FocusFilterSuggestionContext) async -> [Self] {
        [.init(preset: .balanced), .init(preset: .deepWork), .init(preset: .gentle)]
    }

    init() {}
    init(preset: RhythmPreset) { self.preset = preset }
}

struct XikeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartFocusIntent(), phrases: ["用 \(.applicationName) 开始专注"], shortTitle: "开始专注", systemImageName: "play.fill")
        AppShortcut(intent: PauseResumeFocusIntent(), phrases: ["暂停或继续 \(.applicationName)"], shortTitle: "暂停或继续", systemImageName: "pause.fill")
        AppShortcut(intent: EndFocusIntent(), phrases: ["结束 \(.applicationName) 专注"], shortTitle: "结束专注", systemImageName: "stop.fill")
    }
}

extension Notification.Name {
    static let openXikeWindow = Notification.Name("com.zhanglishan.Xike.openWindow")
}
