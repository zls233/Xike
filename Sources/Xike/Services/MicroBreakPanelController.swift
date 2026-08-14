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
    @Published var title = "短休息开始".xikeLocalized
    @Published var message = "请暂时离开屏幕，让眼睛和肩颈放松一下。".xikeLocalized
    @Published var primaryButtonTitle: String?
    @Published var secondaryButtonTitle: String?
    @Published var showsActions = false
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
    static let compactSize = CGSize(width: 420, height: 112)
    static let microBreakActionSize = CGSize(width: 420, height: 158)
    static let decisionSize = CGSize(width: 420, height: 190)

    private let presentation = MicroBreakPresentation()
    private var panel: NSPanel?
    private var primaryHandler: (@MainActor () -> Void)?
    private var secondaryHandler: (@MainActor () -> Void)?
    private var presentationGeneration = 0
    private var autoDismissTask: Task<Void, Never>?
    private var visibilityRepairTask: Task<Void, Never>?
    private var hoverTransitionTask: Task<Void, Never>?
    private var entranceTask: Task<Void, Never>?
    private var isPointerInside = false
    private var acceptsHoverExpansion = false
    private var isEnabled = true
    private var position: BreakOverlayPosition = .topTrailing

    var isVisible: Bool { panel?.isVisible == true }

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceDidChange(_:)),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func configure(isEnabled: Bool, position: BreakOverlayPosition) {
        self.isEnabled = isEnabled
        self.position = position
        if !isEnabled {
            dismiss(animated: false)
        } else {
            reposition()
        }
    }

    func showMicroBreak(
        isShowingCountdown: Bool,
        remainingSeconds: Int,
        onSkip: @escaping @MainActor () -> Void
    ) {
        guard isEnabled else { return }
        autoDismissTask?.cancel()
        autoDismissTask = nil
        primaryHandler = onSkip
        secondaryHandler = nil
        presentation.kind = .microBreak
        presentation.isShowingCountdown = isShowingCountdown
        presentation.remainingSeconds = max(remainingSeconds, 0)
        presentation.title = "短休息开始".xikeLocalized
        presentation.message = "请暂时离开屏幕，让眼睛和肩颈放松一下。".xikeLocalized
        presentation.primaryButtonTitle = "跳过".xikeLocalized
        presentation.secondaryButtonTitle = nil
        presentation.showsActions = false
        showPanel()
    }

    /// Announces a long break without changing the long-break timer itself.
    func showLongBreak(duration: Duration = .seconds(5)) {
        guard isEnabled else { return }
        autoDismissTask?.cancel()
        primaryHandler = nil
        secondaryHandler = nil
        presentation.kind = .longBreakStart
        presentation.isShowingCountdown = false
        presentation.remainingSeconds = 0
        presentation.title = "长休息开始".xikeLocalized
        presentation.message = "离开屏幕，好好恢复。".xikeLocalized
        presentation.primaryButtonTitle = nil
        presentation.secondaryButtonTitle = nil
        presentation.showsActions = false
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
        guard isEnabled else { return }
        autoDismissTask?.cancel()
        autoDismissTask = nil
        primaryHandler = onStartNextFocus
        secondaryHandler = onEndFocus
        presentation.kind = .longBreakComplete
        presentation.isShowingCountdown = false
        presentation.remainingSeconds = 0
        presentation.title = "长休息结束".xikeLocalized
        presentation.message = "恢复得怎么样？由你决定下一步。".xikeLocalized
        presentation.primaryButtonTitle = "开始下一次专注".xikeLocalized
        presentation.secondaryButtonTitle = "结束专注".xikeLocalized
        presentation.showsActions = false
        showPanel()
    }

    func showPreview(duration: Duration = .seconds(3)) {
        guard isEnabled else { return }
        autoDismissTask?.cancel()
        primaryHandler = { [weak self] in self?.dismiss() }
        secondaryHandler = nil
        presentation.kind = .microBreak
        presentation.isShowingCountdown = true
        presentation.remainingSeconds = 10
        presentation.title = "短休息".xikeLocalized
        presentation.message = "望向远处，放松肩颈".xikeLocalized
        presentation.primaryButtonTitle = "跳过".xikeLocalized
        presentation.secondaryButtonTitle = nil
        presentation.showsActions = false
        showPanel()

        autoDismissTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: duration) } catch { return }
            self?.dismiss()
        }
    }

    private func showPanel() {
        hoverTransitionTask?.cancel()
        hoverTransitionTask = nil
        entranceTask?.cancel()
        entranceTask = nil
        isPointerInside = false
        acceptsHoverExpansion = false
        let panel = ensurePanel()
        panel.setContentSize(Self.compactSize)
        presentationGeneration += 1
        let generation = presentationGeneration
        let shouldAnimateIn = !panel.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = shouldAnimateIn ? 0 : 1
        place(panel, on: preferredScreen())
        panel.orderFrontRegardless()
        if shouldAnimateIn {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24
                panel.animator().alphaValue = 1
            }
        }

        isPointerInside = panel.frame.contains(NSEvent.mouseLocation)
        if shouldAnimateIn {
            // Do not let a hover event mutate the panel while its entrance
            // fade is still running. Overlapping those transitions caused the
            // content jump seen when the pointer was already over the panel.
            entranceTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                guard let self,
                      self.presentationGeneration == generation,
                      self.panel?.isVisible == true
                else { return }
                self.acceptsHoverExpansion = true
                if self.isPointerInside {
                    self.expandForActions()
                }
            }
        } else {
            acceptsHoverExpansion = true
            if isPointerInside {
                expandForActions()
            }
        }

        // Full-screen transitions can claim their Space a moment after the
        // timer event. Reassert the public overlay behavior after that race.
        visibilityRepairTask?.cancel()
        visibilityRepairTask = Task { @MainActor [weak self, weak panel] in
            for delay in [Duration.milliseconds(80), .milliseconds(320)] {
                do { try await Task.sleep(for: delay) } catch { return }
                guard let self,
                      let panel,
                      panel.isVisible,
                      self.presentationGeneration == generation
                else { return }
                self.place(panel, on: self.preferredScreen())
                panel.orderFrontRegardless()
            }
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
        visibilityRepairTask?.cancel()
        visibilityRepairTask = nil
        hoverTransitionTask?.cancel()
        hoverTransitionTask = nil
        entranceTask?.cancel()
        entranceTask = nil
        isPointerInside = false
        acceptsHoverExpansion = false
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

    func reposition() {
        guard let panel, panel.isVisible else { return }
        place(panel, on: preferredScreen())
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        reposition()
    }

    @objc private func activeSpaceDidChange(_ notification: Notification) {
        guard let panel, panel.isVisible else { return }
        place(panel, on: preferredScreen())
        panel.orderFrontRegardless()
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = makePanel()
        let view = MicroBreakPanelView(
            presentation: presentation,
            onPrimaryAction: { [weak self] in self?.performPrimaryAction() },
            onSecondaryAction: { [weak self] in self?.performSecondaryAction() },
            onHoverChange: { [weak self] isHovering in
                self?.setActionsExpanded(isHovering)
            }
        )
        let hostingView = FirstMouseHostingView(rootView: AnyView(view))
        hostingView.frame = CGRect(origin: .zero, size: Self.compactSize)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        panel.setContentSize(Self.compactSize)
        self.panel = panel
        return panel
    }

    private func makePanel() -> NSPanel {
        let panel = NonActivatingMicroBreakPanel(
            contentRect: CGRect(origin: .zero, size: Self.compactSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .canJoinAllApplications,
            .transient,
            .ignoresCycle,
        ]
        panel.animationBehavior = .none
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = false
        panel.sharingType = .none
        panel.setAccessibilityLabel("短休息".xikeLocalized)
        return panel
    }

    private func completeAnimatedDismiss(generation: Int) {
        guard generation == presentationGeneration else { return }
        panel?.orderOut(nil)
        panel?.alphaValue = 1
    }

    private func setActionsExpanded(_ isExpanded: Bool) {
        guard presentation.primaryButtonTitle != nil else { return }
        isPointerInside = isExpanded
        guard acceptsHoverExpansion else { return }
        hoverTransitionTask?.cancel()
        hoverTransitionTask = nil

        if isExpanded {
            expandForActions()
        } else {
            collapseActionsAfterPointerExit()
        }
    }

    private func expandForActions() {
        guard let panel, panel.isVisible else { return }
        let targetSize = presentation.kind == .longBreakComplete
            ? Self.decisionSize
            : Self.microBreakActionSize

        presentation.showsActions = false
        resize(panel, to: targetSize, animated: true) { [weak self] in
            guard let self,
                  self.acceptsHoverExpansion,
                  self.isPointerInside,
                  self.panel?.isVisible == true
            else { return }
            self.presentation.showsActions = true
        }
    }

    private func collapseActionsAfterPointerExit() {
        presentation.showsActions = false

        let delay: Duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .zero
            : .milliseconds(70)
        hoverTransitionTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self,
                  !self.isPointerInside,
                  let panel = self.panel,
                  panel.isVisible
            else { return }
            self.resize(panel, to: Self.compactSize, animated: true)
        }
    }

    private func resize(
        _ panel: NSPanel,
        to targetSize: CGSize,
        animated: Bool,
        completion: (@MainActor () -> Void)? = nil
    ) {
        let screen = panel.screen ?? preferredScreen()
        let targetFrame = CGRect(
            origin: position.origin(panelSize: targetSize, in: screen?.visibleFrame ?? panel.screen?.visibleFrame ?? panel.frame),
            size: targetSize
        )

        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.setFrame(targetFrame, display: true)
            completion?()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(targetFrame, display: true)
        } completionHandler: {
            Task { @MainActor in completion?() }
        }
    }

    private func preferredScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSApp.keyWindow?.screen
            ?? NSApp.mainWindow?.screen
            ?? NSScreen.main
    }

    private func place(_ panel: NSPanel, on screen: NSScreen?) {
        guard let screen else { return }
        panel.setFrameOrigin(position.origin(panelSize: panel.frame.size, in: screen.visibleFrame))
    }
}

