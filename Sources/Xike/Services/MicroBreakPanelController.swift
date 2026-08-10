import AppKit
import Combine
import SwiftUI

private enum BreakOverlayKind {
    case microBreak
    case longBreakStart
    case longBreakComplete
}

@MainActor
private final class MicroBreakPresentation: ObservableObject {
    @Published var kind: BreakOverlayKind = .microBreak
    @Published var isShowingCountdown = false
    @Published var remainingSeconds = 0
    @Published var title = "短休息开始"
    @Published var message = "请暂时离开屏幕，让眼睛和肩颈放松一下。"
    @Published var primaryButtonTitle: String?
    @Published var secondaryButtonTitle: String?
}

private final class NonActivatingMicroBreakPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class FirstMouseHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A single, non-activating panel that is retained for the lifetime of the app.
/// The session engine owns all timing; this bridge only projects it onto the
/// display currently under the mouse.
@MainActor
final class MicroBreakPanelController: NSObject {
    static let defaultSize = CGSize(width: 400, height: 300)

    private let presentation = MicroBreakPresentation()
    private var panel: NSPanel?
    private var primaryHandler: (@MainActor () -> Void)?
    private var secondaryHandler: (@MainActor () -> Void)?
    private var presentationGeneration = 0
    private var autoDismissTask: Task<Void, Never>?

    var isVisible: Bool { panel?.isVisible == true }

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func showMicroBreak(
        isShowingCountdown: Bool,
        remainingSeconds: Int,
        onSkip: @escaping @MainActor () -> Void
    ) {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        primaryHandler = onSkip
        secondaryHandler = nil
        presentation.kind = .microBreak
        presentation.isShowingCountdown = isShowingCountdown
        presentation.remainingSeconds = max(remainingSeconds, 0)
        presentation.title = "短休息开始"
        presentation.message = "请暂时离开屏幕，让眼睛和肩颈放松一下。"
        presentation.primaryButtonTitle = "跳过"
        presentation.secondaryButtonTitle = nil
        showPanel()
    }

    /// Announces a long break without changing the long-break timer itself.
    func showLongBreak(duration: Duration = .seconds(5)) {
        autoDismissTask?.cancel()
        primaryHandler = nil
        secondaryHandler = nil
        presentation.kind = .longBreakStart
        presentation.isShowingCountdown = false
        presentation.remainingSeconds = 0
        presentation.title = "长休息开始"
        presentation.message = "离开屏幕，好好恢复。"
        presentation.primaryButtonTitle = nil
        presentation.secondaryButtonTitle = nil
        showPanel()

        autoDismissTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: duration)
            } catch {
                return
            }
            self?.dismiss()
        }
    }

    /// Keeps the completion decision visible until the user explicitly starts
    /// the next focus cycle or ends this one.
    func showLongBreakCompletion(
        onStartNextFocus: @escaping @MainActor () -> Void,
        onEndFocus: @escaping @MainActor () -> Void
    ) {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        primaryHandler = onStartNextFocus
        secondaryHandler = onEndFocus
        presentation.kind = .longBreakComplete
        presentation.isShowingCountdown = false
        presentation.remainingSeconds = 0
        presentation.title = "长休息结束"
        presentation.message = "恢复得怎么样？由你决定下一步。"
        presentation.primaryButtonTitle = "开始下一次专注"
        presentation.secondaryButtonTitle = "结束专注"
        showPanel()
    }

    private func showPanel() {
        let panel = ensurePanel()
        presentationGeneration += 1
        let shouldAnimateIn = !panel.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = shouldAnimateIn ? 0 : 1
        center(panel, on: preferredScreen())
        panel.orderFrontRegardless()
        if shouldAnimateIn {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24
                panel.animator().alphaValue = 1
            }
        }

        // Reasserting order on the next run loop fixes the race where a Space
        // switch or full-screen app claims frontmost status at the same moment.
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, let panel, panel.isVisible else { return }
            self.center(panel, on: self.preferredScreen())
            panel.orderFrontRegardless()
        }
    }

    /// Presentation-only update; it never advances or completes the session.
    func updateMicroBreak(isShowingCountdown: Bool, remainingSeconds: Int) {
        presentation.isShowingCountdown = isShowingCountdown
        presentation.remainingSeconds = max(remainingSeconds, 0)
    }

    func performPrimaryAction() {
        guard isVisible, let handler = primaryHandler else { return }
        dismiss()
        handler()
    }

    func performSecondaryAction() {
        guard isVisible, let handler = secondaryHandler else { return }
        dismiss()
        handler()
    }

    func dismiss(animated: Bool = true) {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        guard let panel else {
            primaryHandler = nil
            secondaryHandler = nil
            return
        }

        primaryHandler = nil
        secondaryHandler = nil
        presentationGeneration += 1
        let dismissGeneration = presentationGeneration
        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.20
                panel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                Task { @MainActor in
                    self?.completeAnimatedDismiss(generation: dismissGeneration)
                }
            }
        } else {
            panel.orderOut(nil)
            panel.alphaValue = 1
        }
    }

    func recenter() {
        guard let panel, panel.isVisible else { return }
        center(panel, on: preferredScreen())
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        recenter()
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = makePanel()
        let view = MicroBreakPanelView(
            presentation: presentation,
            onPrimaryAction: { [weak self] in self?.performPrimaryAction() },
            onSecondaryAction: { [weak self] in self?.performSecondaryAction() }
        )
        let hostingView = FirstMouseHostingView(rootView: AnyView(view))
        hostingView.frame = CGRect(origin: .zero, size: Self.defaultSize)
        panel.contentView = hostingView
        panel.setContentSize(Self.defaultSize)
        self.panel = panel
        return panel
    }

    private func makePanel() -> NSPanel {
        let panel = NonActivatingMicroBreakPanel(
            contentRect: CGRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .utilityWindow
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = false
        panel.setAccessibilityLabel("短休息")
        return panel
    }

    private func completeAnimatedDismiss(generation: Int) {
        guard generation == presentationGeneration else { return }
        panel?.orderOut(nil)
        panel?.alphaValue = 1
    }

    private func preferredScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSApp.keyWindow?.screen
            ?? NSApp.mainWindow?.screen
            ?? NSScreen.main
    }

    private func center(_ panel: NSPanel, on screen: NSScreen?) {
        guard let screen else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(CGPoint(x: frame.midX - panel.frame.width / 2, y: frame.midY - panel.frame.height / 2))
    }
}

