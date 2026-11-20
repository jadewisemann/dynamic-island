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
    var theme = Theme()
    var layout = Layout()
    var widgets = Widgets()
    var notifications = Notifications()
    var calendar = CalendarConfig()
    var dashboard = Dashboard()
    var launcher = Launcher()
    var agents = Agents()
    var shelf = Shelf()
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
        /// With exactMatch, still show the island while Shift is held too,
        /// so OmniWM shortcuts like Option+Shift+number keep it visible.
        var allowShift = true
    }

    struct Behavior: Equatable {
        /// Expand on workspace / window moves even when the modifier is not held.
        var showEventsWithoutModifier = true
        /// How long an expanded event stays on screen.
        var eventDurationMs = 1700.0
        var showWorkspaceSwitch = true
        var showWindowMove = true
        /// Show a moved window as a drop flowing between workspaces in the row.
        var windowMoveTrail = true
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

    /// Everything a theme preset changes. Stored flat in "appearance" (the
    /// dark / fixed look) and in "theme.light" (the light look).
    struct ThemeColors: Equatable {
        /// solid | material | gradient
        var backgroundStyle = "solid"
        var backgroundColor = "#000000"
        /// Solid / gradient opacity, or how strongly the color tints the material.
        var backgroundOpacity = 1.0
        /// thin | regular | thick (material only)
        var material = "regular"
        /// Second gradient color (gradient only).
        var gradientColor = "#1C1C1E"
        /// Gradient direction in degrees: 0 left→right, 90 top→bottom.
        var gradientAngle = 90.0
        var accentColor = "#0A84FF"
        var textColor = "#FFFFFF"
        var secondaryTextColor = "#FFFFFF99"
        /// Text on the highlighted (active) workspace.
        var activeTextColor = "#FFFFFF"
        /// Base color of inactive workspace backgrounds, window dots and the
        /// border. Drawn at low opacity, so white suits dark themes and black
        /// suits light ones.
        var fillColor = "#FFFFFF"
        var badgeColor = "#FF3B30"
        var badgeTextColor = "#FFFFFF"
        /// Remaining-time bar. Empty uses the accent color.
        var progressColor = ""
        var borderOpacity = 0.0
        var shadow = true
        /// How the active workspace is marked: fill | outline | underline | dot
        var activeStyle = "fill"
        /// Soft accent glow around the active workspace.
        var activeGlow = true
    }

    struct Appearance: Equatable {
        var colors = ThemeColors()
        var bottomCornerRadius = 20.0
        /// Radius of the small concave "shoulders" where the island meets the
        /// top edge of the screen, like the real notch.
        var topCornerRadius = 7.0
        var fontSize = 13.0
        /// Installed font family name. Empty uses the system font.
        var fontFamily = ""
        /// System font design: default | rounded | monospaced | serif
        var fontDesign = "default"
        /// light | regular | bold | heavy (shifts every weight in the island)
        var fontWeight = "regular"
        /// Font of workspace numbers and names: same | default | rounded | monospaced | serif
        var numberFontDesign = "rounded"
        var pillSize = 24.0
        var pillSpacing = 6.0
        /// Used on screens without a notch.
        var fallbackNotchWidth = 200.0
        var fallbackNotchHeight = 32.0
        /// Height of the workspace row shown below the notch while the
        /// modifier is held.
        var compactRowHeight = 38.0
        var expandedWidth = 400.0
        var expandedHeaderHeight = 54.0
        var showAppIcons = true
        var showEventProgress = true
        /// apps: workspace number followed by its app icons (like OmniWM's
        /// workspace bar). pills: compact numbered capsules only.
        var workspaceStyle = "apps"
        var appIconSize = 20.0
        /// Icons shown per workspace before collapsing the rest into "+N".
        var maxAppsPerWorkspace = 6.0
        /// Red notification badges read from the Dock (needs Accessibility).
        var showBadges = true
        /// How an app with several windows on one workspace is shown:
        /// merge (one icon), dots (one icon with a dot per window, up to
        /// three) or separate (one icon per window).
        var multiWindowStyle = "dots"
        /// Ring the icon of the focused window in the accent color.
        var highlightFocusedWindow = true
    }

    struct Theme: Equatable {
        /// fixed: always use the "appearance" colors.
        /// system: "appearance" in dark mode, `light` in light mode.
        var mode = "fixed"
        var light = ThemePreset.light.colors
        /// Themes the user saved from the settings window.
        var saved: [SavedTheme] = []
    }

    struct SavedTheme: Equatable, Identifiable {
        var name: String
        var colors: ThemeColors
        var id: String { name }
    }

    struct Layout: Equatable {
        /// attached: grows out of the notch. floating: a separate rounded
        /// island below the menu bar.
        var shape = "attached"
        /// Gap between the menu bar and a floating island.
        var topGap = 8.0
        /// center | left | right. Screens with a notch always use center.
        var horizontalPosition = "center"
        /// Extra horizontal shift in points (screens without a notch).
        var horizontalOffset = 0.0
        /// auto: as wide as the content. fixed: at least `fixedWidth`.
        var widthMode = "auto"
        var fixedWidth = 420.0
        /// Workspace row alignment: center | leading | spread
        var rowAlignment = "center"
        /// Space between the island edge and its content.
        var contentPadding = 20.0
        /// Where the move notification goes: below | above | replace
        var eventPlacement = "below"
    }

    struct Widgets: Equatable {
        /// Content of the notch-height strip, left and right of the notch:
        /// app | workspace | clock | date | windows | nextEvent | notifications | agents | none
        var leftWing = "app"
        var rightWing = "workspace"
        /// name | number | both
        var workspaceLabel = "name"
        var eventIcon = true
        var eventSubtitle = true
        var eventFromTo = true
        /// 24h | 12h | 24hSeconds
        var clockFormat = "24h"
        /// Square widget tiles attached to the left and right of the island
        /// while the workspace row is shown:
        /// clock | calendar | nextEvent | events | notifications | agents
        var leftPanel = ["clock"]
        var rightPanel = ["calendar"]
        /// Width of each side panel in squares (1–3). More widgets than
        /// squares widen the panel; fewer share the width.
        var panelUnits = 1.0
    }

    /// macOS notifications read from Notification Center banners.
    struct Notifications: Equatable {
        var enabled = true
        /// How long a notification card stays expanded.
        var durationMs = 4000.0
        /// full | title | app (how much of the notification is shown)
        var contentMode = "full"
        /// all | allow (only `apps`) | block (everything except `apps`)
        var filterMode = "all"
        /// App names or bundle ids for the filter.
        var apps: [String] = []
        /// Also read the usernoted database (needs Full Disk Access). Sees
        /// apps whose banners are turned off.
        var readDatabase = true
        /// Close the system banner right after reading it.
        var dismissSystemBanner = false
        /// Keep small icons of missed notifications beside the notch.
        var keepIndicator = true
        var indicatorTimeoutMin = 30.0
        /// Merge notifications from the same app that arrive within this time.
        var mergeWindowMs = 3000.0
    }

    struct CalendarConfig: Equatable {
        /// Off by default because turning it on asks for calendar access.
        var enabled = false
        /// Calendar titles or identifiers to use. Empty uses every calendar.
        var calendars: [String] = []
        /// Alert this many minutes before each event (0 = when it starts).
        var alertMinutes: [Double] = [5, 0]
        var showAlerts = true
        var includeAllDay = false
    }

    /// Clock, today's events and recent notifications, shown when the
    /// modifier is held a little longer.
    struct Dashboard: Equatable {
        var enabled = false
        /// Extra hold time after the workspace row appears.
        var holdMs = 800.0
        /// clock | events | notifications, in display order.
        var items = ["clock", "events", "notifications"]
    }

    /// Search apps and windows from the island (⌥H by default).
    struct Launcher: Equatable {
        var enabled = true
        /// Global shortcut, e.g. "option+h", "control+space".
        var hotkey = "option+h"
        /// Switch to an English input source while open, and back on close.
        var englishInput = true
        var maxResults = 10.0
        /// With an empty query, list recently opened apps.
        var showRecent = true
        var recentCount = 5.0
        var searchApps = true
        /// Windows OmniWM manages; Return focuses one, ⌘Return brings it here.
        var searchWindows = true
        var calculator = true
        /// "100 USD to KRW", "100달러": ECB daily rates from Frankfurter.
        var currency = true
        /// Files in the home folder, from the Spotlight index.
        var searchFiles = true
        var maxFiles = 4.0
        /// System Settings panes ("wifi", "다크 모드") and OmniIsland's own settings.
        var searchSettings = true
        /// A "search Google" row, and Google's completions under it.
        var webSearch = true
        var suggestions = true
        var maxSuggestions = 3.0
        var askClaude = false
        var askGrok = false
        var searchX = false
        /// Clipboard history in the top-level search (it always has its own
        /// mode, "c ").
        var searchClipboard = false
        /// Width of the island while the launcher is open.
        var width = 560.0
        /// Trigger prefix of each built-in app: typing it and a space enters
        /// that app alone. "" turns the prefix off.
        var prefixes: [String: String] = Launcher.defaultPrefixes

        static let defaultPrefixes = ["clipboard": "c", "windows": "w", "settings": "s", "files": "f", "apps": ""]
    }

    /// Coding agents (Claude Code, Codex) reporting through `omni-island hook`.
    /// Clipboard manager: copies are kept and offered in the launcher ("c ").
    struct Shelf: Equatable {
        var enabled = true
        var maxItems = 30.0
        var captureImages = true
        var captureFiles = true
        /// Bundle ids or app names whose copies are never kept (password
        /// managers are always skipped).
        var ignoreApps: [String] = []
    }

    struct Agents: Equatable {
        var enabled = true
        /// Permission requests get allow / deny buttons on the island.
        var approvals = true
        /// Unanswered requests fall back to the terminal prompt after this.
        var approvalTimeoutSec = 120.0
        var notifyDone = true
        var notifyWaiting = true
        /// How long "done" and "waiting" cards stay.
        var cardDurationMs = 5000.0
        /// Finished sessions stay in the agents widget this long.
        var keepDoneMin = 30.0
    }

    struct AnimationConfig: Equatable {
        /// spring | bouncy | smooth | snappy | easeInOut | none
        var style = "spring"
        /// Spring settle time in seconds (spring only).
        var response = 0.5
        /// 0...1, lower is bouncier (spring only). Near 1 the island settles
        /// without overshooting, which reads calmer for large size changes.
        var dampingFraction = 0.9
        /// Duration for easeInOut / bouncy / smooth / snappy.
        var durationMs = 380.0
        /// Multiplies the speed of every island animation.
        var speed = 1.0
        /// How content appears: blur | fade | slide | none
        var contentTransition = "blur"
        /// Small scale "pop" when the island expands for an event.
        var popOnEvent = true
        /// Gooey, liquid-like motion: side panels split off as drops and the
        /// active workspace highlight stretches between workspaces.
        var liquid = true
    }
}

