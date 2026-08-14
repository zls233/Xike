import AppKit
import SwiftUI

struct DashboardView: View {
    @Bindable var store: AppStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if store.shouldOfferResume {
                    ResumeSessionBanner(store: store)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        TimerCardView(store: store)
                            .frame(minWidth: 500, maxWidth: .infinity)
                        VStack(spacing: 16) {
                            StatisticsView(store: store)
                                .frame(height: 236)
                            ActiveTasksCard(store: store)
                                .frame(height: 180)
                        }
                        .frame(width: 326)
                    }

                    VStack(spacing: 16) {
                        TimerCardView(store: store)
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 16) {
                                StatisticsView(store: store)
                                ActiveTasksCard(store: store)
                            }
                            VStack(spacing: 16) {
                                StatisticsView(store: store)
                                ActiveTasksCard(store: store)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background { dashboardBackground }
        .frame(minWidth: 520, minHeight: 560)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button("任务", systemImage: "checklist") { openWindow(id: "tasks") }
                Button("记录", systemImage: "clock.arrow.circlepath") { openWindow(id: "history") }
            }
            ToolbarSpacer(.fixed)
            ToolbarItem(placement: .primaryAction) {
                SettingsLink { Label("设置", systemImage: "gearshape") }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("专注工作台")
                    .font(.largeTitle.weight(.semibold))
                Text(headerSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label("仅保存在本机", systemImage: "lock.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .glassEffect(reduceTransparency ? .identity : .regular, in: .capsule)
        }
    }

    private var headerSubtitle: String {
        switch store.engine.phase {
        case .idle: "选择一件重要的事，进入自己的节奏。".xikeLocalized
        case .focusing: "保持单点投入，休息提示会在合适的时候出现。".xikeLocalized
        case .microBreak: "短暂离开屏幕，让注意力重新变得清晰。".xikeLocalized
        case .longBreak: "这一轮已经完成，现在安心恢复。".xikeLocalized
        case .awaitingNextCycle: "本轮记录已保存，准备好再继续。".xikeLocalized
        }
    }

    private var dashboardBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(
                colors: [Color.accentColor.opacity(0.11), .clear],
                center: .topLeading,
                startRadius: 30,
                endRadius: 620
            )
            RadialGradient(
                colors: [Color.cyan.opacity(0.055), .clear],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private struct ResumeSessionBanner: View {
    @Bindable var store: AppStore
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "pause.circle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("专注已安全暂停").font(.headline)
                Text("上次退出后的离线时间没有计入本轮。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("结束本轮", role: .destructive) { store.endSession() }
                .buttonStyle(.glass)
            Button("继续") { store.resumeSession() }
                .buttonStyle(.glassProminent).tint(.accentColor)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(reduceTransparency ? AnyShapeStyle(.background) : AnyShapeStyle(.regularMaterial))
        }
    }
}

private struct ActiveTasksCard: View {
    @Bindable var store: AppStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("接下来").font(.headline)
                Spacer()
                Button("全部任务", systemImage: "chevron.right") { openWindow(id: "tasks") }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.plain)
                    .font(.caption)
            }

            if store.tasks.activeTasks.isEmpty {
                ContentUnavailableView(
                    "暂无待办",
                    systemImage: "checkmark.circle",
                    description: Text("新建任务，或直接填写本轮目标。")
                )
                .frame(maxWidth: .infinity, minHeight: 78)
            } else {
                ForEach(store.tasks.activeTasks.prefix(3)) { task in
                    Button {
                        store.selectedTaskID = task.id
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: store.selectedTaskID == task.id ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(store.selectedTaskID == task.id ? Color.accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title).lineLimit(1)
                                Text(taskSubtitle(task)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(reduceTransparency ? AnyShapeStyle(.background) : AnyShapeStyle(.regularMaterial))
        }
    }

    private func taskSubtitle(_ task: TaskItem) -> String {
        [task.tag, task.estimatedMinutes.map { XikeText.format("%lld 分钟", $0) }]
            .compactMap { $0 }
            .joined(separator: " · ")
            .nonEmpty ?? "未设置标签和预计时长".xikeLocalized
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
