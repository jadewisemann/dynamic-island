import AppKit
import SwiftUI

enum IslandPhase: Equatable {
    /// Collapsed to the notch (or faded out on screens without one).
    case hidden
    /// Modifier held: workspace row below the notch.
    case compact
    /// A move just happened: compact row plus an event header.
    case expanded
}

/// Size of the hardware notch (or a stand-in on screens without one).
struct NotchGeometry: Equatable {
    var width: CGFloat
    var height: CGFloat
    var hasNotch: Bool
}

/// All state the SwiftUI view renders, plus the show/hide state machine.
@MainActor
final class IslandModel: ObservableObject {
    @Published private(set) var phase: IslandPhase = .hidden
    @Published private(set) var workspaces: [WorkspaceItem] = []
    @Published private(set) var activeWorkspaceKey: String?
    @Published private(set) var activeWorkspaceLabel: String?
    @Published private(set) var activeWorkspaceNumber: Int?
    @Published private(set) var focusedApp: AppRef?
    @Published private(set) var event: IslandEvent?
    @Published private(set) var eventSerial = 0
    @Published private(set) var config = IslandConfig()
    /// Dock notification badges, keyed by lower-cased bundle id.
    @Published private(set) var badges: [String: String] = [:]
    @Published var geometry = NotchGeometry(width: 200, height: 32, hasNotch: false)
    /// Whether macOS currently uses dark mode (for theme.mode = system).
    @Published var systemIsDark = true
    /// Settings preview only: forces the light (true) or dark (false) look.
    @Published var lookOverride: Bool?
    /// The settings window preview draws materials within its own window.
    var isPreview = false

    private(set) var modifierHeld = false
    private var showWork: DispatchWorkItem?
    private var hideWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var coalesceWork: DispatchWorkItem?
    private var pendingEvent: IslandEvent?

    // MARK: - Inputs

    func apply(config: IslandConfig) {
        animate { self.config = config }
    }

    func update(from tracker: WMStateTracker) {
        let items = tracker.workspaceItems(displayId: nil, includeEmpty: config.behavior.showEmptyWorkspaces)
        let key = tracker.activeWorkspace?.key
        let label = tracker.activeWorkspace?.label
        let number = tracker.activeWorkspace?.number
        let app = tracker.focusedApp
        guard items != workspaces || key != activeWorkspaceKey || label != activeWorkspaceLabel
                || number != activeWorkspaceNumber || app != focusedApp
        else { return }
        animate {
            self.workspaces = items
            self.activeWorkspaceKey = key
            self.activeWorkspaceLabel = label
            self.activeWorkspaceNumber = number
            self.focusedApp = app
        }
    }

    /// Fills the model with sample workspaces for the settings preview.
    func loadSample() {
        func app(_ name: String, _ bundle: String, windows: Int = 1, focused: Bool = false) -> WorkspaceApp {
            WorkspaceApp(id: bundle.lowercased(), name: name, bundleId: bundle, windowCount: windows, isFocused: focused)
        }
        func ws(_ n: Int, _ name: String, _ apps: [WorkspaceApp]) -> WorkspaceItem {
            WorkspaceItem(id: "sample-\(n)", label: name, number: n, displayId: nil, displayName: nil,
                          windowCount: apps.reduce(0) { $0 + $1.windowCount }, isVisible: n == 1,
                          apps: apps, windows: apps)
        }
        workspaces = [
            ws(1, "web", [app("Finder", "com.apple.finder", focused: true), app("Safari", "com.apple.Safari", windows: 2)]),
            ws(2, "chat", [app("Messages", "com.apple.MobileSMS")]),
            ws(3, "dev", [app("Terminal", "com.apple.Terminal")]),
            ws(4, "mail", [app("Mail", "com.apple.mail"), app("System Settings", "com.apple.systempreferences")]),
        ]
        activeWorkspaceKey = "sample-1"
        activeWorkspaceLabel = "web"
        activeWorkspaceNumber = 1
        focusedApp = AppRef(name: "Finder", bundleId: "com.apple.finder")
        badges = ["com.apple.mobilesms": "2"]
    }