private struct MicroBreakPanelView: View {
    private enum DecisionAction: Hashable {
        case endFocus
        case startNextFocus
    }

    @ObservedObject var presentation: MicroBreakPresentation
    let onPrimaryAction: () -> Void
    let onSecondaryAction: () -> Void
    let onHoverChange: (Bool) -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredDecision: DecisionAction?
    @State private var isSkipHovered = false

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: symbolName)
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(symbolColor)
                        .frame(width: 48, height: 48)
                        .glassEffect(
                            reduceTransparency ? .identity : .regular.tint(symbolColor.opacity(0.16)),
                            in: .circle
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(displayTitle)
                            .font(.headline)
                        Text(presentation.message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)

                    Spacer(minLength: 8)

                    if presentation.isShowingCountdown {
                        Text("\(presentation.remainingSeconds)")
                            .font(.system(size: 42, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .frame(width: 82, alignment: .trailing)
                            .layoutPriority(2)
                            .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
                            .accessibilityLabel(XikeText.format("剩余 %lld 秒", presentation.remainingSeconds))
                    } else if presentation.kind != .longBreakComplete {
                        Image(systemName: "checkmark")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .frame(height: MicroBreakPanelController.compactSize.height - 18)

                if presentation.showsActions, presentation.kind == .longBreakComplete {
                    HStack(spacing: 8) {
                        if let secondaryButtonTitle = presentation.secondaryButtonTitle {
                            decisionButton(
                                secondaryButtonTitle,
                                systemImage: "stop.fill",
                                actionKind: .endFocus,
                                isPrimary: false,
                                action: onSecondaryAction
                            )
                        }
                        if let primaryButtonTitle = presentation.primaryButtonTitle {
                            decisionButton(
                                primaryButtonTitle,
                                systemImage: "play.fill",
                                actionKind: .startNextFocus,
                                isPrimary: true,
                                action: onPrimaryAction
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity)
                    .transition(.opacity)
                    .accessibilityHint(buttonAccessibilityHint)
                } else if presentation.showsActions,
                          let primaryButtonTitle = presentation.primaryButtonTitle {
                    HStack {
                        Spacer(minLength: 0)
                        Button(action: onPrimaryAction) {
                            Label(primaryButtonTitle, systemImage: "forward.end.fill")
                                .font(.callout.weight(.semibold))
                                .frame(minWidth: 108)
                                .frame(height: 32)
                                .contentShape(.rect)
                        }
                            .buttonStyle(.plain)
                            .foregroundStyle(.white)
                            .background {
                                Capsule().fill(Color.orange.gradient)
                            }
                            .overlay {
                                Capsule()
                                    .stroke(.white.opacity(0.28), lineWidth: 1)
                            }
                            .shadow(color: Color.orange.opacity(0.34), radius: 7, y: 2)
                            .scaleEffect(isSkipHovered ? 1.03 : 1)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isSkipHovered)
                            .onHover { isSkipHovered = $0 }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
                    .frame(maxHeight: .infinity)
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: presentation.isShowingCountdown)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: presentation.showsActions)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor))
                }
            }
            .glassEffect(reduceTransparency ? .identity : .regular, in: .rect(cornerRadius: 26))
        }
        .padding(9)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onHover(perform: onHoverChange)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityTitle)
    }

    @ViewBuilder
    private func decisionButton(
        _ title: String,
        systemImage: String,
        actionKind: DecisionAction,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let isHovered = hoveredDecision == actionKind
        let actionColor: Color = isPrimary ? .green : .orange
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.callout.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background {
            Capsule().fill(actionColor.gradient)
        }
        .overlay {
            Capsule()
                .stroke(.white.opacity(isHovered ? 0.40 : 0.24), lineWidth: 1)
        }
        .shadow(
            color: actionColor.opacity(isHovered ? 0.46 : 0.30),
            radius: isHovered ? 10 : 7,
            y: isHovered ? 3 : 2
        )
        .scaleEffect(isHovered ? 1.03 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovered)
        .onHover { isHovered in
            hoveredDecision = isHovered ? actionKind : nil
        }
    }

    private var displayTitle: String {
        presentation.isShowingCountdown ? "短休息".xikeLocalized : presentation.title
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
        case .microBreak: presentation.isShowingCountdown ? "短休息倒计时".xikeLocalized : "短休息开始".xikeLocalized
        case .longBreakStart: "长休息开始".xikeLocalized
        case .longBreakComplete: "长休息结束，请决定下一步".xikeLocalized
        }
    }

    private var buttonAccessibilityHint: String {
        presentation.kind == .longBreakComplete
            ? "选择开始下一次专注或结束专注".xikeLocalized
            : "立即结束本次短休息".xikeLocalized
    }
}
