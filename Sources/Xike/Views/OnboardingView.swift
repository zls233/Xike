import SwiftUI

struct OnboardingView: View {
    @Bindable var store: AppStore

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            ambientBackground

            GlassEffectContainer(spacing: 20) {
                VStack(spacing: 28) {
                    VStack(spacing: 12) {
                        Image(systemName: "circle.hexagongrid.circle.fill")
                            .font(.system(size: 54, weight: .light))
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)

                        Text("欢迎使用息刻")
                            .font(.largeTitle.weight(.semibold))
                        Text("专注不是一直紧绷，而是在恰当的时候松开十秒。")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    HStack(alignment: .top, spacing: 24) {
                        feature(
                            icon: "waveform",
                            title: "随机提示",
                            detail: "默认每 3–5 分钟，用柔和声音提醒你。"
                        )
                        feature(
                            icon: "eye",
                            title: "十秒微休息",
                            detail: "不打断键盘焦点，只邀请你暂时离开屏幕。"
                        )
                        feature(
                            icon: "cup.and.saucer",
                            title: "完整恢复",
                            detail: "90 分钟结束后，进入 20 分钟长休息。"
                        )
                    }

                    VStack(spacing: 14) {
                        Toggle(
                            "允许长休息与恢复提醒",
                            isOn: Binding(
                                get: { store.preferences.notificationsEnabled },
                                set: { store.preferences.notificationsEnabled = $0 }
                            )
                        )
                        .toggleStyle(.switch)

                        HStack(spacing: 12) {
                            Button("试听柔铃", systemImage: "speaker.wave.2") {
                                store.previewSound(FocusConfiguration.defaultSoundID)
                            }
                            .buttonStyle(.glass)

                            Button("开始使用", systemImage: "arrow.right") {
                                Task { await store.completeOnboarding() }
                            }
                            .buttonStyle(.glassProminent)
                            .tint(.accentColor)
                            .keyboardShortcut(.defaultAction)
                        }
                        .controlSize(.large)
                    }
                }
                .padding(42)
                .frame(maxWidth: 760)
                .background {
                    if reduceTransparency {
                        RoundedRectangle(cornerRadius: 38, style: .continuous)
                            .fill(.background)
                    }
                }
                .glassEffect(
                    reduceTransparency ? .identity : .regular,
                    in: .rect(cornerRadius: 38)
                )
            }
            .padding(44)
        }
        .frame(minWidth: 820, minHeight: 620)
    }

    private var ambientBackground: some View {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(0.13),
                Color.mint.opacity(0.07),
                Color.clear,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func feature(icon: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
