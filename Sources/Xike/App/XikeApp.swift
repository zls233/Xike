import AppKit
import AppIntents
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppStore.shared.start()

        if !AppStore.shared.preferences.hasCompletedOnboarding {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let store = AppStore.shared
        guard store.engine.canEnd else { return .terminateNow }

        if store.engine.phase == .longBreak {
            store.skipLongBreak()
            return .terminateNow
        }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "当前专注仍在进行".xikeLocalized
        alert.informativeText = "结束后会把已完成时间记录为中止。".xikeLocalized
        alert.addButton(withTitle: "继续专注".xikeLocalized)
        alert.addButton(withTitle: "结束并退出".xikeLocalized)

        if alert.runModal() == .alertFirstButtonReturn {
            return .terminateCancel
        }

        store.endSession()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppStore.shared.shutdown()
    }
}

@main
@MainActor
struct XikeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let store = AppStore.shared

    var body: some Scene {
        Window("息刻", id: "main") {
            ContentView(store: store)
        }
        .defaultSize(width: 980, height: 680)
        .defaultLaunchBehavior(
            store.preferences.hasCompletedOnboarding ? .suppressed : .presented
        )
        .restorationBehavior(.disabled)
        .commands {
            CommandMenu("专注") {
                Button(primaryCommandTitle, systemImage: primaryCommandImage) {
                    performPrimaryCommand()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!canPerformPrimaryCommand)

                Button("结束本轮", systemImage: "stop.fill") {
                    store.requestEndSession()
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!store.engine.canEnd)

                Button("跳过长休息", systemImage: "forward.end.fill") {
                    store.skipLongBreak()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(store.engine.phase != .longBreak || store.engine.isPaused)

                Divider()
                OpenWindowCommandButton(title: "打开任务", systemImage: "checklist", windowID: "tasks", shortcut: "t")
                OpenWindowCommandButton(title: "打开专注记录", systemImage: "clock.arrow.circlepath", windowID: "history", shortcut: "h")
            }
        }

        Window("任务", id: "tasks") {
            TasksView(store: store)
        }
        .defaultSize(width: 900, height: 620)

        Window("专注记录", id: "history") {
            HistoryView(store: store)
        }
        .defaultSize(width: 780, height: 560)

        MenuBarExtra {
            MenuBarView(store: store)
        } label: {
            Label("息刻", systemImage: store.statusSystemImage)
                .accessibilityLabel("息刻，\(store.phaseTitle)")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store)
        }
        .onChange(of: store.preferences.configuration) { _, _ in
            XikeFocusFilterIntent.invalidateFocusFilterAppContext()
        }
    }

    private var primaryCommandTitle: String {
        if store.engine.canPause { return "暂停".xikeLocalized }
        if store.engine.canResume { return "继续".xikeLocalized }
        return "开始专注".xikeLocalized
    }

    private var primaryCommandImage: String {
        store.engine.canPause ? "pause.fill" : "play.fill"
    }

    private var canPerformPrimaryCommand: Bool {
        store.engine.canStart || store.engine.canPause || store.engine.canResume
    }

    private func performPrimaryCommand() {
        if store.engine.canPause {
            store.pauseSession()
        } else if store.engine.canResume {
            store.resumeSession()
        } else if store.engine.canStart {
            _ = store.startSession()
        }
    }
}

private struct OpenWindowCommandButton: View {
    let title: String
    let systemImage: String
    let windowID: String
    let shortcut: KeyEquivalent
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(title, systemImage: systemImage) {
            openWindow(id: windowID)
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(shortcut, modifiers: [.command, .shift])
    }
}