// MARK: - Theme presets

struct ThemePreset: Identifiable {
    let id: String
    let name: String
    let colors: IslandConfig.ThemeColors
    /// Fonts the preset also sets; nil leaves the current font alone.
    var fontDesign: String? = nil
    var numberFontDesign: String? = nil

    static let standard = ThemePreset(id: "default", name: "기본", colors: .init(), fontDesign: "default", numberFontDesign: "rounded")

    static let midnight: ThemePreset = {
        var c = IslandConfig.ThemeColors()
        c.backgroundColor = "#121A33"
        c.accentColor = "#7A8CFF"
        c.textColor = "#E6ECFF"
        c.secondaryTextColor = "#B8C4ECB3"
        c.activeTextColor = "#0D1330"
        c.fillColor = "#A0B4FF"
        c.borderOpacity = 0.1
        return ThemePreset(id: "midnight", name: "미드나잇", colors: c, fontDesign: "default", numberFontDesign: "rounded")
    }()

    static let glass: ThemePreset = {
        var c = IslandConfig.ThemeColors()
        c.backgroundStyle = "material"
        c.material = "thin"
        c.backgroundColor = "#1E1E24"
        c.backgroundOpacity = 0.35
        c.accentColor = "#FFFFFF"
        c.activeTextColor = "#111111"
        c.secondaryTextColor = "#FFFFFFB3"
        c.borderOpacity = 0.18
        c.activeGlow = false
        return ThemePreset(id: "glass", name: "글래스", colors: c, fontDesign: "default", numberFontDesign: "rounded")
    }()

