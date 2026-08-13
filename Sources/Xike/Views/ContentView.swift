import SwiftUI

struct ContentView: View {
    @Bindable var store: AppStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if store.preferences.hasCompletedOnboarding {
                DashboardView(store: store)
            } else {
                OnboardingView(store: store)
            }
        }
        .task { store.start() }
        .onReceive(NotificationCenter.default.publisher(for: .openXikeWindow)) { notification in
            if let id = notification.object as? String { openWindow(id: id) }
        }
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

}
