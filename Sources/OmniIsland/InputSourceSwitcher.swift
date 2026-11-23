import Carbon

/// Switches the keyboard to an English (ASCII-capable) input source while the
/// launcher is open, and puts the previous one back when it closes, like
/// Flow Launcher's "always start typing in English mode". Prefixes ("c ")
/// and app names then type as expected even when Korean was on.
@MainActor
final class InputSourceSwitcher {
    /// The source that was on before the launcher opened, when we changed it.
    private var saved: TISInputSource?

    func switchToEnglish() {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return }
        guard !Self.isASCIICapable(current),
              let english = TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue()
        else {
            saved = nil
            return
        }
        saved = current
        TISSelectInputSource(english)
    }

    /// True while a switched-away input source is waiting to be put back.
    var isHolding: Bool { saved != nil }

    func restore() {
        guard let saved else { return }
        self.saved = nil
        TISSelectInputSource(saved)
    }

    private static func isASCIICapable(_ source: TISInputSource) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsASCIICapable) else {
            return false
        }
        let value = Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue()
        return CFBooleanGetValue(value)
    }
}