    static let light: ThemePreset = {
        var c = IslandConfig.ThemeColors()
        c.backgroundColor = "#F7F7F9"
        c.accentColor = "#007AFF"
        c.textColor = "#1A1A1E"
        c.secondaryTextColor = "#1A1A1E99"
        c.activeTextColor = "#FFFFFF"
        c.fillColor = "#000000"
        c.borderOpacity = 0.08
        return ThemePreset(id: "light", name: "라이트", colors: c, fontDesign: "default", numberFontDesign: "rounded")
    }()

    static let sunset: ThemePreset = {
        var c = IslandConfig.ThemeColors()
        c.backgroundStyle = "gradient"
        c.backgroundColor = "#2B0F3A"
        c.gradientColor = "#0F2F3A"
        c.gradientAngle = 20
        c.accentColor = "#FF9F45"
        c.activeTextColor = "#2B0F3A"
        c.secondaryTextColor = "#FFFFFFB3"
        return ThemePreset(id: "sunset", name: "선셋", colors: c, fontDesign: "default", numberFontDesign: "rounded")
    }()

    static let terminal: ThemePreset = {
        var c = IslandConfig.ThemeColors()
        c.accentColor = "#E7E7E7"
        c.textColor = "#E7E7E7"
        c.secondaryTextColor = "#8A8A8A"
        c.activeTextColor = "#000000"
        c.activeStyle = "outline"
        c.activeGlow = false
        c.borderOpacity = 0.2
        return ThemePreset(id: "terminal", name: "터미널", colors: c, fontDesign: "monospaced", numberFontDesign: "same")
    }()

    /// Builds a preset from a community palette (r/unixporn favorites).
    /// Colors are the palettes' official values.
    private static func palette(_ id: String, _ name: String, bg: String, text: String, subtext: String,
                                accent: String, red: String, light: Bool = false) -> ThemePreset {
        var c = IslandConfig.ThemeColors()
        c.backgroundColor = bg
        c.textColor = text
        c.secondaryTextColor = subtext
        c.accentColor = accent
        c.activeTextColor = bg
        c.fillColor = text
        c.badgeColor = red
        c.badgeTextColor = bg
        c.borderOpacity = light ? 0.1 : 0.08
        c.activeGlow = false
        return ThemePreset(id: id, name: name, colors: c)
    }

    static let community: [ThemePreset] = [
        palette("catppuccin-mocha", "Catppuccin Mocha", bg: "#1E1E2E", text: "#CDD6F4", subtext: "#A6ADC8",
                accent: "#CBA6F7", red: "#F38BA8"),
        palette("catppuccin-latte", "Catppuccin Latte", bg: "#EFF1F5", text: "#4C4F69", subtext: "#6C6F85",
                accent: "#8839EF", red: "#D20F39", light: true),
        palette("nord", "Nord", bg: "#2E3440", text: "#ECEFF4", subtext: "#D8DEE9",
                accent: "#88C0D0", red: "#BF616A"),
        palette("gruvbox", "Gruvbox", bg: "#282828", text: "#EBDBB2", subtext: "#A89984",
                accent: "#FABD2F", red: "#FB4934"),
        palette("tokyo-night", "Tokyo Night", bg: "#1A1B26", text: "#C0CAF5", subtext: "#A9B1D6",
                accent: "#7AA2F7", red: "#F7768E"),
        palette("rose-pine", "Rosé Pine", bg: "#191724", text: "#E0DEF4", subtext: "#908CAA",
                accent: "#C4A7E7", red: "#EB6F92"),
        palette("rose-pine-dawn", "Rosé Pine Dawn", bg: "#FAF4ED", text: "#575279", subtext: "#797593",
                accent: "#907AA9", red: "#B4637A", light: true),
        palette("dracula", "Dracula", bg: "#282A36", text: "#F8F8F2", subtext: "#6272A4",
                accent: "#BD93F9", red: "#FF5555"),
        palette("everforest", "Everforest", bg: "#2D353B", text: "#D3C6AA", subtext: "#859289",
                accent: "#A7C080", red: "#E67E80"),
        palette("kanagawa", "Kanagawa", bg: "#1F1F28", text: "#DCD7BA", subtext: "#727169",
                accent: "#7E9CD8", red: "#E82424"),
    ]

    static let builtIn: [ThemePreset] = [standard, midnight, glass, light, sunset, terminal]
    static let all: [ThemePreset] = builtIn + community
}

// MARK: - ThemeColors <-> dictionary

extension IslandConfig.ThemeColors {
    typealias C = IslandConfig.ThemeColors

    static var stringKeys: [(String, WritableKeyPath<C, String>)] {
        [("backgroundStyle", \.backgroundStyle), ("backgroundColor", \.backgroundColor),
         ("material", \.material), ("gradientColor", \.gradientColor),
         ("accentColor", \.accentColor), ("textColor", \.textColor),
         ("secondaryTextColor", \.secondaryTextColor), ("activeTextColor", \.activeTextColor),
         ("fillColor", \.fillColor), ("badgeColor", \.badgeColor),
         ("badgeTextColor", \.badgeTextColor), ("progressColor", \.progressColor),
         ("activeStyle", \.activeStyle)]
    }

    static var numberKeys: [(String, WritableKeyPath<C, Double>)] {
        [("backgroundOpacity", \.backgroundOpacity), ("gradientAngle", \.gradientAngle),
         ("borderOpacity", \.borderOpacity)]
    }

    static var boolKeys: [(String, WritableKeyPath<C, Bool>)] {
        [("shadow", \.shadow), ("activeGlow", \.activeGlow)]
    }

    /// Reads the keys present in `dict` on top of `base`.
    init(dict: [String: Any], base: C) {
        self = base
        for (key, path) in Self.stringKeys {
            if let v = dict[key] as? String { self[keyPath: path] = v }
        }
        for (key, path) in Self.numberKeys {
            if let n = dict[key] as? NSNumber, n.doubleValue.isFinite { self[keyPath: path] = n.doubleValue }
        }
        for (key, path) in Self.boolKeys {
            if let v = dict[key] as? Bool { self[keyPath: path] = v }
        }
    }

