import SwiftUI

struct TimerCardView: View {
    @Bindable var store: AppStore

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var displayedTime: TimeInterval {
        switch store.engine.phase {
        case .idle:
            store.preferences.configuration.focusDuration
        case .awaitingNextCycle:
            0
        case .microBreak:
            store.engine.microBreakCountdownRemaining(at: store.displayDate)
        case .focusing, .longBreak:
            store.remainingTime
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            phaseHeader
            timer
            controls
        }
        .padding(34)
        .frame(maxWidth: .infinity, minHeight: 430)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(.background)
            }
        }
        .glassEffect(reduceTransparency ? .identity : .regular, in: .rect(cornerRadius: 34))
        .confirmationDialog(
            "结束当前这一轮？",
            isPresented: $store.showEndConfirmation
        ) {
            Button("结束并记录为中止", role: .destructive) {
                store.endSession()
            }
            Button("继续专注", role: .cancel) {}
        } message: {
            Text("已完成的时间与微休息记录会保留。")
        }
    }

    private var phaseHeader: some View {
        VStack(spacing: 9) {
            Label(store.phaseTitle, systemImage: store.statusSystemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(store.engine.phase == .microBreak ? .mint : .primary)
            Text(store.phaseSubtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var timer: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.12), lineWidth: 8)
            Circle()
                .trim(from: 0, to: store.phaseProgress)
                .stroke(
                    progressColor,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: store.phaseProgress)

            VStack(spacing: 7) {
                Text(TimeDisplay.clock(displayedTime))
                    .font(.system(size: 62, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
                    .accessibilityLabel(TimeDisplay.accessibilityDuration(displayedTime))

                if store.engine.phase == .microBreak {
                    Text(store.isMicroBreakIntro ? "短休息即将开始" : "第 \(store.engine.microBreaksTriggered) 次短休息")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else if store.engine.phase == .focusing {
                    Text("已完成 \(store.engine.microBreaksCompleted) 次短休息")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: 228, height: 228)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            primaryControl

            if store.engine.canEnd {
                if store.engine.phase == .longBreak, !store.engine.isPaused {
                    Button("结束休息", systemImage: "forward.end.fill") {
                        store.skipLongBreak()
                    }
                    .buttonStyle(.glass)
                    .accessibilityHint("结束长休息，决定是否开始下一轮专注")
                } else {
                    Button("结束", systemImage: "stop.fill") {
                        store.requestEndSession()
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .controlSize(.large)
    }

    @ViewBuilder
    private var primaryControl: some View {
        if store.engine.canStart {
            Button("开始专注", systemImage: "play.fill") {
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
    }

    private var progressColor: Color {
        switch store.engine.phase {
        case .microBreak: .mint
        case .longBreak: .cyan
        case .awaitingNextCycle: .green
        case .idle, .focusing: .accentColor
        }
    }
}
