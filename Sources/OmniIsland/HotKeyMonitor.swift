import AppKit
import Carbon.HIToolbox

/// A key combination the whole system hands to this app, such as ⌥H.
///
/// Uses Carbon's `RegisterEventHotKey`, like most launchers: it needs no
/// Accessibility permission, and the key press is not passed on to the
/// frontmost app (so ⌥H does not also type "˙").
@MainActor
final class HotKeyMonitor {
    var onPress: (() -> Void)?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private(set) var registeredSpec: String?

    /// Registers `spec` ("option+h", "control+space", …), replacing the
    /// previous key. An empty spec only unregisters. Returns success.
    @discardableResult
    func register(_ spec: String) -> Bool {
        unregister()
        let trimmed = spec.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        guard let parsed = Self.parse(trimmed) else {
            Log.info("launcher hotkey '\(spec)' could not be parsed")
            return false
        }
        installHandler()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x4F49_4C48), id: 1) // "OILH"
        let status = RegisterEventHotKey(parsed.keyCode, parsed.modifiers, id,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            Log.info("launcher hotkey '\(spec)' was refused (\(status))")
            return false
        }
        hotKey = ref
        registeredSpec = trimmed
        return true
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        registeredSpec = nil
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let user = Unmanaged.passUnretained(self).toOpaque()
        var ref: EventHandlerRef?
        InstallEventHandler(GetApplicationEventTarget(), { _, _, user in
            guard let user else { return noErr }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    Unmanaged<HotKeyMonitor>.fromOpaque(user).takeUnretainedValue().onPress?()
                }
            }
            return noErr
        }, 1, &spec, user, &ref)
        handler = ref
    }

    // MARK: - Parsing

    struct Parsed: Equatable {
        let keyCode: UInt32
        let modifiers: UInt32
    }

    static func parse(_ spec: String) -> Parsed? {
        let tokens = spec.lowercased()
            .split(whereSeparator: { $0 == "+" || $0 == " " })
            .map(String.init)
        guard let key = tokens.last, let code = keyCodes[key] else { return nil }
        var modifiers: UInt32 = 0
        for token in tokens.dropLast() {
            switch token {
            case "option", "opt", "alt": modifiers |= UInt32(optionKey)
            case "command", "cmd": modifiers |= UInt32(cmdKey)
            case "control", "ctrl": modifiers |= UInt32(controlKey)
            case "shift": modifiers |= UInt32(shiftKey)
            default: return nil
            }
        }
        guard modifiers != 0 else { return nil }
        return Parsed(keyCode: UInt32(code), modifiers: modifiers)
    }

    /// Display form such as "⌥H".
    static func symbols(_ spec: String) -> String {
        let tokens = spec.lowercased().split(whereSeparator: { $0 == "+" || $0 == " " }).map(String.init)
        guard let key = tokens.last else { return spec }
        var text = ""
        if tokens.contains("control") || tokens.contains("ctrl") { text += "⌃" }
        if tokens.contains("option") || tokens.contains("opt") || tokens.contains("alt") { text += "⌥" }
        if tokens.contains("shift") { text += "⇧" }
        if tokens.contains("command") || tokens.contains("cmd") { text += "⌘" }
        switch key {
        case "space": text += "Space"
        case "return": text += "↩"
        case "tab": text += "⇥"
        default: text += key.uppercased()
        }
        return text
    }

    private static let keyCodes: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
        "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
        "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
        "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
        "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
        "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "space": kVK_Space, "return": kVK_Return, "tab": kVK_Tab,
        "/": kVK_ANSI_Slash, ";": kVK_ANSI_Semicolon, ".": kVK_ANSI_Period, ",": kVK_ANSI_Comma,
        "`": kVK_ANSI_Grave,
    ]
}