    var dictionary: [String: Any] {
        var d: [String: Any] = [:]
        for (key, path) in Self.stringKeys { d[key] = self[keyPath: path] }
        for (key, path) in Self.numberKeys { d[key] = self[keyPath: path] }
        for (key, path) in Self.boolKeys { d[key] = self[keyPath: path] }
        return d
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
        c.trigger.allowShift = t.bool("allowShift", c.trigger.allowShift)

        let b = r.sub("behavior")
        c.behavior.showEventsWithoutModifier = b.bool("showEventsWithoutModifier", c.behavior.showEventsWithoutModifier)
        c.behavior.eventDurationMs = b.number("eventDurationMs", c.behavior.eventDurationMs)
        c.behavior.showWorkspaceSwitch = b.bool("showWorkspaceSwitch", c.behavior.showWorkspaceSwitch)
        c.behavior.showWindowMove = b.bool("showWindowMove", c.behavior.showWindowMove)
        c.behavior.windowMoveTrail = b.bool("windowMoveTrail", c.behavior.windowMoveTrail)
        c.behavior.showEmptyWorkspaces = b.bool("showEmptyWorkspaces", c.behavior.showEmptyWorkspaces)
        c.behavior.screen = b.string("screen", c.behavior.screen)
        c.behavior.hiddenStyle = b.string("hiddenStyle", c.behavior.hiddenStyle)
        c.behavior.showMenuBarIcon = b.bool("showMenuBarIcon", c.behavior.showMenuBarIcon)
        c.behavior.coalesceMs = b.number("coalesceMs", c.behavior.coalesceMs)
        c.behavior.badgeIntervalMs = b.number("badgeIntervalMs", c.behavior.badgeIntervalMs)

        let a = r.sub("appearance")
        c.appearance.colors = ThemeColors(dict: a.dict, base: c.appearance.colors)
        c.appearance.bottomCornerRadius = a.number("bottomCornerRadius", c.appearance.bottomCornerRadius)
        c.appearance.topCornerRadius = a.number("topCornerRadius", c.appearance.topCornerRadius)
        c.appearance.fontSize = a.number("fontSize", c.appearance.fontSize)
        c.appearance.fontFamily = a.string("fontFamily", c.appearance.fontFamily)
        c.appearance.fontDesign = a.string("fontDesign", c.appearance.fontDesign)
        c.appearance.fontWeight = a.string("fontWeight", c.appearance.fontWeight)
        c.appearance.numberFontDesign = a.string("numberFontDesign", c.appearance.numberFontDesign)
        c.appearance.pillSize = a.number("pillSize", c.appearance.pillSize)
        c.appearance.pillSpacing = a.number("pillSpacing", c.appearance.pillSpacing)
        c.appearance.fallbackNotchWidth = a.number("fallbackNotchWidth", c.appearance.fallbackNotchWidth)
        c.appearance.fallbackNotchHeight = a.number("fallbackNotchHeight", c.appearance.fallbackNotchHeight)
        c.appearance.compactRowHeight = a.number("compactRowHeight", c.appearance.compactRowHeight)
        c.appearance.expandedWidth = a.number("expandedWidth", c.appearance.expandedWidth)
        c.appearance.expandedHeaderHeight = a.number("expandedHeaderHeight", c.appearance.expandedHeaderHeight)
        c.appearance.showAppIcons = a.bool("showAppIcons", c.appearance.showAppIcons)
        c.appearance.showEventProgress = a.bool("showEventProgress", c.appearance.showEventProgress)
        c.appearance.workspaceStyle = a.string("workspaceStyle", c.appearance.workspaceStyle)
        c.appearance.appIconSize = a.number("appIconSize", c.appearance.appIconSize)
        c.appearance.maxAppsPerWorkspace = a.number("maxAppsPerWorkspace", c.appearance.maxAppsPerWorkspace)
        c.appearance.showBadges = a.bool("showBadges", c.appearance.showBadges)
        // Older files used a boolean; false meant "merge".
        if !a.bool("showWindowCount", true) { c.appearance.multiWindowStyle = "merge" }
        c.appearance.multiWindowStyle = a.string("multiWindowStyle", c.appearance.multiWindowStyle)
        c.appearance.highlightFocusedWindow = a.bool("highlightFocusedWindow", c.appearance.highlightFocusedWindow)

        let th = r.sub("theme")
        c.theme.mode = th.string("mode", c.theme.mode)
        c.theme.light = ThemeColors(dict: th.sub("light").dict, base: c.theme.light)
        c.theme.saved = th.objects("saved").compactMap { entry in
            guard let name = entry["name"] as? String, !name.isEmpty else { return nil }
            return SavedTheme(name: name, colors: ThemeColors(dict: entry, base: ThemeColors()))
        }

        let l = r.sub("layout")
        c.layout.shape = l.string("shape", c.layout.shape)
        c.layout.topGap = l.number("topGap", c.layout.topGap)
        c.layout.horizontalPosition = l.string("horizontalPosition", c.layout.horizontalPosition)
        c.layout.horizontalOffset = l.number("horizontalOffset", c.layout.horizontalOffset)
        c.layout.widthMode = l.string("widthMode", c.layout.widthMode)
        c.layout.fixedWidth = l.number("fixedWidth", c.layout.fixedWidth)
        c.layout.rowAlignment = l.string("rowAlignment", c.layout.rowAlignment)
        c.layout.contentPadding = l.number("contentPadding", c.layout.contentPadding)
        c.layout.eventPlacement = l.string("eventPlacement", c.layout.eventPlacement)

        let w = r.sub("widgets")
        // Older files hid the focused app with appearance.showFocusedApp.
        if !a.bool("showFocusedApp", true) { c.widgets.leftWing = "none" }
        c.widgets.leftWing = w.string("leftWing", c.widgets.leftWing)
        c.widgets.rightWing = w.string("rightWing", c.widgets.rightWing)
        c.widgets.workspaceLabel = w.string("workspaceLabel", c.widgets.workspaceLabel)
        c.widgets.eventIcon = w.bool("eventIcon", c.widgets.eventIcon)
        c.widgets.eventSubtitle = w.bool("eventSubtitle", c.widgets.eventSubtitle)
        c.widgets.eventFromTo = w.bool("eventFromTo", c.widgets.eventFromTo)
        c.widgets.clockFormat = w.string("clockFormat", c.widgets.clockFormat)
        c.widgets.leftPanel = w.strings("leftPanel", c.widgets.leftPanel)
        c.widgets.rightPanel = w.strings("rightPanel", c.widgets.rightPanel)
        c.widgets.panelUnits = w.number("panelUnits", c.widgets.panelUnits)

        let no = r.sub("notifications")
        c.notifications.enabled = no.bool("enabled", c.notifications.enabled)
        c.notifications.durationMs = no.number("durationMs", c.notifications.durationMs)
        c.notifications.contentMode = no.string("contentMode", c.notifications.contentMode)
        c.notifications.filterMode = no.string("filterMode", c.notifications.filterMode)
        c.notifications.apps = no.strings("apps", c.notifications.apps)
        c.notifications.readDatabase = no.bool("readDatabase", c.notifications.readDatabase)
        c.notifications.dismissSystemBanner = no.bool("dismissSystemBanner", c.notifications.dismissSystemBanner)
        c.notifications.keepIndicator = no.bool("keepIndicator", c.notifications.keepIndicator)
        c.notifications.indicatorTimeoutMin = no.number("indicatorTimeoutMin", c.notifications.indicatorTimeoutMin)
        c.notifications.mergeWindowMs = no.number("mergeWindowMs", c.notifications.mergeWindowMs)

        let ca = r.sub("calendar")
        c.calendar.enabled = ca.bool("enabled", c.calendar.enabled)
        c.calendar.calendars = ca.strings("calendars", c.calendar.calendars)
        c.calendar.alertMinutes = ca.numbers("alertMinutes", c.calendar.alertMinutes)
        c.calendar.showAlerts = ca.bool("showAlerts", c.calendar.showAlerts)
        c.calendar.includeAllDay = ca.bool("includeAllDay", c.calendar.includeAllDay)

        let d = r.sub("dashboard")
        c.dashboard.enabled = d.bool("enabled", c.dashboard.enabled)
        c.dashboard.holdMs = d.number("holdMs", c.dashboard.holdMs)
        c.dashboard.items = d.strings("items", c.dashboard.items)

        let la = r.sub("launcher")
        c.launcher.enabled = la.bool("enabled", c.launcher.enabled)
        c.launcher.hotkey = la.string("hotkey", c.launcher.hotkey)
        c.launcher.englishInput = la.bool("englishInput", c.launcher.englishInput)
        c.launcher.maxResults = la.number("maxResults", c.launcher.maxResults)
        c.launcher.showRecent = la.bool("showRecent", c.launcher.showRecent)
        c.launcher.recentCount = la.number("recentCount", c.launcher.recentCount)
        c.launcher.searchApps = la.bool("searchApps", c.launcher.searchApps)
        c.launcher.searchWindows = la.bool("searchWindows", c.launcher.searchWindows)
        c.launcher.calculator = la.bool("calculator", c.launcher.calculator)
        c.launcher.width = la.number("width", c.launcher.width)
        c.launcher.currency = la.bool("currency", c.launcher.currency)
        c.launcher.searchFiles = la.bool("searchFiles", c.launcher.searchFiles)
        c.launcher.maxFiles = la.number("maxFiles", c.launcher.maxFiles)
        c.launcher.searchSettings = la.bool("searchSettings", c.launcher.searchSettings)
        c.launcher.webSearch = la.bool("webSearch", c.launcher.webSearch)
        c.launcher.suggestions = la.bool("suggestions", c.launcher.suggestions)
        c.launcher.maxSuggestions = la.number("maxSuggestions", c.launcher.maxSuggestions)
        c.launcher.askClaude = la.bool("askClaude", c.launcher.askClaude)
        c.launcher.askGrok = la.bool("askGrok", c.launcher.askGrok)
        c.launcher.searchX = la.bool("searchX", c.launcher.searchX)
        c.launcher.searchClipboard = la.bool("searchClipboard", c.launcher.searchClipboard)
        for (key, value) in la.sub("prefixes").dict {
            if let text = value as? String { c.launcher.prefixes[key] = text.trimmingCharacters(in: .whitespaces) }
        }

        let sh = r.sub("shelf")
        c.shelf.enabled = sh.bool("enabled", c.shelf.enabled)
        c.shelf.maxItems = sh.number("maxItems", c.shelf.maxItems)
        c.shelf.captureImages = sh.bool("captureImages", c.shelf.captureImages)
        c.shelf.captureFiles = sh.bool("captureFiles", c.shelf.captureFiles)
        c.shelf.ignoreApps = sh.strings("ignoreApps", c.shelf.ignoreApps)

        let ag = r.sub("agents")
        c.agents.enabled = ag.bool("enabled", c.agents.enabled)
        c.agents.approvals = ag.bool("approvals", c.agents.approvals)
        c.agents.approvalTimeoutSec = ag.number("approvalTimeoutSec", c.agents.approvalTimeoutSec)
        c.agents.notifyDone = ag.bool("notifyDone", c.agents.notifyDone)
        c.agents.notifyWaiting = ag.bool("notifyWaiting", c.agents.notifyWaiting)
        c.agents.cardDurationMs = ag.number("cardDurationMs", c.agents.cardDurationMs)
        c.agents.keepDoneMin = ag.number("keepDoneMin", c.agents.keepDoneMin)

        let n = r.sub("animation")
        c.motion.style = n.string("style", c.motion.style)
        c.motion.response = n.number("response", c.motion.response)
        c.motion.dampingFraction = n.number("dampingFraction", c.motion.dampingFraction)
        // Files written by older builds carry the old bouncy defaults verbatim;
        // treat them as "never touched" and move them to the calmer spring.
        if abs(c.motion.response - 0.45) < 0.0001 && abs(c.motion.dampingFraction - 0.76) < 0.0001 {
            c.motion.response = IslandConfig.AnimationConfig().response
            c.motion.dampingFraction = IslandConfig.AnimationConfig().dampingFraction
        }
        c.motion.durationMs = n.number("durationMs", c.motion.durationMs)
        c.motion.speed = n.number("speed", c.motion.speed)
        // Older files had a blur on/off switch.
        if !n.bool("blurTransitions", true) { c.motion.contentTransition = "fade" }
        c.motion.contentTransition = n.string("contentTransition", c.motion.contentTransition)
        c.motion.popOnEvent = n.bool("popOnEvent", c.motion.popOnEvent)
        c.motion.liquid = n.bool("liquid", c.motion.liquid)

        return c
    }
}

