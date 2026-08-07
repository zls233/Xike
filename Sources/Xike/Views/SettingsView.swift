import SwiftUI

struct SettingsView: View {
    @Bindable var store: AppStore

    var body: some View {
        TabView {
            timingSettings
                .tabItem { Label("节律", systemImage: "timer") }
            soundSettings
                .tabItem { Label("声音", systemImage: "speaker.wave.2") }
            generalSettings
                .tabItem { Label("通用", systemImage: "gearshape") }
            dataSettings
                .tabItem { Label("数据", systemImage: "chart.bar") }
        }
        .frame(width: 560, height: 440)
        .scenePadding()
        .confirmationDialog(
            "清除全部专注记录？",
            isPresented: $store.showHistoryClearConfirmation
        ) {
            Button("永久清除", role: .destructive) {
                store.history.clearAll()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作无法撤销，不会影响当前计时和设置。")
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

    private var timingSettings: some View {
        Form {
            Section("周期") {
                Stepper(
                    "专注 \(store.preferences.configuration.focusMinutes) 分钟",
                    value: focusMinutes,
                    in: FocusConfiguration.focusMinutesRange
                )
                Stepper(
                    "长休息 \(store.preferences.configuration.longBreakMinutes) 分钟",
                    value: longBreakMinutes,
                    in: FocusConfiguration.longBreakMinutesRange
                )
                Stepper(
                    "微休息 \(store.preferences.configuration.microBreakSeconds) 秒",
                    value: microBreakSeconds,
                    in: FocusConfiguration.microBreakSecondsRange
                )
            }

            Section("随机提示间隔") {
                Stepper(
                    "最短 \(store.preferences.configuration.minimumPromptMinutes) 分钟",
                    value: minimumPromptMinutes,
                    in: 1 ... promptMaximumLimit
                )
                Stepper(
                    "最长 \(store.preferences.configuration.maximumPromptMinutes) 分钟",
                    value: maximumPromptMinutes,
                    in: 1 ... promptMaximumLimit
                )
                Text("每次微休息结束后重新随机；最后不足完整微休息时不再提示。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("恢复默认节律") {
                    store.preferences.resetTimingDefaults()
                }
            }
        }
        .formStyle(.grouped)
    }

    private var soundSettings: some View {
        Form {
            Section("播放方式") {
                Picker("提示音", selection: soundMode) {
                    Text("固定一个").tag(SoundSelectionMode.fixed)
                    Text("每次随机").tag(SoundSelectionMode.random)
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("音量")
                    Slider(value: volume, in: 0 ... 1, step: 0.05)
                    Text(store.preferences.configuration.volume, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }
            }

            Section("可用声音") {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(store.soundService.availableSounds) { sound in
                            soundRow(sound)
                        }
                    }
                }
                .frame(height: 225)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            _ = store.soundService.refreshAvailableSounds()
        }
    }

    private var generalSettings: some View {
        Form {
            Section("启动") {
                Toggle(
                    "登录时启动息刻",
                    isOn: Binding(
                        get: { store.preferences.launchAtLogin },
                        set: { store.setLaunchAtLogin($0) }
                    )
                )
                if store.loginItemState == .requiresApproval {
                    HStack {
                        Text("等待系统设置批准")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("打开登录项设置") {
                            store.loginItemService.openSystemSettings()
                        }
                    }
                }
            }

            Section("通知") {
                Toggle(
                    "长休息和恢复提醒",
                    isOn: Binding(
                        get: { store.preferences.notificationsEnabled },
                        set: { enabled in
                            store.preferences.notificationsEnabled = enabled
                            if enabled, store.notificationPermission == .notDetermined {
                                Task { await store.requestNotificationPermission() }
                            }
                        }
                    )
                )
                Text(notificationStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("关于") {
                LabeledContent("名称", value: "息刻")
                LabeledContent("版本", value: "1.0.0")
                LabeledContent("数据", value: "仅保存在这台 Mac")
            }
        }
        .formStyle(.grouped)
    }

    private var dataSettings: some View {
        Form {
            Section("本地记录") {
                LabeledContent("已保存", value: "\(store.history.records.count) 轮")
                Text("记录用于今天和近 7 天摘要，不会上传或同步。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("清除全部记录", role: .destructive) {
                    store.showHistoryClearConfirmation = true
                }
            }

            if let error = store.history.persistenceError {
                Section("存储状态") {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func soundRow(_ sound: SoundOption) -> some View {
        let selected = store.preferences.configuration.selectedSoundIDs.contains(sound.id)
        return HStack(spacing: 10) {
            Button {
                toggleSound(sound.id)
            } label: {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(selected ? "取消选择 \(sound.displayName)" : "选择 \(sound.displayName)")

            VStack(alignment: .leading, spacing: 2) {
                Text(sound.displayName)
                Text(sound.source == .builtIn ? "息刻内置" : "macOS")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("试听", systemImage: "play.circle") {
                store.previewSound(sound.id)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .accessibilityLabel("试听 \(sound.displayName)")
        }
        .padding(.vertical, 5)
        .contentShape(.rect)
    }

    private var promptMaximumLimit: Int {
        min(FocusConfiguration.promptMinutesRange.upperBound, store.preferences.configuration.focusMinutes - 1)
    }

    private var focusMinutes: Binding<Int> {
        configurationBinding(\.focusMinutes) { configuration, newValue in
            configuration.focusMinutes = newValue
            let maximum = min(configuration.maximumPromptMinutes, newValue - 1)
            configuration.maximumPromptMinutes = maximum
            configuration.minimumPromptMinutes = min(configuration.minimumPromptMinutes, maximum)
        }
    }

    private var longBreakMinutes: Binding<Int> {
        configurationBinding(\.longBreakMinutes) { $0.longBreakMinutes = $1 }
    }

    private var microBreakSeconds: Binding<Int> {
        configurationBinding(\.microBreakSeconds) { $0.microBreakSeconds = $1 }
    }

    private var minimumPromptMinutes: Binding<Int> {
        configurationBinding(\.minimumPromptMinutes) { configuration, newValue in
            configuration.minimumPromptMinutes = newValue
            configuration.maximumPromptMinutes = max(configuration.maximumPromptMinutes, newValue)
        }
    }

    private var maximumPromptMinutes: Binding<Int> {
        configurationBinding(\.maximumPromptMinutes) { configuration, newValue in
            configuration.maximumPromptMinutes = newValue
            configuration.minimumPromptMinutes = min(configuration.minimumPromptMinutes, newValue)
        }
    }

    private var volume: Binding<Double> {
        configurationBinding(\.volume) { $0.volume = $1 }
    }

    private var soundMode: Binding<SoundSelectionMode> {
        Binding(
            get: { store.preferences.configuration.soundMode },
            set: { newValue in
                var configuration = store.preferences.configuration
                configuration.soundMode = newValue
                if newValue == .fixed, let first = configuration.selectedSoundIDs.first {
                    configuration.selectedSoundIDs = [first]
                }
                store.preferences.configuration = configuration
            }
        )
    }

    private func configurationBinding<Value>(
        _ keyPath: WritableKeyPath<FocusConfiguration, Value>,
        update: @escaping (inout FocusConfiguration, Value) -> Void
    ) -> Binding<Value> {
        Binding(
            get: { store.preferences.configuration[keyPath: keyPath] },
            set: { newValue in
                var configuration = store.preferences.configuration
                update(&configuration, newValue)
                store.preferences.configuration = configuration
            }
        )
    }

    private func toggleSound(_ id: String) {
        var configuration = store.preferences.configuration
        if configuration.soundMode == .fixed {
            configuration.selectedSoundIDs = [id]
        } else if configuration.selectedSoundIDs.contains(id) {
            guard configuration.selectedSoundIDs.count > 1 else { return }
            configuration.selectedSoundIDs.removeAll { $0 == id }
        } else {
            configuration.selectedSoundIDs.append(id)
        }
        store.preferences.configuration = configuration
    }

    private var notificationStatusText: String {
        switch store.notificationPermission {
        case .notDetermined: "系统尚未询问通知权限。"
        case .denied: "系统通知已关闭；声音和微休息浮层仍会正常工作。"
        case .authorized: "系统通知已允许。"
        }
    }
}
