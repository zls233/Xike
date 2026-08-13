import Carbon
import Foundation

enum GlobalShortcut: String, Codable, CaseIterable, Identifiable, Sendable {
    case commandOptionReturn
    case controlOptionSpace
    case commandShiftSpace

    var id: String { rawValue }
    var title: String {
        switch self {
        case .commandOptionReturn: "⌘⌥↩"
        case .controlOptionSpace: "⌃⌥Space"
        case .commandShiftSpace: "⌘⇧Space"
        }
    }

    var keyCode: UInt32 {
        switch self {
        case .commandOptionReturn: UInt32(kVK_Return)
        case .controlOptionSpace, .commandShiftSpace: UInt32(kVK_Space)
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .commandOptionReturn: UInt32(cmdKey | optionKey)
        case .controlOptionSpace: UInt32(controlKey | optionKey)
        case .commandShiftSpace: UInt32(cmdKey | shiftKey)
        }
    }
}

@MainActor
final class GlobalHotKeyService {
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var action: (() -> Void)?

    func register(shortcut: GlobalShortcut, action: @escaping () -> Void) {
        unregister()
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData else { return noErr }
            let service = Unmanaged<GlobalHotKeyService>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in service.action?() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)

        let identifier = EventHotKeyID(signature: Self.signature, id: 1)
        RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, identifier, GetApplicationEventTarget(), 0, &hotKey)
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKey = nil
        eventHandler = nil
        action = nil
    }

    private static let signature: OSType = 0x58494B45 // XIKE
}