private struct ConfigReader {
    let dict: [String: Any]
    init(_ dict: [String: Any]) { self.dict = dict }

    func sub(_ key: String) -> ConfigReader {
        ConfigReader(dict[key] as? [String: Any] ?? [:])
    }

    func objects(_ key: String) -> [[String: Any]] {
        (dict[key] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
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

    func strings(_ key: String, _ fallback: [String]) -> [String] {
        guard let array = dict[key] as? [Any] else { return fallback }
        return array.compactMap { $0 as? String }
    }

    func numbers(_ key: String, _ fallback: [Double]) -> [Double] {
        guard let array = dict[key] as? [Any] else { return fallback }
        return array.compactMap { ($0 as? NSNumber)?.doubleValue }.filter(\.isFinite)
    }

    static func expandTilde(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}

// MARK: - Writing

extension IslandConfig {
    static var defaultFileContents: String { IslandConfig().fileContents() }

    fileprivate static func quote(_ s: String?) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [s ?? ""], options: [.withoutEscapingSlashes])
        let array = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return String(array.dropFirst().dropLast())
    }

    fileprivate static func number(_ v: Double) -> String {
        if v.rounded() == v && abs(v) < 1e9 { return String(Int(v)) }
        var text = String(format: "%.3f", v)
        while text.hasSuffix("0") { text.removeLast() }
        return text
    }

    /// The ThemeColors keys as commented JSON5 lines.
    fileprivate static func colorLines(_ c: ThemeColors, indent: String) -> String {
        let q = quote, n = number
        func b(_ v: Bool) -> String { v ? "true" : "false" }
        let lines = [
            "// solid: 단색 | material: 반투명 재질 | gradient: 그라데이션",
            "\"backgroundStyle\": \(q(c.backgroundStyle)),",
            "\"backgroundColor\": \(q(c.backgroundColor)),",
            "// 단색과 그라데이션의 불투명도, 반투명 재질에서는 색을 덧칠하는 강도입니다.",
            "\"backgroundOpacity\": \(n(c.backgroundOpacity)),",
            "// thin | regular | thick (반투명 재질의 두께)",
            "\"material\": \(q(c.material)),",
            "// 그라데이션의 두 번째 색과 방향(0: 왼쪽→오른쪽, 90: 위→아래)입니다.",
            "\"gradientColor\": \(q(c.gradientColor)),",
            "\"gradientAngle\": \(n(c.gradientAngle)),",
            "\"accentColor\": \(q(c.accentColor)),",
            "\"textColor\": \(q(c.textColor)),",
            "\"secondaryTextColor\": \(q(c.secondaryTextColor)),",
            "// 활성 워크스페이스 위의 글자 색입니다.",
            "\"activeTextColor\": \(q(c.activeTextColor)),",
            "// 비활성 워크스페이스 배경, 창 개수 점, 테두리에 옅게 쓰는 기본 색입니다.",
            "// 어두운 테마는 흰색, 밝은 테마는 검정이 어울립니다.",
            "\"fillColor\": \(q(c.fillColor)),",
            "\"badgeColor\": \(q(c.badgeColor)),",
            "\"badgeTextColor\": \(q(c.badgeTextColor)),",
            "// 남은 시간 막대 색입니다. 비워 두면 강조색을 씁니다.",
            "\"progressColor\": \(q(c.progressColor)),",
            "// 가장자리에 얇은 테두리를 그립니다 (0이면 없음).",
            "\"borderOpacity\": \(n(c.borderOpacity)),",
            "\"shadow\": \(b(c.shadow)),",
            "// 활성 워크스페이스 표시: fill(채움) | outline(테두리) | underline(밑줄) | dot(점)",
            "\"activeStyle\": \(q(c.activeStyle)),",
            "\"activeGlow\": \(b(c.activeGlow)),",
        ]
        return lines.map { indent + $0 }.joined(separator: "\n")
    }

    fileprivate static func savedThemeLine(_ theme: SavedTheme) -> String {
        var dict = theme.colors.dictionary
        dict["name"] = theme.name
        let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys, .withoutEscapingSlashes])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    /// Renders the config as commented JSON5. Used for the first-launch file
    /// and every time the settings window saves.
    func fileContents() -> String {
        let q = Self.quote, n = Self.number
        func b(_ v: Bool) -> String { v ? "true" : "false" }
        let t = trigger, be = behavior, a = appearance, an = motion, th = theme, l = layout, w = widgets
        let no = notifications, ca = calendar, d = dashboard, la = launcher, ag = agents, sh = shelf
        func list(_ values: [String]) -> String { "[" + values.map { q($0) }.joined(separator: ", ") + "]" }
        func numberList(_ values: [Double]) -> String { "[" + values.map { n($0) }.joined(separator: ", ") + "]" }
        func prefixList(_ values: [String: String]) -> String {
            let order = ["clipboard", "windows", "settings", "files", "apps"]
            let keys = order.filter { values[$0] != nil } + values.keys.filter { !order.contains($0) }.sorted()
            return "{ " + keys.map { "\(q($0)): \(q(values[$0] ?? ""))" }.joined(separator: ", ") + " }"
        }
        let saved = th.saved.map { "      " + Self.savedThemeLine($0) + "," }.joined(separator: "\n")

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
            // exactMatch가 true여도 Shift를 함께 누른 상태(Option+Shift 등)에서는 보여 줍니다.
            "allowShift": \(b(t.allowShift)),
          },

