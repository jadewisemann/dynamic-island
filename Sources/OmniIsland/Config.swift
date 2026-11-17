import Foundation

/// User-facing configuration. Every field has a default, so a partial (or
/// missing) config file is always valid. The file is parsed as JSON5, which
/// means `// comments` and trailing commas are allowed.
struct IslandConfig: Equatable {
    /// Absolute path to `omniwmctl`. `nil` searches the usual locations.
    var omniwmctlPath: String? = nil
    /// Overrides OmniWM's IPC socket path (passed as `OMNIWM_SOCKET`).
    var socketPath: String? = nil

    var trigger = Trigger()
    var behavior = Behavior()
    var appearance = Appearance()
    var animation = AnimationConfig()

    struct Trigger: Equatable {
        /// option | leftOption | rightOption | command | leftCommand | rightCommand |
        /// control | leftControl | rightControl | shift | leftShift | rightShift |
        /// any `+`-joined combination such as "control+option".
        var modifier = "option"
        /// How long the modifier must be held before the island appears.
        var holdDelayMs = 120.0
        /// How long the island stays after the modifier is released.
        var hideDelayMs = 160.0
        /// When true, the island only appears when the modifier is pressed on
        /// its own (no other modifier held at the same time).
        var exactMatch = true
    }

    struct Behavior: Equatable {
        /// Expand on workspace / window moves even when the modifier is not held.
        var showEventsWithoutModifier = true
        /// How long an expanded event stays on screen.
        var eventDurationMs = 1700.0
        var showWorkspaceSwitch = true
        var showWindowMove = true
        /// Show workspaces with no windows in the workspace row.
        var showEmptyWorkspaces = false
        /// Which screen hosts the island: notch | main | active
        var screen = "notch"
        /// What the island looks like while hidden: auto | notch | fade.
        /// `notch` keeps a black notch-sized shape (invisible on notched
        /// MacBooks), `fade` fades out completely, `auto` picks per screen.
        var hiddenStyle = "auto"
        var showMenuBarIcon = true
        /// Merge events that arrive within this window (a window move that also
        /// switches workspace becomes one "window moved" event).
        var coalesceMs = 140.0
    }

    struct Appearance: Equatable {
        var backgroundColor = "#000000"
        var backgroundOpacity = 1.0
        var accentColor = "#0A84FF"
        var textColor = "#FFFFFF"
        var secondaryTextColor = "#FFFFFF99"
        var bottomCornerRadius = 20.0
        /// Radius of the small concave "shoulders" where the island meets the
        /// top edge of the screen, like the real notch.
        var topCornerRadius = 7.0
        var fontSize = 13.0
        var pillSize = 24.0
        var pillSpacing = 6.0
        var shadow = true
        /// Used on screens without a notch.
        var fallbackNotchWidth = 200.0
        var fallbackNotchHeight = 32.0
        /// Height of the workspace row shown below the notch while the
        /// modifier is held.
        var compactRowHeight = 38.0
        var expandedWidth = 400.0
        var expandedHeaderHeight = 54.0
        var showAppIcons = true
        var showFocusedApp = true
    }

    struct AnimationConfig: Equatable {
        /// spring | bouncy | smooth | snappy | easeInOut | none
        var style = "spring"
        /// Spring settle time in seconds (spring only).
        var response = 0.45
        /// 0...1, lower is bouncier (spring only).
        var dampingFraction = 0.76
        /// Duration for easeInOut / bouncy / smooth / snappy.
        var durationMs = 380.0
        /// Blur content while it fades in/out.
        var blurTransitions = true
        /// Small scale "pop" when the island expands for an event.
        var popOnEvent = true
    }
}

// MARK: - Parsing

extension IslandConfig {
    enum ParseError: Error, CustomStringConvertible {
        case notAnObject
        var description: String { "config root must be a JSON object" }
    }

