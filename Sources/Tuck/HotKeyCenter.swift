import Carbon.HIToolbox
import TuckCore

/// Registers one system-wide shortcut through Carbon, which needs no Accessibility permission.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    var action: (() -> Void)?
    private var hotKey: EventHotKeyRef?
    private var handlerInstalled = false

    /// Returns false when another app already owns the shortcut.
    @discardableResult
    func register(_ shortcut: Shortcut?) -> Bool {
        unregister()
        guard let shortcut else { return true }
        installHandlerOnce()
        let id = EventHotKeyID(signature: OSType(0x5455_434B), id: 1) // "TUCK"
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers.rawValue, id,
                                         GetApplicationEventTarget(), 0, &hotKey)
        return status == noErr
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    private func installHandlerOnce() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { HotKeyCenter.shared.action?() }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
