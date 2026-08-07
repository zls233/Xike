import AppKit
import Combine
import SwiftUI

@MainActor
private final class MicroBreakPresentation: ObservableObject {
    @Published var remainingSeconds: Int
    @Published var title: String
    @Published var message: String

    init(remainingSeconds: Int, title: String, message: String) {
        self.remainingSeconds = remainingSeconds
        self.title = title
        self.message = message
    }
}

private final class NonActivatingMicroBreakPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The one AppKit bridge needed by Xike: a non-activating panel above full-screen spaces.
/// Session phase and countdown truth remain outside this controller.
@MainActor
final class MicroBreakPanelController: NSObject {
    static let defaultSize = CGSize(width: 380, height: 280)

    private var panel: NSPanel?
    private var presentation: MicroBreakPresentation?
    private var skipHandler: (@MainActor () -> Void)?
    private var presentationGeneration = 0

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

    /// Presents arbitrary SwiftUI content. A standard skip action can be appended by the bridge.
    func show(
        content: AnyView,
        size: CGSize = defaultSize,
        showsStandardSkipButton: Bool = false,
        onSkip: @escaping @MainActor () -> Void
    ) {
        presentation = nil
        skipHandler = onSkip

        let rootView: AnyView
        if showsStandardSkipButton {
            rootView = AnyView(
                StandardPanelWrapper(content: content) { [weak self] in
                    self?.skip()
                }
            )
        } else {
            rootView = content
        }

        present(rootView: rootView, size: size)
    }

    /// Presents Xike's built-in micro-break UI. Update its number from the external session engine.
    func showMicroBreak(
        remainingSeconds: Int,
        title: String = "休息一下",
        message: String = "放松肩颈，望向远处，慢慢呼吸。",
        onSkip: @escaping @MainActor () -> Void
    ) {
        let presentation = MicroBreakPresentation(
            remainingSeconds: max(remainingSeconds, 0),
            title: title,
            message: message
        )
        self.presentation = presentation
        skipHandler = onSkip

        let view = MicroBreakPanelView(presentation: presentation) { [weak self] in
            self?.skip()
        }
        present(rootView: AnyView(view), size: Self.defaultSize)
    }

    /// Presentation-only update; it does not advance or complete the session.
    func updateMicroBreak(
        remainingSeconds: Int,
        title: String? = nil,
        message: String? = nil
    ) {
        presentation?.remainingSeconds = max(remainingSeconds, 0)
        if let title { presentation?.title = title }
        if let message { presentation?.message = message }
    }

    func skip() {
        guard isVisible, let handler = skipHandler else { return }
        dismiss()
        handler()
    }

    func dismiss(animated: Bool = true) {
        guard let panel else {
            skipHandler = nil
            presentation = nil
            return
        }

        skipHandler = nil
        presentation = nil
        presentationGeneration += 1
        let dismissGeneration = presentationGeneration

        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
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

    /// Re-centers an already visible panel after a display arrangement change.
    func recenter() {
        guard let panel, panel.isVisible else { return }
        center(panel, on: preferredScreen())
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        recenter()
    }

    private func present(rootView: AnyView, size: CGSize) {
        let panel = panel ?? makePanel()
        self.panel = panel
        presentationGeneration += 1

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = CGRect(origin: .zero, size: size)
        panel.contentView = hostingView
        panel.setContentSize(size)
        center(panel, on: preferredScreen())
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NonActivatingMicroBreakPanel(
            contentRect: CGRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        panel.animationBehavior = .utilityWindow
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = false
        panel.setAccessibilityLabel("微休息")
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
        let targetFrame = screen.visibleFrame
        let origin = CGPoint(
            x: targetFrame.midX - panel.frame.width / 2,
            y: targetFrame.midY - panel.frame.height / 2
        )
        panel.setFrameOrigin(origin)
    }
}

private struct StandardPanelWrapper: View {
    let content: AnyView
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            content
            Button("跳过", action: onSkip)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityHint("立即结束本次微休息")
        }
        .padding(20)
    }
}

private struct MicroBreakPanelView: View {
    @ObservedObject var presentation: MicroBreakPresentation
    let onSkip: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            surface
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var surface: some View {
        VStack(spacing: 16) {
            Image(systemName: "eye")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.secondary)

            Text(presentation.title)
                .font(.title2.weight(.semibold))

            Text("\(presentation.remainingSeconds)")
                .font(.system(size: 64, weight: .light, design: .rounded))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())
                .accessibilityLabel("剩余 \(presentation.remainingSeconds) 秒")

            Text(presentation.message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("跳过", action: onSkip)
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityHint("立即结束本次微休息")
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            }
        }
        .glassEffect(
            reduceTransparency ? .identity : .regular,
            in: .rect(cornerRadius: 28)
        )
        .glassEffectID("micro-break", in: glassNamespace)
    }
}
