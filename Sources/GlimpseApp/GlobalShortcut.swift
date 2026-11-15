import AppKit
import Carbon.HIToolbox
import GlimpseCore

/// One system-wide hotkey via Carbon's RegisterEventHotKey: no Accessibility permission,
/// works in the App Store sandbox and on macOS 12.
@MainActor
final class GlobalShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var registered: KeyboardShortcut?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { shortcut.action() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    /// Registers `shortcut`, replacing any previous one; nil unregisters. Returns false when
    /// the system refuses it (usually because another app already owns that combination).
    @discardableResult
    func update(_ shortcut: KeyboardShortcut?) -> Bool {
        guard shortcut != registered else { return true }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        registered = shortcut
        guard let shortcut else { return true }
        let id = EventHotKeyID(signature: OSType(0x474C4D50), id: 1) // "GLMP"
        return RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &hotKey) == noErr
    }

    /// Converts a key-down event into a shortcut. At least one of ⌘ ⌥ ⌃ is required so
    /// typing ordinary characters never triggers it.
    static func shortcut(from event: NSEvent) -> KeyboardShortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
        var carbon: UInt32 = 0
        var symbols = ""
        if flags.contains(.control) { carbon |= UInt32(controlKey); symbols += "⌃" }
        if flags.contains(.option) { carbon |= UInt32(optionKey); symbols += "⌥" }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey); symbols += "⇧" }
        if flags.contains(.command) { carbon |= UInt32(cmdKey); symbols += "⌘" }
        let named: [UInt16: String] = [122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
                                       101: "F9", 109: "F10", 103: "F11", 111: "F12", 49: "Space", 36: "↩", 48: "⇥", 51: "⌫",
                                       123: "←", 124: "→", 125: "↓", 126: "↑"]
        let key = named[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "#\(event.keyCode)"
        return KeyboardShortcut(keyCode: UInt32(event.keyCode), modifiers: carbon, display: symbols + key)
    }
}
