import Foundation
import Observation

@MainActor
@Observable
final class PreferencesStore {
    private enum Key {
        static let configuration = "preferences.focusConfiguration"
        static let completedOnboarding = "preferences.completedOnboarding"
        static let notificationsEnabled = "preferences.notificationsEnabled"
        static let launchAtLogin = "preferences.launchAtLogin"
        static let globalShortcutEnabled = "preferences.globalShortcutEnabled"
        static let globalShortcut = "preferences.globalShortcut"
        static let breakOverlayEnabled = "preferences.breakOverlayEnabled"
        static let breakOverlayPosition = "preferences.breakOverlayPosition"
    }

    var configuration: FocusConfiguration {
        didSet { persistConfiguration() }
    }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.completedOnboarding) }
    }

    var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) }
    }

    var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }

    var globalShortcutEnabled: Bool {
        didSet { defaults.set(globalShortcutEnabled, forKey: Key.globalShortcutEnabled) }
    }

    var globalShortcut: GlobalShortcut {
        didSet { defaults.set(globalShortcut.rawValue, forKey: Key.globalShortcut) }
    }

    var breakOverlayEnabled: Bool {
        didSet { defaults.set(breakOverlayEnabled, forKey: Key.breakOverlayEnabled) }
    }

    var breakOverlayPosition: BreakOverlayPosition {
        didSet { defaults.set(breakOverlayPosition.rawValue, forKey: Key.breakOverlayPosition) }
    }

    @ObservationIgnored
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Key.configuration),
           let decoded = try? JSONDecoder().decode(FocusConfiguration.self, from: data),
           decoded.isValid
        {
            configuration = decoded
        } else {
            configuration = .default
        }
        hasCompletedOnboarding = defaults.bool(forKey: Key.completedOnboarding)
        notificationsEnabled = defaults.object(forKey: Key.notificationsEnabled) as? Bool ?? true
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        globalShortcutEnabled = defaults.object(forKey: Key.globalShortcutEnabled) as? Bool ?? true
        globalShortcut = defaults.string(forKey: Key.globalShortcut).flatMap(GlobalShortcut.init(rawValue:)) ?? .commandOptionReturn
        breakOverlayEnabled = defaults.object(forKey: Key.breakOverlayEnabled) as? Bool ?? true
        breakOverlayPosition = defaults.string(forKey: Key.breakOverlayPosition)
            .flatMap(BreakOverlayPosition.init(rawValue:)) ?? .topTrailing
    }

    func resetTimingDefaults() {
        let soundMode = configuration.soundMode
        let selectedSoundIDs = configuration.selectedSoundIDs
        let volume = configuration.volume
        configuration = .default
        configuration.soundMode = soundMode
        configuration.selectedSoundIDs = selectedSoundIDs
        configuration.volume = volume
    }

    func markOnboardingCompleted() {
        hasCompletedOnboarding = true
    }

    private func persistConfiguration() {
        guard configuration.isValid,
              let data = try? JSONEncoder().encode(configuration)
        else { return }
        defaults.set(data, forKey: Key.configuration)
    }
}