    /// Settings preview: shows a phase and stays there.
    func showSample(_ next: IslandPhase) {
        collapseWork?.cancel()
        animate {
            if next == .expanded {
                self.event = .windowMove(
                    app: AppRef(name: "Safari", bundleId: "com.apple.Safari"), title: "OmniWM – GitHub",
                    from: WorkspaceRef(id: "sample-1", rawName: "web", displayName: "web", number: 1),
                    to: WorkspaceRef(id: "sample-3", rawName: "dev", displayName: "dev", number: 3), count: 1)
                self.eventSerial &+= 1
            }
            self.phase = next
        }
    }

    func setBadges(_ labels: [String: String]) {
        guard labels != badges else { return }
        animate { self.badges = labels }
    }

    func badge(for app: WorkspaceApp) -> String? {
        guard config.appearance.showBadges, let id = app.bundleId?.lowercased() else { return nil }
        return badges[id]
    }

    func modifierChanged(held: Bool) {
        modifierHeld = held
        showWork?.cancel()
        hideWork?.cancel()
        if held {
            showWork = after(ms: config.trigger.holdDelayMs) { [weak self] in
                guard let self, self.modifierHeld, self.phase == .hidden else { return }
                self.setPhase(.compact)
            }
        } else {
            hideWork = after(ms: config.trigger.hideDelayMs) { [weak self] in
                guard let self, !self.modifierHeld, self.phase == .compact else { return }
                self.setPhase(.hidden)
            }
        }
    }

    func present(_ event: IslandEvent) {
        switch event {
        case .workspaceSwitch where !config.behavior.showWorkspaceSwitch: return
        case .windowMove where !config.behavior.showWindowMove: return
        default: break
        }
        if !config.behavior.showEventsWithoutModifier && !modifierHeld && phase == .hidden { return }

        // Coalesce: a window move usually arrives together with the workspace
        // switch that follows it; keep the more informative one.
        if let pending = pendingEvent, pending.priority > event.priority {
            return
        }
        pendingEvent = event
        guard coalesceWork == nil else { return }
        coalesceWork = after(ms: config.behavior.coalesceMs) { [weak self] in
            guard let self else { return }
            self.coalesceWork = nil
            guard let e = self.pendingEvent else { return }
            self.pendingEvent = nil
            self.show(e)
        }
    }

    /// Plays a fake event so the animation can be previewed without OmniWM.
    func preview(_ event: IslandEvent) {
        show(event)
    }

    // MARK: - Derived layout

    var hiddenStyleFades: Bool {
        switch config.behavior.hiddenStyle.lowercased() {
        case "notch": return false
        case "fade": return true
        default: return !geometry.hasNotch
        }
    }

    // MARK: Look

    /// True when the light colors (theme.light) are in use.
    var usesLightLook: Bool {
        if let lookOverride { return lookOverride && config.theme.mode.lowercased() == "system" }
        return config.theme.mode.lowercased() == "system" && !systemIsDark
    }

    var colors: IslandConfig.ThemeColors {
        usesLightLook ? config.theme.light : config.appearance.colors
    }

    var palette: IslandPalette { IslandPalette(colors) }

    // MARK: Fonts

    private static let fontWeights: [Font.Weight] = [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black]
    private static let nsFontWeights: [NSFont.Weight] = [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black]
    /// NSFontManager weights (0–15) matching `nsFontWeights`.
    private static let managerWeights = [1, 2, 3, 5, 6, 8, 9, 11, 12]

    private var weightShift: Int {
        switch config.appearance.fontWeight.lowercased() {
        case "light": return -1
        case "bold": return 1
        case "heavy": return 2
        default: return 0
        }
    }

    private func shiftedIndex(_ index: Int) -> Int {
        min(max(index + weightShift, 0), Self.fontWeights.count - 1)
    }

    private static func design(_ name: String) -> Font.Design? {
        switch name.lowercased() {
        case "default": return .default
        case "rounded": return .rounded
        case "monospaced": return .monospaced
        case "serif": return .serif
        default: return nil
        }
    }

    private static func nsDesign(_ name: String) -> NSFontDescriptor.SystemDesign? {
        switch name.lowercased() {
        case "default": return .default
        case "rounded": return .rounded
        case "monospaced": return .monospaced
        case "serif": return .serif
        default: return nil
        }
    }