          "behavior": {
            // modifier를 누르지 않았을 때도 이동이 일어나면 펼쳐서 보여 줍니다.
            "showEventsWithoutModifier": \(b(be.showEventsWithoutModifier)),
            "eventDurationMs": \(n(be.eventDurationMs)),
            "showWorkspaceSwitch": \(b(be.showWorkspaceSwitch)),
            "showWindowMove": \(b(be.showWindowMove)),
            // 창이 옮겨질 때 워크스페이스 줄에서 방울이 흘러가듯 보여 줍니다.
            "windowMoveTrail": \(b(be.windowMoveTrail)),
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
            // 아래 색 값은 어두운 모양(또는 theme.mode가 fixed일 때의 모양)입니다.
        \(Self.colorLines(a.colors, indent: "    "))

            "bottomCornerRadius": \(n(a.bottomCornerRadius)),
            "topCornerRadius": \(n(a.topCornerRadius)),
            "fontSize": \(n(a.fontSize)),
            // 설치된 글꼴 이름입니다. 비워 두면 시스템 글꼴을 씁니다.
            "fontFamily": \(q(a.fontFamily)),
            // default | rounded | monospaced | serif
            "fontDesign": \(q(a.fontDesign)),
            // light | regular | bold | heavy
            "fontWeight": \(q(a.fontWeight)),
            // 워크스페이스 번호와 이름의 글꼴: same(본문과 같게) | default | rounded | monospaced | serif
            "numberFontDesign": \(q(a.numberFontDesign)),
            "pillSize": \(n(a.pillSize)),
            "pillSpacing": \(n(a.pillSpacing)),
            "fallbackNotchWidth": \(n(a.fallbackNotchWidth)),
            "fallbackNotchHeight": \(n(a.fallbackNotchHeight)),
            "compactRowHeight": \(n(a.compactRowHeight)),
            "expandedWidth": \(n(a.expandedWidth)),
            "expandedHeaderHeight": \(n(a.expandedHeaderHeight)),
            "showAppIcons": \(b(a.showAppIcons)),
            // 펼쳐진 상태가 끝날 때까지 남은 시간을 아래쪽 막대로 보여 줍니다.
            "showEventProgress": \(b(a.showEventProgress)),
            // apps: 워크스페이스 번호 옆에 앱 아이콘을 나열 (OmniWM 바와 비슷)
            // pills: 번호만 있는 작은 알약
            "workspaceStyle": \(q(a.workspaceStyle)),
            "appIconSize": \(n(a.appIconSize)),
            "maxAppsPerWorkspace": \(n(a.maxAppsPerWorkspace)),
            // Dock에 뜨는 빨간 알림 배지를 앱 아이콘에 표시합니다 (손쉬운 사용 권한 필요).
            "showBadges": \(b(a.showBadges)),
            // 한 앱의 창이 그 워크스페이스에 여러 개일 때 보여 주는 방식입니다.
            // merge: 아이콘 하나로 합침, dots: 아이콘 아래에 창 개수만큼 점(최대 3개),
            // separate: 창마다 아이콘을 따로 표시
            "multiWindowStyle": \(q(a.multiWindowStyle)),
            // 지금 포커스된 창의 아이콘을 강조색 테두리로 표시합니다.
            "highlightFocusedWindow": \(b(a.highlightFocusedWindow)),
          },