    static func parse(_ data: Data) throws -> IslandConfig {
        let object = try JSONSerialization.jsonObject(with: data, options: [.json5Allowed])
        guard let dict = object as? [String: Any] else { throw ParseError.notAnObject }
        let r = ConfigReader(dict)
        var c = IslandConfig()

        c.omniwmctlPath = r.optionalString("omniwmctlPath").map(ConfigReader.expandTilde)
        c.socketPath = r.optionalString("socketPath").map(ConfigReader.expandTilde)

        let t = r.sub("trigger")
        c.trigger.modifier = t.string("modifier", c.trigger.modifier)
        c.trigger.holdDelayMs = t.number("holdDelayMs", c.trigger.holdDelayMs)
        c.trigger.hideDelayMs = t.number("hideDelayMs", c.trigger.hideDelayMs)
        c.trigger.exactMatch = t.bool("exactMatch", c.trigger.exactMatch)

        let b = r.sub("behavior")
        c.behavior.showEventsWithoutModifier = b.bool("showEventsWithoutModifier", c.behavior.showEventsWithoutModifier)
        c.behavior.eventDurationMs = b.number("eventDurationMs", c.behavior.eventDurationMs)
        c.behavior.showWorkspaceSwitch = b.bool("showWorkspaceSwitch", c.behavior.showWorkspaceSwitch)
        c.behavior.showWindowMove = b.bool("showWindowMove", c.behavior.showWindowMove)
        c.behavior.showEmptyWorkspaces = b.bool("showEmptyWorkspaces", c.behavior.showEmptyWorkspaces)
        c.behavior.screen = b.string("screen", c.behavior.screen)
        c.behavior.hiddenStyle = b.string("hiddenStyle", c.behavior.hiddenStyle)
        c.behavior.showMenuBarIcon = b.bool("showMenuBarIcon", c.behavior.showMenuBarIcon)
        c.behavior.coalesceMs = b.number("coalesceMs", c.behavior.coalesceMs)

        let a = r.sub("appearance")
        c.appearance.backgroundColor = a.string("backgroundColor", c.appearance.backgroundColor)
        c.appearance.backgroundOpacity = a.number("backgroundOpacity", c.appearance.backgroundOpacity)
        c.appearance.accentColor = a.string("accentColor", c.appearance.accentColor)
        c.appearance.textColor = a.string("textColor", c.appearance.textColor)
        c.appearance.secondaryTextColor = a.string("secondaryTextColor", c.appearance.secondaryTextColor)
        c.appearance.bottomCornerRadius = a.number("bottomCornerRadius", c.appearance.bottomCornerRadius)
        c.appearance.topCornerRadius = a.number("topCornerRadius", c.appearance.topCornerRadius)
        c.appearance.fontSize = a.number("fontSize", c.appearance.fontSize)
        c.appearance.pillSize = a.number("pillSize", c.appearance.pillSize)
        c.appearance.pillSpacing = a.number("pillSpacing", c.appearance.pillSpacing)
        c.appearance.shadow = a.bool("shadow", c.appearance.shadow)
        c.appearance.fallbackNotchWidth = a.number("fallbackNotchWidth", c.appearance.fallbackNotchWidth)
        c.appearance.fallbackNotchHeight = a.number("fallbackNotchHeight", c.appearance.fallbackNotchHeight)
        c.appearance.compactRowHeight = a.number("compactRowHeight", c.appearance.compactRowHeight)
        c.appearance.expandedWidth = a.number("expandedWidth", c.appearance.expandedWidth)
        c.appearance.expandedHeaderHeight = a.number("expandedHeaderHeight", c.appearance.expandedHeaderHeight)
        c.appearance.showAppIcons = a.bool("showAppIcons", c.appearance.showAppIcons)
        c.appearance.showFocusedApp = a.bool("showFocusedApp", c.appearance.showFocusedApp)

        let n = r.sub("animation")
        c.animation.style = n.string("style", c.animation.style)
        c.animation.response = n.number("response", c.animation.response)
        c.animation.dampingFraction = n.number("dampingFraction", c.animation.dampingFraction)
        c.animation.durationMs = n.number("durationMs", c.animation.durationMs)
        c.animation.blurTransitions = n.bool("blurTransitions", c.animation.blurTransitions)
        c.animation.popOnEvent = n.bool("popOnEvent", c.animation.popOnEvent)

        return c
    }
}