    private var numberUsesTextFont: Bool {
        let d = config.appearance.numberFontDesign.lowercased()
        return d == "same" || d.isEmpty
    }

    /// Font for running text (app names, event titles).
    func textFont(size: CGFloat, weight: Font.Weight) -> Font {
        let a = config.appearance
        let index = Self.fontWeights.firstIndex(of: weight) ?? 3
        let w = Self.fontWeights[shiftedIndex(index)]
        if !a.fontFamily.isEmpty {
            return .custom(a.fontFamily, size: size).weight(w)
        }
        return .system(size: size, weight: w, design: Self.design(a.fontDesign) ?? .default)
    }

    /// Font for workspace numbers and names.
    func numberFont(size: CGFloat, weight: Font.Weight) -> Font {
        if numberUsesTextFont { return textFont(size: size, weight: weight) }
        let index = Self.fontWeights.firstIndex(of: weight) ?? 3
        let w = Self.fontWeights[shiftedIndex(index)]
        return .system(size: size, weight: w, design: Self.design(config.appearance.numberFontDesign) ?? .rounded)
    }

    /// AppKit twin of `numberFont`, used to measure labels.
    func numberNSFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let a = config.appearance
        let index = shiftedIndex(Self.nsFontWeights.firstIndex(of: weight) ?? 3)
        let w = Self.nsFontWeights[index]
        if numberUsesTextFont && !a.fontFamily.isEmpty {
            if let font = NSFontManager.shared.font(withFamily: a.fontFamily, traits: [],
                                                    weight: Self.managerWeights[index], size: size) {
                return font
            }
        }
        let base = NSFont.systemFont(ofSize: size, weight: w)
        let designName = numberUsesTextFont ? a.fontDesign : a.numberFontDesign
        if let design = Self.nsDesign(designName), let descriptor = base.fontDescriptor.withDesign(design),
           let font = NSFont(descriptor: descriptor, size: size) {
            return font
        }
        return base
    }

    var pillFont: NSFont {
        numberNSFont(size: CGFloat(config.appearance.fontSize) * 0.9, weight: .semibold)
    }

    var pillSwiftUIFont: Font {
        numberFont(size: CGFloat(config.appearance.fontSize) * 0.9, weight: .semibold)
    }

    // MARK: Labels

    /// A workspace name in the format chosen in widgets.workspaceLabel.
    func label(_ name: String, number: Int?) -> String {
        guard let number else { return name }
        switch config.widgets.workspaceLabel.lowercased() {
        case "number": return String(number)
        case "both": return name == String(number) || name.isEmpty ? String(number) : "\(number) \(name)"
        default: return name
        }
    }

    func label(for ws: WorkspaceItem) -> String { label(ws.label, number: ws.number) }
    func label(for ref: WorkspaceRef) -> String { label(ref.label, number: ref.number) }

    var activeWorkspaceText: String? {
        activeWorkspaceLabel.map { label($0, number: activeWorkspaceNumber) }
    }

    func pillWidth(for label: String) -> CGFloat {
        let text = (label as NSString).size(withAttributes: [.font: pillFont]).width
        return max(CGFloat(config.appearance.pillSize), ceil(text) + 14)
    }

    // MARK: Layout

    var isFloating: Bool { config.layout.shape.lowercased() == "floating" }

    /// Horizontal placement; screens with a notch always center on it.
    var horizontalPosition: String {
        geometry.hasNotch ? "center" : config.layout.horizontalPosition.lowercased()
    }

    /// Height of the strip beside the notch (none when floating).
    var topStripHeight: CGFloat { isFloating ? 0 : geometry.height }

    /// How far a floating island sits below the top of the screen.
    var floatingTop: CGFloat { geometry.height + CGFloat(max(config.layout.topGap, 0)) }

    var contentPadding: CGFloat { CGFloat(max(config.layout.contentPadding, 0)) }

    enum EventPlacement { case below, above, replace }

    var eventPlacement: EventPlacement {
        switch config.layout.eventPlacement.lowercased() {
        case "above": return .above
        case "replace": return .replace
        default: return .below
        }
    }

    /// Room one wing widget needs beside the notch.
    func wingWidth(_ widget: String) -> CGFloat {
        switch widget.lowercased() {
        case "app": return 76
        case "clock": return config.widgets.clockFormat.lowercased() == "24h" ? 52 : 70
        case "date": return 84
        case "windows": return 40
        case "workspace":
            let text = activeWorkspaceText ?? ""
            return max(28, ceil((text as NSString).size(withAttributes: [.font: pillFont]).width) + 20)
        default: return isFloating ? 0 : 28
        }
    }

    var leftWingWidth: CGFloat { wingWidth(config.widgets.leftWing) }
    var rightWingWidth: CGFloat { wingWidth(config.widgets.rightWing) }

    /// Number of windows on the active workspace (windows widget).
    var activeWindowCount: Int {
        workspaces.first { $0.id == activeWorkspaceKey }?.windowCount ?? 0
    }

    var usesAppStyle: Bool { config.appearance.workspaceStyle.lowercased() != "pills" }

    enum ActiveStyle { case fill, outline, underline, dot }

    var activeStyle: ActiveStyle {
        switch colors.activeStyle.lowercased() {
        case "outline": return .outline
        case "underline": return .underline
        case "dot": return .dot
        default: return .fill
        }
    }

    enum MultiWindowStyle { case merge, dots, separate }

    var multiWindowStyle: MultiWindowStyle {
        switch config.appearance.multiWindowStyle.lowercased() {
        case "merge": return .merge
        case "separate": return .separate
        default: return .dots
        }
    }

    /// Icons for one workspace group, following `multiWindowStyle`.
    func displayedApps(for ws: WorkspaceItem) -> [WorkspaceApp] {
        multiWindowStyle == .separate && !ws.windows.isEmpty ? ws.windows : ws.apps
    }

    var maxAppsPerWorkspace: Int { max(1, Int(config.appearance.maxAppsPerWorkspace)) }

    static let appIconGap: CGFloat = 4
    static let groupPadding: CGFloat = 8

    /// Width of one workspace group in the "apps" style:
    /// [pad] label [gap] icon icon … (+N) [pad]
    func groupWidth(for ws: WorkspaceItem) -> CGFloat {
        let a = config.appearance
        let labelWidth = pillWidth(for: label(for: ws)) - 8
        let apps = displayedApps(for: ws)
        let shown = min(apps.count, maxAppsPerWorkspace)
        var width = Self.groupPadding * 2 + labelWidth
        if shown > 0 {
            width += CGFloat(shown) * (CGFloat(a.appIconSize) + Self.appIconGap)
        }
        if apps.count > shown {
            width += pillWidth(for: "+\(apps.count - shown)") - 4
        }
        return ceil(width)
    }

    var rowHeight: CGFloat {
        let a = config.appearance
        let needed = usesAppStyle ? CGFloat(a.appIconSize) + 16 : CGFloat(a.pillSize) + 12
        return max(CGFloat(a.compactRowHeight), needed)
    }

    var rowContentWidth: CGFloat {
        let a = config.appearance
        let items = workspaces.map { usesAppStyle ? groupWidth(for: $0) : pillWidth(for: label(for: $0)) }
        let spacing = CGFloat(a.pillSpacing) * CGFloat(max(workspaces.count - 1, 0))
        return items.reduce(0, +) + spacing
    }

    private var fixedWidth: CGFloat {
        config.layout.widthMode.lowercased() == "fixed" ? CGFloat(config.layout.fixedWidth) : 0
    }

    var compactSize: CGSize {
        let padding = contentPadding * 2
        if isFloating {
            let wings = leftWingWidth + rightWingWidth
            let gaps: CGFloat = (leftWingWidth > 0 ? 10 : 0) + (rightWingWidth > 0 ? 10 : 0)
            let width = max(rowContentWidth + padding + wings + gaps, fixedWidth, 120)
            return CGSize(width: width, height: rowHeight)
        }
        let wings = max(leftWingWidth, rightWingWidth)
        let width = max(geometry.width + 2 * wings, rowContentWidth + padding, fixedWidth)
        return CGSize(width: width, height: geometry.height + rowHeight)
    }

    var expandedSize: CGSize {
        let a = config.appearance
        let width = max(CGFloat(a.expandedWidth), compactSize.width)
        let row = eventPlacement == .replace ? 0 : rowHeight
        return CGSize(width: width, height: topStripHeight + row + CGFloat(a.expandedHeaderHeight))
    }

    var currentSize: CGSize {
        switch phase {
        case .hidden: return CGSize(width: geometry.width, height: geometry.height)
        case .compact: return compactSize
        case .expanded: return expandedSize
        }
    }

    /// Distance from the top of the screen to the island's top edge.
    var currentTopOffset: CGFloat {
        isFloating && phase != .hidden ? floatingTop : 0
    }

    /// Largest size the island can take, including the floating gap; the
    /// panel is sized from this.
    var maximumSize: CGSize {
        let e = expandedSize
        let c = compactSize
        let height = max(e.height, c.height) + (isFloating ? floatingTop : 0)
        return CGSize(width: max(e.width, 520), height: max(height, geometry.height))
    }

    var swiftUIAnimation: Animation? {
        let n = config.motion
        let d = max(n.durationMs, 1) / 1000
        let base: Animation
        switch n.style.lowercased() {
        case "none": return nil
        case "easeinout", "ease": base = .easeInOut(duration: d)
        case "bouncy": base = .bouncy(duration: d)
        case "smooth": base = .smooth(duration: d)
        case "snappy": base = .snappy(duration: d)
        default:
            base = .spring(response: max(n.response, 0.05), dampingFraction: min(max(n.dampingFraction, 0.05), 1))
        }
        let speed = min(max(n.speed, 0.1), 5)
        return speed == 1 ? base : base.speed(speed)
    }

    // MARK: - State machine

    private func show(_ event: IslandEvent) {
        collapseWork?.cancel()
        animate {
            self.event = event
            self.eventSerial &+= 1
            self.phase = .expanded
        }
        collapseWork = after(ms: config.behavior.eventDurationMs) { [weak self] in
            guard let self else { return }
            self.setPhase(self.modifierHeld ? .compact : .hidden)
        }
    }

    private func setPhase(_ next: IslandPhase) {
        guard next != phase else { return }
        animate { self.phase = next }
    }

    private func animate(_ body: () -> Void) {
        withAnimation(swiftUIAnimation, body)
    }

    @discardableResult
    private func after(ms: Double, _ body: @escaping @MainActor () -> Void) -> DispatchWorkItem {
        let work = DispatchWorkItem {
            MainActor.assumeIsolated { body() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + max(ms, 0) / 1000, execute: work)
        return work
    }
}

