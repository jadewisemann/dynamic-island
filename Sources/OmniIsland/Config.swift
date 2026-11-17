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
    // JSON key "animation"; named `motion` in Swift because `Binding.animation(_:)` would shadow it.
    var motion = AnimationConfig()

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
        /// How often Dock notification badges are re-read.
        var badgeIntervalMs = 3000.0
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
        var borderOpacity = 0.0
        var showEventProgress = true
        /// apps: workspace number followed by its app icons (like OmniWM's
        /// workspace bar). pills: compact numbered capsules only.
        var workspaceStyle = "apps"
        var appIconSize = 20.0
        /// Icons shown per workspace before collapsing the rest into "+N".
        var maxAppsPerWorkspace = 6.0
        /// Red notification badges read from the Dock (needs Accessibility).
        var showBadges = true
        /// Small dots under an icon when the app has several windows on
        /// that workspace (one dot per window, up to three).
        var showWindowCount = true
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
        c.behavior.badgeIntervalMs = b.number("badgeIntervalMs", c.behavior.badgeIntervalMs)

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
        c.appearance.borderOpacity = a.number("borderOpacity", c.appearance.borderOpacity)
        c.appearance.showEventProgress = a.bool("showEventProgress", c.appearance.showEventProgress)
        c.appearance.workspaceStyle = a.string("workspaceStyle", c.appearance.workspaceStyle)
        c.appearance.appIconSize = a.number("appIconSize", c.appearance.appIconSize)
        c.appearance.maxAppsPerWorkspace = a.number("maxAppsPerWorkspace", c.appearance.maxAppsPerWorkspace)
        c.appearance.showBadges = a.bool("showBadges", c.appearance.showBadges)
        c.appearance.showWindowCount = a.bool("showWindowCount", c.appearance.showWindowCount)

        let n = r.sub("animation")
        c.motion.style = n.string("style", c.motion.style)
        c.motion.response = n.number("response", c.motion.response)
        c.motion.dampingFraction = n.number("dampingFraction", c.motion.dampingFraction)
        c.motion.durationMs = n.number("durationMs", c.motion.durationMs)
        c.motion.blurTransitions = n.bool("blurTransitions", c.motion.blurTransitions)
        c.motion.popOnEvent = n.bool("popOnEvent", c.motion.popOnEvent)

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

// MARK: - Writing

extension IslandConfig {
    static var defaultFileContents: String { IslandConfig().fileContents() }

