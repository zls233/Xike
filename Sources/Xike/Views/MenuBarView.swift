import AppKit
import SwiftUI

struct MenuBarView: View {
    @Bindable var store: AppStore

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                MenuBarStatusHeader(store: store)

                if let contextTitle {
                    Label(contextTitle, systemImage: "scope")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .glassEffect(.regular, in: .capsule)
                }

                sessionControls

                quickLinks
                footer
            }
        }
        .padding(16)
        .frame(width: 326)
        .task { store.start() }
    }

    private var sessionControls: some View {
        VStack(spacing: 10) {
            if store.recoverySnapshot != nil {
                sessionButton(
                    "恢复上次专注",
                    systemImage: "arrow.counterclockwise",
                    prominence: .primary,
                    action: showMainWindow
                )
            } else {
                primarySessionControl
                secondarySessionControls
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var primarySessionControl: some View {
        if store.engine.canStart {
            sessionButton("开始专注", systemImage: "play.fill", prominence: .primary) {
                _ = store.startSession()
            }
        } else if store.engine.canResume {
            sessionButton("继续专注", systemImage: "play.fill", prominence: .primary) {
                store.resumeSession()
            }
        } else if store.engine.canPause {
            sessionButton("暂停专注", systemImage: "pause.fill", prominence: .primary) {
                store.pauseSession()
            }
        }
    }

    @ViewBuilder
    private var secondarySessionControls: some View {
        if store.engine.canEnd {
            HStack(spacing: 10) {
                if store.engine.phase == .microBreak, !store.engine.isPaused {
                    sessionButton("跳过短休息", systemImage: "forward.end.fill", prominence: .secondary) {
                        store.skipMicroBreak()
                    }
                } else if store.engine.phase == .longBreak, !store.engine.isPaused {
                    sessionButton("结束长休息", systemImage: "forward.end.fill", prominence: .secondary) {
                        store.skipLongBreak()
                    }
                }
                sessionButton("结束本轮", systemImage: "stop.fill", prominence: .secondary) {
                    store.requestEndSession()
                    showMainWindow()
                }
            }
        }
    }

    private var quickLinks: some View {
        HStack(spacing: 8) {
            quickLink("任务", systemImage: "checklist", windowID: "tasks")
            quickLink("记录", systemImage: "clock.arrow.circlepath", windowID: "history")
            quickLink("主窗口", systemImage: "macwindow", windowID: "main")
        }
    }

    private var footer: some View {
        HStack {
            SettingsLink { Label("设置", systemImage: "gearshape") }
                .buttonStyle(.plain)
            Spacer()
            Button("退出", systemImage: "power") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 2)
    }

    private var contextTitle: String? {
        store.engine.focusContext?.taskTitleSnapshot ?? store.engine.focusContext?.goal
    }

    private enum SessionActionProminence {
        case primary
        case secondary
    }

    @ViewBuilder
    private func sessionButton(
        _ title: String,
        systemImage: String,
        prominence: SessionActionProminence,
        action: @escaping () -> Void
    ) -> some View {
        let labelHeight: CGFloat = prominence == .primary ? 30 : 24
        let labelFont: Font = prominence == .primary
            ? .body.weight(.semibold)
            : .callout.weight(.medium)
        let controlSize: ControlSize = prominence == .primary ? .large : .regular

        let button = Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(labelFont)
                .frame(maxWidth: .infinity)
                .frame(height: labelHeight)
                .contentShape(.rect)
        }
        .buttonBorderShape(.capsule)
        .controlSize(controlSize)

        if prominence == .primary {
            button
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
        } else {
            button.buttonStyle(.glass)
        }
    }

    private func quickLink(_ title: String, systemImage: String, windowID: String) -> some View {
        Button { showWindow(windowID) } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .frame(height: 18)
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .contentShape(.rect)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle)
    }

    private func showMainWindow() {
        showWindow("main")
    }

    private func showWindow(_ id: String) {
        openWindow(id: id)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// The countdown changes every second. Keeping it in a dedicated view avoids
/// rebuilding and remeasuring every glass button in the menu-bar window.
private struct MenuBarStatusHeader: View {
    @Bindable var store: AppStore

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: store.statusSystemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 34, height: 34)
                .glassEffect(.regular.tint(Color.accentColor.opacity(0.14)), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.phaseTitle).font(.headline)
                Text(statusDetail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if store.engine.phase.isRunning {
                Text(TimeDisplay.clock(store.remainingTime))
                    .font(.title3.weight(.medium).monospacedDigit())
                    .lineLimit(1)
                    .frame(width: 58, alignment: .trailing)
                    .accessibilityLabel(TimeDisplay.accessibilityDuration(store.remainingTime))
            }
        }
    }

    private var statusDetail: String {
        if store.engine.isPaused { return "等待你继续" }
        switch store.engine.phase {
        case .idle:
            let config = store.preferences.configuration
            return "\(config.focusMinutes) 分钟 · 提示 \(config.minimumPromptMinutes)–\(config.maximumPromptMinutes) 分钟"
        case .focusing: return "随机提示已开启"
        case .microBreak: return store.isMicroBreakIntro ? "短休息即将开始" : "看看远处"
        case .longBreak: return "离开屏幕"
        case .awaitingNextCycle: return "准备好再开始"
        }
    }
}
