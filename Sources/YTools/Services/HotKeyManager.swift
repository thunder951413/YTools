import Carbon
import Foundation

@MainActor
final class HotKeyManager {
    private var hotKeys: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var actions: [UInt32: () -> Void] = [:]

    init() {
        install()
    }

    isolated deinit {
        removeAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    func register(
        id: UInt32,
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping () -> Void
    ) -> Bool {
        actions[id] = action
        let identifier = EventHotKeyID(signature: 0x5A_54_4F_4F, id: id)
        var hotKey: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        if status == noErr, let hotKey {
            hotKeys.append(hotKey)
            return true
        } else {
            actions.removeValue(forKey: id)
            return false
        }
    }

    func removeAll() {
        for hotKey in hotKeys { UnregisterEventHotKey(hotKey) }
        hotKeys.removeAll()
        actions.removeAll()
    }

    private func install() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                var identifier = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                if status == noErr {
                    MainActor.assumeIsolated { manager.actions[identifier.id]?() }
                }
                return noErr
            },
            1,
            &eventType,
            pointer,
            &eventHandler
        )
    }
}
