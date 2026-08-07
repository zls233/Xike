import SwiftUI

struct ContentView: View {
    @Bindable var store: AppStore

    var body: some View {
        Group {
            if store.preferences.hasCompletedOnboarding {
                dashboard
            } else {
                OnboardingView(store: store)
            }
        }
        .task { store.start() }
        .alert(
            "恢复上次专注？",
            isPresented: Binding(
                get: { store.recoverySnapshot != nil },
                set: { _ in }
            )
        ) {
            Button("恢复为暂停状态") {
                store.restoreSavedSession()
            }
            Button("放弃记录", role: .destructive) {
                store.discardSavedSession()
            }
        } message: {
            Text("离线时间不会计入专注。恢复后由你决定何时继续。")
        }
        .alert(
            "息刻",
            isPresented: Binding(
                get: { store.alertMessage != nil },
                set: { if !$0 { store.clearAlert() } }
            )
        ) {
            Button("好") { store.clearAlert() }
        } message: {
            Text(store.alertMessage ?? "")
        }
    }

    private var dashboard: some View {
        ScrollView {
            VStack(spacing: 18) {
                if store.shouldOfferResume {
                    resumeBanner
                }

                GlassEffectContainer(spacing: 22) {
                    HStack(alignment: .top, spacing: 22) {
                        TimerCardView(store: store)
                            .frame(maxWidth: .infinity)
                        StatisticsView(store: store)
                            .frame(width: 330)
                    }
                }
            }
            .padding(28)
        }
        .background {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.10), .clear, Color.cyan.opacity(0.055)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
        .frame(minWidth: 860, minHeight: 620)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                SettingsLink {
                    Label("设置", systemImage: "gearshape")
                }
            }
        }
    }

    private var resumeBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "pause.circle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("专注已安全暂停")
                    .font(.headline)
                Text("睡眠、锁屏或离线时间没有计入本轮。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("结束本轮", role: .destructive) {
                store.endSession()
            }
            .buttonStyle(.glass)
            Button("继续") {
                store.resumeSession()
            }
            .buttonStyle(.glassProminent)
            .tint(.accentColor)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}