private struct ConfigReader {
    let dict: [String: Any]
    init(_ dict: [String: Any]) { self.dict = dict }

    func sub(_ key: String) -> ConfigReader {
        ConfigReader(dict[key] as? [String: Any] ?? [:])
    }

    func string(_ key: String, _ fallback: String) -> String {
        dict[key] as? String ?? fallback
    }

    func optionalString(_ key: String) -> String? {
        guard let s = dict[key] as? String, !s.isEmpty else { return nil }
        return s
    }

    func number(_ key: String, _ fallback: Double) -> Double {
        guard let n = dict[key] as? NSNumber else { return fallback }
        let v = n.doubleValue
        return v.isFinite ? v : fallback
    }

    func bool(_ key: String, _ fallback: Bool) -> Bool {
        dict[key] as? Bool ?? fallback
    }

    static func expandTilde(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}

// MARK: - Default file

extension IslandConfig {
    /// Written on first launch. Keep in sync with the defaults above.
    static let defaultFileContents = """
    // OmniIsland 설정 파일 (JSON5: 주석과 끝 쉼표를 쓸 수 있습니다)
    // 저장하면 앱이 자동으로 다시 불러옵니다.
    {
      // omniwmctl 경로. 비워 두면 PATH, ~/.local/bin, /opt/homebrew/bin,
      // /Applications/OmniWM.app/Contents/MacOS 순서로 찾습니다.
      "omniwmctlPath": "",
      // OmniWM IPC 소켓 경로를 바꿨다면 여기에 적습니다 (OMNIWM_SOCKET).
      "socketPath": "",

      "trigger": {
        // option | leftOption | rightOption | command | control | shift ...
        // "control+option"처럼 조합할 수도 있습니다.
        "modifier": "option",
        "holdDelayMs": 120,
        "hideDelayMs": 160,
        // true면 다른 modifier 없이 이 키만 눌렀을 때만 나타납니다.
        "exactMatch": true,
      },

      "behavior": {
        // modifier를 누르지 않았을 때도 이동이 일어나면 펼쳐서 보여 줍니다.
        "showEventsWithoutModifier": true,
        "eventDurationMs": 1700,
        "showWorkspaceSwitch": true,
        "showWindowMove": true,
        "showEmptyWorkspaces": false,
        // notch | main | active (OmniWM이 지금 조작 중인 모니터)
        "screen": "notch",
        // auto | notch | fade
        "hiddenStyle": "auto",
        "showMenuBarIcon": true,
        "coalesceMs": 140,
      },

      "appearance": {
        "backgroundColor": "#000000",
        "backgroundOpacity": 1.0,
        "accentColor": "#0A84FF",
        "textColor": "#FFFFFF",
        "secondaryTextColor": "#FFFFFF99",
        "bottomCornerRadius": 20,
        "topCornerRadius": 7,
        "fontSize": 13,
        "pillSize": 24,
        "pillSpacing": 6,
        "shadow": true,
        "fallbackNotchWidth": 200,
        "fallbackNotchHeight": 32,
        "compactRowHeight": 38,
        "expandedWidth": 400,
        "expandedHeaderHeight": 54,
        "showAppIcons": true,
        "showFocusedApp": true,
      },

      "animation": {
        // spring | bouncy | smooth | snappy | easeInOut | none
        "style": "spring",
        "response": 0.45,
        "dampingFraction": 0.76,
        "durationMs": 380,
        "blurTransitions": true,
        "popOnEvent": true,
      },
    }

    """
}
