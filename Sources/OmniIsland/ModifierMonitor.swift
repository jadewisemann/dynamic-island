import AppKit
import ApplicationServices

/// Reports whether the configured trigger modifier (Option by default) is held.
///
/// With Accessibility permission it uses a global `flagsChanged` monitor
/// (event driven, zero idle cost). Without permission it falls back to
/// polling `CGEventSource.flagsState`, which needs no permission at all, so the
/// island still works before the user grants access.
@MainActor
final class ModifierMonitor {
    var onChange: ((Bool) -> Void)?
    private(set) var isHeld = false

    private var requirement = ModifierRequirement.parse("option")
    private var exactMatch = true
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pollTimer: Timer?
    private var trustCheckTimer: Timer?

    func configure(modifier: String, exactMatch: Bool) {
        requirement = ModifierRequirement.parse(modifier)
        self.exactMatch = exactMatch
        evaluate(rawFlags: UInt64(CGEventSource.flagsState(.combinedSessionState).rawValue))
    }

    func start(promptForAccessibility: Bool) {
        let trusted = Self.isTrusted(prompt: promptForAccessibility)
        installLocalMonitor()
        if trusted {
            installGlobalMonitor()
        } else {
            startPolling()
            // Switch to the event monitor as soon as the user grants access.
            trustCheckTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, Self.isTrusted(prompt: false) else { return }
                    self.trustCheckTimer?.invalidate()
                    self.trustCheckTimer = nil
                    self.stopPolling()
                    self.installGlobalMonitor()
                }
            }
        }
    }

    static func isTrusted(prompt: Bool) -> Bool {
        // String value of kAXTrustedCheckOptionPrompt.
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    var usesEventMonitor: Bool { globalMonitor != nil }

    // MARK: - Sources

    private func installGlobalMonitor() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let raw = UInt64(event.modifierFlags.rawValue)
            MainActor.assumeIsolated { self?.evaluate(rawFlags: raw) }
        }
    }

    private func installLocalMonitor() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let raw = UInt64(event.modifierFlags.rawValue)
            MainActor.assumeIsolated { self?.evaluate(rawFlags: raw) }
            return event
        }
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 40.0, repeats: true) { [weak self] _ in
            let raw = UInt64(CGEventSource.flagsState(.combinedSessionState).rawValue)
            MainActor.assumeIsolated { self?.evaluate(rawFlags: raw) }
        }
        timer.tolerance = 0.005
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func evaluate(rawFlags: UInt64) {
        let held = requirement.matches(rawFlags: rawFlags, exact: exactMatch)
        guard held != isHeld else { return }
        isHeld = held
        onChange?(held)
    }
}

/// Parsed form of strings like "option", "rightOption", "control+option".
struct ModifierRequirement {
    /// Device-independent masks (NSEvent.ModifierFlags / CGEventFlags share them).
    static let shift: UInt64 = 1 << 17
    static let control: UInt64 = 1 << 18
    static let option: UInt64 = 1 << 19
    static let command: UInt64 = 1 << 20
    static let allGeneric: UInt64 = shift | control | option | command

    // Device-dependent bits from IOKit's NX_DEVICE*KEYMASK.
    static let leftControl: UInt64 = 0x0000_0001
    static let leftShift: UInt64 = 0x0000_0002
    static let rightShift: UInt64 = 0x0000_0004
    static let leftCommand: UInt64 = 0x0000_0008
    static let rightCommand: UInt64 = 0x0000_0010
    static let leftOption: UInt64 = 0x0000_0020
    static let rightOption: UInt64 = 0x0000_0040
    static let rightControl: UInt64 = 0x0000_2000

    struct Part {
        let generic: UInt64
        let device: UInt64?
    }

    let parts: [Part]

    static func parse(_ spec: String) -> ModifierRequirement {
        let tokens = spec.lowercased()
            .split(whereSeparator: { $0 == "+" || $0 == "," || $0 == " " })
            .map(String.init)
        var parts: [Part] = []
        for token in tokens {
            switch token {
            case "option", "opt", "alt": parts.append(Part(generic: option, device: nil))
            case "leftoption", "leftalt", "loption": parts.append(Part(generic: option, device: leftOption))
            case "rightoption", "rightalt", "roption": parts.append(Part(generic: option, device: rightOption))
            case "command", "cmd": parts.append(Part(generic: command, device: nil))
            case "leftcommand", "leftcmd": parts.append(Part(generic: command, device: leftCommand))
            case "rightcommand", "rightcmd": parts.append(Part(generic: command, device: rightCommand))
            case "control", "ctrl": parts.append(Part(generic: control, device: nil))
            case "leftcontrol", "leftctrl": parts.append(Part(generic: control, device: leftControl))
            case "rightcontrol", "rightctrl": parts.append(Part(generic: control, device: rightControl))
            case "shift": parts.append(Part(generic: shift, device: nil))
            case "leftshift": parts.append(Part(generic: shift, device: leftShift))
            case "rightshift": parts.append(Part(generic: shift, device: rightShift))
            default: Log.info("unknown modifier '\(token)' ignored")
            }
        }
        if parts.isEmpty { parts = [Part(generic: option, device: nil)] }
        return ModifierRequirement(parts: parts)
    }

    func matches(rawFlags: UInt64, exact: Bool) -> Bool {
        for part in parts {
            guard rawFlags & part.generic != 0 else { return false }
            if let device = part.device, rawFlags & device == 0 { return false }
        }
        if exact {
            let required = parts.reduce(UInt64(0)) { $0 | $1.generic }
            if rawFlags & Self.allGeneric & ~required != 0 { return false }
        }
        return true
    }
}