          "theme": {
            // fixed: 항상 appearance의 색을 씁니다.
            // system: macOS가 다크 모드면 appearance, 라이트 모드면 아래 light의 색을 씁니다.
            "mode": \(q(th.mode)),
            "light": {
        \(Self.colorLines(th.light, indent: "      "))
            },
            // 설정 창에서 "내 테마로 저장"한 테마입니다.
            "saved": [
        \(saved)
            ],
          },

          "layout": {
            // attached: 노치에서 자라나는 모양 | floating: 메뉴 막대 아래에 떠 있는 캡슐
            "shape": \(q(l.shape)),
            // 떠 있는 형태에서 메뉴 막대와 아일랜드 사이의 간격입니다.
            "topGap": \(n(l.topGap)),
            // center | left | right (노치가 있는 화면에서는 항상 가운데)
            "horizontalPosition": \(q(l.horizontalPosition)),
            "horizontalOffset": \(n(l.horizontalOffset)),
            // auto: 내용에 맞춤 | fixed: fixedWidth 이상으로 고정
            "widthMode": \(q(l.widthMode)),
            "fixedWidth": \(n(l.fixedWidth)),
            // 워크스페이스 줄 정렬: center | leading | spread
            "rowAlignment": \(q(l.rowAlignment)),
            "contentPadding": \(n(l.contentPadding)),
            // 이동 알림 위치: below(워크스페이스 줄 아래) | above(위) | replace(줄 대신)
            "eventPlacement": \(q(l.eventPlacement)),
          },

          "widgets": {
            // 노치 양옆에 보여 줄 내용:
            // app | workspace | clock | date | windows | nextEvent(다음 일정) | notifications(놓친 알림 수) | none
            "leftWing": \(q(w.leftWing)),
            "rightWing": \(q(w.rightWing)),
            // 워크스페이스 이름: name(OmniWM 표시 이름) | number(번호) | both(번호와 이름)
            "workspaceLabel": \(q(w.workspaceLabel)),
            // 이동 알림에 아이콘, 부제목(창 제목), "출발 → 도착"을 보여 줄지 정합니다.
            "eventIcon": \(b(w.eventIcon)),
            "eventSubtitle": \(b(w.eventSubtitle)),
            "eventFromTo": \(b(w.eventFromTo)),
            // 24h | 12h | 24hSeconds
            "clockFormat": \(q(w.clockFormat)),
            // 워크스페이스 줄이 보일 때 좌우에 붙는 정사각형 위젯 칸입니다. 비우면 그쪽 칸이 없습니다.
            // clock(시계) | calendar(달력) | nextEvent(다음 일정) | events(오늘 일정) | notifications(최근 알림)
            "leftPanel": \(list(w.leftPanel)),
            "rightPanel": \(list(w.rightPanel)),
            // 한쪽 칸의 너비를 정사각형 몇 칸으로 할지 정합니다 (1~3).
            "panelUnits": \(n(w.panelUnits)),
          },

          "notifications": {
            // macOS 알림 배너를 읽어 아일랜드에 보여 줍니다 (손쉬운 사용 권한 필요).
            "enabled": \(b(no.enabled)),
            "durationMs": \(n(no.durationMs)),
            // full(전체) | title(제목까지) | app(앱 이름만)
            "contentMode": \(q(no.contentMode)),
            // all(모든 앱) | allow(apps에 적은 앱만) | block(apps에 적은 앱 빼고)
            "filterMode": \(q(no.filterMode)),
            // 앱 이름이나 번들 ID를 적습니다. 예: ["Slack", "com.apple.MobileSMS"]
            "apps": \(list(no.apps)),
            // macOS 알림 데이터베이스도 읽습니다 (전체 디스크 접근 권한 필요).
            // 배너를 꺼 둔 앱의 알림도 볼 수 있습니다.
            "readDatabase": \(b(no.readDatabase)),
            // 내용을 읽은 직후 macOS 기본 배너를 닫습니다.
            "dismissSystemBanner": \(b(no.dismissSystemBanner)),
            // 알림이 접힌 뒤에도 노치 옆에 놓친 알림 아이콘을 남깁니다.
            "keepIndicator": \(b(no.keepIndicator)),
            "indicatorTimeoutMin": \(n(no.indicatorTimeoutMin)),
            // 같은 앱에서 이 시간 안에 온 알림은 한 장으로 합칩니다.
            "mergeWindowMs": \(n(no.mergeWindowMs)),
          },