    /// Renders the config as commented JSON5. Used for the first-launch file
    /// and every time the settings window saves.
    func fileContents() -> String {
        func q(_ s: String?) -> String {
            let data = try? JSONSerialization.data(withJSONObject: [s ?? ""], options: [.withoutEscapingSlashes])
            let array = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
            return String(array.dropFirst().dropLast())
        }
        func n(_ v: Double) -> String {
            if v.rounded() == v && abs(v) < 1e9 { return String(Int(v)) }
            var text = String(format: "%.3f", v)
            while text.hasSuffix("0") { text.removeLast() }
            return text
        }
        func b(_ v: Bool) -> String { v ? "true" : "false" }
        let t = trigger, be = behavior, a = appearance, an = motion

        return """
        // OmniIsland 설정 파일 (JSON5: 주석과 끝 쉼표를 쓸 수 있습니다)
        // 메뉴 막대 아이콘 → "설정…"에서 바꾸는 것을 권장합니다.
        // 직접 고쳐도 저장하면 앱이 자동으로 다시 불러옵니다.
        {
          // omniwmctl 경로. 비워 두면 PATH, ~/.local/bin, /opt/homebrew/bin,
          // /Applications/OmniWM.app/Contents/MacOS 순서로 찾습니다.
          "omniwmctlPath": \(q(omniwmctlPath)),
          // OmniWM IPC 소켓 경로를 바꿨다면 여기에 적습니다 (OMNIWM_SOCKET).
          "socketPath": \(q(socketPath)),

          "trigger": {
            // option | leftOption | rightOption | command | control | shift ...
            // "control+option"처럼 조합할 수도 있습니다.
            "modifier": \(q(t.modifier)),
            "holdDelayMs": \(n(t.holdDelayMs)),
            "hideDelayMs": \(n(t.hideDelayMs)),
            // true면 다른 modifier 없이 이 키만 눌렀을 때만 나타납니다.
            "exactMatch": \(b(t.exactMatch)),
          },

          "behavior": {
            // modifier를 누르지 않았을 때도 이동이 일어나면 펼쳐서 보여 줍니다.
            "showEventsWithoutModifier": \(b(be.showEventsWithoutModifier)),
            "eventDurationMs": \(n(be.eventDurationMs)),
            "showWorkspaceSwitch": \(b(be.showWorkspaceSwitch)),
            "showWindowMove": \(b(be.showWindowMove)),
            "showEmptyWorkspaces": \(b(be.showEmptyWorkspaces)),
            // notch | main | active (OmniWM이 지금 조작 중인 모니터)
            "screen": \(q(be.screen)),
            // auto | notch | fade
            "hiddenStyle": \(q(be.hiddenStyle)),
            "showMenuBarIcon": \(b(be.showMenuBarIcon)),
            "coalesceMs": \(n(be.coalesceMs)),
            // Dock 알림 배지를 다시 읽는 간격입니다.
            "badgeIntervalMs": \(n(be.badgeIntervalMs)),
          },

          "appearance": {
            "backgroundColor": \(q(a.backgroundColor)),
            "backgroundOpacity": \(n(a.backgroundOpacity)),
            "accentColor": \(q(a.accentColor)),
            "textColor": \(q(a.textColor)),
            "secondaryTextColor": \(q(a.secondaryTextColor)),
            "bottomCornerRadius": \(n(a.bottomCornerRadius)),
            "topCornerRadius": \(n(a.topCornerRadius)),
            "fontSize": \(n(a.fontSize)),
            "pillSize": \(n(a.pillSize)),
            "pillSpacing": \(n(a.pillSpacing)),
            "shadow": \(b(a.shadow)),
            // 가장자리에 아주 얇은 밝은 테두리를 그립니다 (0이면 없음).
            "borderOpacity": \(n(a.borderOpacity)),
            "fallbackNotchWidth": \(n(a.fallbackNotchWidth)),
            "fallbackNotchHeight": \(n(a.fallbackNotchHeight)),
            "compactRowHeight": \(n(a.compactRowHeight)),
            "expandedWidth": \(n(a.expandedWidth)),
            "expandedHeaderHeight": \(n(a.expandedHeaderHeight)),
            "showAppIcons": \(b(a.showAppIcons)),
            "showFocusedApp": \(b(a.showFocusedApp)),
            // 펼쳐진 상태가 끝날 때까지 남은 시간을 아래쪽 막대로 보여 줍니다.
            "showEventProgress": \(b(a.showEventProgress)),
            // apps: 워크스페이스 번호 옆에 앱 아이콘을 나열 (OmniWM 바와 비슷)
            // pills: 번호만 있는 작은 알약
            "workspaceStyle": \(q(a.workspaceStyle)),
            "appIconSize": \(n(a.appIconSize)),
            "maxAppsPerWorkspace": \(n(a.maxAppsPerWorkspace)),
            // Dock에 뜨는 빨간 알림 배지를 앱 아이콘에 표시합니다 (손쉬운 사용 권한 필요).
            "showBadges": \(b(a.showBadges)),
            // 한 앱의 창이 그 워크스페이스에 여러 개면 아이콘 아래에 점(최대 3개)을 찍습니다.
            "showWindowCount": \(b(a.showWindowCount)),
          },

          "animation": {
            // spring | bouncy | smooth | snappy | easeInOut | none
            "style": \(q(an.style)),
            "response": \(n(an.response)),
            "dampingFraction": \(n(an.dampingFraction)),
            "durationMs": \(n(an.durationMs)),
            "blurTransitions": \(b(an.blurTransitions)),
            "popOnEvent": \(b(an.popOnEvent)),
          },
        }

        """
    }
}