/// Resolved colors for one look. Views use these instead of fixed colors
/// so light themes work.
struct IslandPalette {
    let colors: IslandConfig.ThemeColors
    let background: Color
    let gradientEnd: Color
    let text: Color
    let secondary: Color
    let accent: Color
    let activeText: Color
    /// Base for low-opacity fills (inactive workspaces, dots, border).
    let fill: Color
    let badge: Color
    let badgeText: Color
    let progress: Color

    init(_ c: IslandConfig.ThemeColors) {
        colors = c
        background = Color(hex: c.backgroundColor)
        gradientEnd = Color(hex: c.gradientColor)
        text = Color(hex: c.textColor, fallback: .white)
        secondary = Color(hex: c.secondaryTextColor, fallback: .gray)
        accent = Color(hex: c.accentColor, fallback: .blue)
        activeText = Color(hex: c.activeTextColor, fallback: .white)
        fill = Color(hex: c.fillColor, fallback: .white)
        badge = Color(hex: c.badgeColor, fallback: Color(red: 1, green: 0.23, blue: 0.19))
        badgeText = Color(hex: c.badgeTextColor, fallback: .white)
        progress = c.progressColor.isEmpty ? accent : Color(hex: c.progressColor, fallback: accent)
    }

    /// True when the text is light, i.e. the theme is dark (for materials).
    var isDark: Bool {
        let ns = NSColor(text).usingColorSpace(.sRGB) ?? .white
        let luminance = 0.2126 * ns.redComponent + 0.7152 * ns.greenComponent + 0.0722 * ns.blueComponent
        return luminance > 0.5
    }
}