          "calendar": {
            // 켜면 캘린더 접근 권한을 묻습니다.
            "enabled": \(b(ca.enabled)),
            // 사용할 캘린더 이름. 비워 두면 전체를 씁니다.
            "calendars": \(list(ca.calendars)),
            // 일정 시작 몇 분 전에 알릴지 정합니다 (0은 시작 시각).
            "alertMinutes": \(numberList(ca.alertMinutes)),
            "showAlerts": \(b(ca.showAlerts)),
            "includeAllDay": \(b(ca.includeAllDay)),
          },

          "dashboard": {
            // modifier를 더 길게 누르면 시계, 오늘 일정, 최근 알림을 보여 줍니다.
            "enabled": \(b(d.enabled)),
            // 워크스페이스 줄이 나타난 뒤 이만큼 더 누르고 있으면 펼칩니다.
            "holdMs": \(n(d.holdMs)),
            // clock | events | notifications (적은 순서대로 보여 줍니다)
            "items": \(list(d.items)),
          },

          "launcher": {
            // 단축키를 누르면 아일랜드가 펼쳐지면서 앱과 창을 검색할 수 있습니다.
            "enabled": \(b(la.enabled)),
            // option+h | option+space | control+space | option+command+space ...
            "hotkey": \(q(la.hotkey)),
            // 런처를 열 때 입력 소스를 영어로 바꾸고, 닫으면 원래 입력 소스로 되돌립니다.
            "englishInput": \(b(la.englishInput)),
            "maxResults": \(n(la.maxResults)),
            // 검색어가 없을 때 최근에 연 앱을 보여 줍니다.
            "showRecent": \(b(la.showRecent)),
            "recentCount": \(n(la.recentCount)),
            "searchApps": \(b(la.searchApps)),
            // OmniWM이 관리하는 창을 검색합니다. Return은 그 창으로 이동, ⌘Return은 지금 워크스페이스로 불러옵니다.
            "searchWindows": \(b(la.searchWindows)),
            // 2^10*3 같은 수식을 계산합니다. Return을 누르면 결과를 복사합니다.
            "calculator": \(b(la.calculator)),
            // 100 USD to KRW, 100달러처럼 입력하면 ECB 기준 환율로 바꿉니다 (Frankfurter).
            "currency": \(b(la.currency)),
            // 홈 폴더의 파일을 Spotlight 색인에서 찾습니다.
            "searchFiles": \(b(la.searchFiles)),
            "maxFiles": \(n(la.maxFiles)),
            // 시스템 설정 패널("wifi", "다크 모드")과 OmniIsland 설정을 찾습니다.
            "searchSettings": \(b(la.searchSettings)),
            // "Google에서 검색" 줄과 Google 추천 검색어입니다.
            // 추천 검색어는 입력한 글자를 Google에 보냅니다 (주소처럼 보이는 입력은 보내지 않습니다).
            "webSearch": \(b(la.webSearch)),
            "suggestions": \(b(la.suggestions)),
            "maxSuggestions": \(n(la.maxSuggestions)),
            "askClaude": \(b(la.askClaude)),
            "askGrok": \(b(la.askGrok)),
            "searchX": \(b(la.searchX)),
            // 복사 기록도 기본 검색에 섞어서 보여 줍니다. 꺼 두어도 "c "로 클립보드 관리자에 들어갈 수 있습니다.
            "searchClipboard": \(b(la.searchClipboard)),
            "width": \(n(la.width)),
            // 내장 앱의 트리거 접두어입니다. 접두어 다음에 스페이스를 누르면 그 앱만 보입니다.
            // 한글 자판으로 친 글자(ㅊ, ㅈ, ㄴ, ㄹ)도 됩니다. ""로 두면 접두어를 쓰지 않습니다.
            // clipboard: 클립보드 관리자, windows: 창 관리자, settings: 설정 관리자, files: 파일 검색, apps: 앱
            "prefixes": \(prefixList(la.prefixes)),
          },

          "shelf": {
            // 클립보드 관리자: 복사한 텍스트, 이미지, 파일을 기억합니다.
            // 런처(⌥H)에서 "c "를 입력하면 기록이 나오고, Return으로 붙여넣습니다.
            "enabled": \(b(sh.enabled)),
            "maxItems": \(n(sh.maxItems)),
            "captureImages": \(b(sh.captureImages)),
            "captureFiles": \(b(sh.captureFiles)),
            // 여기 적은 앱(번들 ID나 이름)에서 복사한 것은 담지 않습니다. 비밀번호 관리자는 항상 뺍니다.
            "ignoreApps": \(list(sh.ignoreApps)),
          },

          "agents": {
            // Claude Code·Codex 훅이 보내는 상태를 아일랜드에 보여 줍니다.
            // 훅은 설정 창의 에이전트 탭에서 설치합니다.
            "enabled": \(b(ag.enabled)),
            // 권한 요청에 허용·거부 버튼을 띄웁니다. 시간 안에 답하지 않으면 터미널에서 묻습니다.
            "approvals": \(b(ag.approvals)),
            "approvalTimeoutSec": \(n(ag.approvalTimeoutSec)),
            "notifyDone": \(b(ag.notifyDone)),
            "notifyWaiting": \(b(ag.notifyWaiting)),
            "cardDurationMs": \(n(ag.cardDurationMs)),
            // 끝난 세션을 에이전트 위젯에 남겨 두는 시간(분)입니다.
            "keepDoneMin": \(n(ag.keepDoneMin)),
          },

          "animation": {
            // spring | bouncy | smooth | snappy | easeInOut | none
            "style": \(q(an.style)),
            "response": \(n(an.response)),
            "dampingFraction": \(n(an.dampingFraction)),
            "durationMs": \(n(an.durationMs)),
            // 모든 움직임의 속도 배율입니다 (1이 기본).
            "speed": \(n(an.speed)),
            // 내용이 나타나는 방식: blur | fade | slide | none
            "contentTransition": \(q(an.contentTransition)),
            "popOnEvent": \(b(an.popOnEvent)),
            // 좌우 칸이 액체 방울처럼 떨어져 나오고, 활성 표시가 끈적하게 늘어나며 옮겨 갑니다.
            "liquid": \(b(an.liquid)),
          },
        }

        """
    }
}
