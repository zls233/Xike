import Foundation

@MainActor
final class SnapshotStore {
    private enum Key {
        static let activeSession = "session.activeSnapshot"
    }

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        encoder = JSONEncoder()
        decoder = JSONDecoder()
    }

    func save(_ snapshot: SessionSnapshot?) {
        guard let snapshot else {
            clear()
            return
        }
        guard let data = try? encoder.encode(snapshot) else { return }
        defaults.set(data, forKey: Key.activeSession)
    }

    func load() -> SessionSnapshot? {
        guard let data = defaults.data(forKey: Key.activeSession) else { return nil }
        guard let snapshot = try? decoder.decode(SessionSnapshot.self, from: data) else {
            clear()
            return nil
        }
        return snapshot
    }

    func clear() {
        defaults.removeObject(forKey: Key.activeSession)
    }
}
