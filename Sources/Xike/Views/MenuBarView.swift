import AppKit
import SwiftUI

struct MenuBarView: View {
    @Bindable var store: AppStore

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: store.engine.phase.systemImage)
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.phaseTitle)
                        .font(.headline)
                    Text(statusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if store.engine.phase.isRunning {
                    Text(TimeDisplay.clock(store.remainingTime))
                        .font(.title3.monospacedDigit())
                        .accessibilityLabel(TimeDisplay.accessibilityDuration(store.remainingTime))
                }
            }

            if store.recoverySnapshot != nil {
                Button("恢复上次专注", systemImage: "arrow.counterclockwise") {
                    showMainWindow()
                }
                .buttonStyle(.glassProminent)
                .frame(maxWidth: .infinity)
            } else {
                sessionControls
            }

            Divider()

            Button("打开息刻", systemImage: "macwindow") {
                showMainWindow()
            }

            SettingsLink {
                Label("设置", systemImage: "gearshape")
            }

            Divider()

            Button("退出息刻", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(18)
        .frame(width: 310)
        .task { store.start() }
    }

    @ViewBuilder
    private var sessionControls: some View {
        HStack(spacing: 10) {
            if store.engine.canStart {
                Button("开始", systemImage: "play.fill") {
                    _ = store.startSession()
                }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
            } else if store.engine.canResume {
                Button("继续", systemImage: "play.fill") {
                    store.resumeSession()
                }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
            } else if store.engine.canPause {
                Button("暂停", systemImage: "pause.fill") {
                    store.pauseSession()
                }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
            }

            if store.engine.canEnd {
                Button("结束", systemImage: "stop.fill") {
                    store.showEndConfirmation = true
                    showMainWindow()
                }
                .buttonStyle(.glass)
            }
        }
        .controlSize(.large)
    }

    private var statusDetail: String {
        if store.engine.isPaused { return "等待你继续" }
        switch store.engine.phase {
        case .idle: return "90 分钟 · 提示 3–5 分钟"
        case .focusing: return "随机提示已开启"
        case .microBreak: return "看看远处"
        case .longBreak: return "离开屏幕"
        case .awaitingNextCycle: return "准备好再开始"
        }
    }

    private func showMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