private struct MicroBreakPanelView: View {
    @ObservedObject var presentation: MicroBreakPresentation
    let onPrimaryAction: () -> Void
    let onSecondaryAction: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            VStack(spacing: 16) {
                Image(systemName: symbolName)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(symbolColor)

                Text(displayTitle)
                    .font(.title2.weight(.semibold))

                if presentation.isShowingCountdown {
                    Text("\(presentation.remainingSeconds)")
                        .font(.system(size: 68, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .accessibilityLabel("剩余 \(presentation.remainingSeconds) 秒")
                }

                Text(presentation.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let primaryButtonTitle = presentation.primaryButtonTitle {
                    HStack(spacing: 10) {
                        if let secondaryButtonTitle = presentation.secondaryButtonTitle {
                            Button(secondaryButtonTitle, action: onSecondaryAction)
                                .buttonStyle(.glass)
                        }
                        if presentation.kind == .longBreakComplete {
                            Button(primaryButtonTitle, action: onPrimaryAction)
                                .buttonStyle(.glassProminent)
                                .tint(.accentColor)
                        } else {
                            Button(primaryButtonTitle, action: onPrimaryAction)
                                .buttonStyle(.glass)
                        }
                    }
                    .controlSize(.regular)
                    .accessibilityHint(buttonAccessibilityHint)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(1)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: presentation.isShowingCountdown)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor))
                }
            }
            .glassEffect(reduceTransparency ? .identity : .regular, in: .rect(cornerRadius: 28))
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityTitle)
    }

    private var displayTitle: String {
        presentation.isShowingCountdown ? "短休息" : presentation.title
    }

    private var symbolName: String {
        switch presentation.kind {
        case .microBreak: presentation.isShowingCountdown ? "wind" : "sparkles"
        case .longBreakStart: "cup.and.saucer.fill"
        case .longBreakComplete: "checkmark.circle.fill"
        }
    }

    private var symbolColor: Color {
        switch presentation.kind {
        case .microBreak: presentation.isShowingCountdown ? .mint : .accentColor
        case .longBreakStart: .cyan
        case .longBreakComplete: .green
        }
    }

    private var accessibilityTitle: String {
        switch presentation.kind {
        case .microBreak: presentation.isShowingCountdown ? "短休息倒计时" : "短休息开始"
        case .longBreakStart: "长休息开始"
        case .longBreakComplete: "长休息结束，请决定下一步"
        }
    }

    private var buttonAccessibilityHint: String {
        presentation.kind == .longBreakComplete
            ? "选择开始下一次专注或结束专注"
            : "立即结束本次短休息"
    }
}
