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
