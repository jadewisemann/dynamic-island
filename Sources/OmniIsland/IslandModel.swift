import AppKit
import SwiftUI

enum IslandPhase: Equatable {
    /// Collapsed to the notch (or faded out on screens without one).
    case hidden
    /// Modifier held: workspace row below the notch.
    case compact
    /// A move just happened: compact row plus an event header.
    case expanded
    /// A macOS notification (or calendar alert) card.
    case notification
    /// Modifier held longer: workspace row plus clock, events and recent
    /// notifications.
    case dashboard

    /// Phases that the modifier opened and that close when it is released.
    var isModifierPhase: Bool { self == .compact || self == .dashboard }
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
    /// The notification card on screen (phase .notification).
    @Published private(set) var notification: IslandNotification?
    /// How many times the current card was merged with a newer one.
    @Published private(set) var notificationMergeCount = 0
    /// Notifications waiting for their turn.
    @Published private(set) var notificationQueue: [IslandNotification] = []
    /// Shown but not yet looked at: drawn beside the notch while hidden.
    @Published private(set) var missedNotifications: [IslandNotification] = []
    /// Most recent first, for the dashboard.
    @Published private(set) var recentNotifications: [IslandNotification] = []
    /// Today's and tomorrow's calendar events, sorted by start.
    @Published private(set) var calendarEvents: [CalendarEvent] = []
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
    private var dashboardWork: DispatchWorkItem?
    private var notificationWork: DispatchWorkItem?
    private var notificationShownAt = Date.distantPast

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
        let now = Date()
        func event(_ id: String, _ title: String, in minutes: Double, length: Double, color: String) -> CalendarEvent {
            CalendarEvent(id: id, title: title, start: now.addingTimeInterval(minutes * 60),
                          end: now.addingTimeInterval((minutes + length) * 60), isAllDay: false,
                          location: nil, calendarTitle: "샘플", colorHex: color)
        }
        calendarEvents = [
            event("sample-a", "디자인 리뷰", in: 12, length: 30, color: "#FF9F0A"),
            event("sample-b", "1:1 미팅", in: 160, length: 30, color: "#30D158"),
            event("sample-c", "저녁 약속", in: 330, length: 90, color: "#64D2FF"),
        ]
        recentNotifications = [
            IslandNotification(source: .system, appName: "메시지", bundleId: "com.apple.MobileSMS",
                               title: "민지", body: "테마 시안 확인했어요", date: now.addingTimeInterval(-180)),
            IslandNotification(source: .system, appName: "메일", bundleId: "com.apple.mail",
                               title: "주간 보고", date: now.addingTimeInterval(-1200)),
        ]
    }

    /// Settings preview: shows a phase and stays there.
    func showSample(_ next: IslandPhase) {
        if next == .notification {
            showSampleNotification()
            return
        }
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
        dashboardWork?.cancel()
        if held {
            showWork = after(ms: config.trigger.holdDelayMs) { [weak self] in
                guard let self, self.modifierHeld else { return }
                if self.phase == .notification {
                    // Make way for the workspace row; the card comes back later.
                    self.interruptNotification()
                }
                guard self.phase == .hidden else { return }
                self.clearMissed()
                self.setPhase(.compact)
                self.scheduleDashboard()
            }
        } else {
            hideWork = after(ms: config.trigger.hideDelayMs) { [weak self] in
                guard let self, !self.modifierHeld, self.phase.isModifierPhase else { return }
                self.setPhase(.hidden)
                self.showNextNotification()
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

    // MARK: - Notifications and calendar

    func setCalendarEvents(_ events: [CalendarEvent]) {
        guard events != calendarEvents else { return }
        animate { self.calendarEvents = events }
    }

    /// The next event that has not ended yet.
    var nextEvent: CalendarEvent? {
        let now = Date()
        return calendarEvents.first { !$0.isAllDay && $0.end > now }
    }

    /// Events still to come today, ongoing ones included.
    var remainingTodayEvents: [CalendarEvent] {
        let now = Date()
        let endOfDay = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400)
        return calendarEvents.filter { $0.end > now && $0.start < endOfDay }
    }

    /// Whether a notification passes the app filter in the settings.
    func allows(_ n: IslandNotification) -> Bool {
        let c = config.notifications
        guard c.enabled || n.source == .calendar else { return false }
        let names = Set(c.apps.map { $0.lowercased() })
        let matches = names.contains(n.appName.lowercased()) || names.contains(n.bundleId?.lowercased() ?? "\u{0}")
        switch c.filterMode.lowercased() {
        case "allow": return n.source == .calendar || matches
        case "block": return !matches
        default: return true
        }
    }

    func present(notification n: IslandNotification) {
        guard allows(n) else { return }
        let c = config.notifications
        recentNotifications.insert(n, at: 0)
        if recentNotifications.count > 8 { recentNotifications.removeLast(recentNotifications.count - 8) }

        // Same app again while its card is up: replace the card's content.
        if phase == .notification, let current = notification, current.groupKey == n.groupKey,
           Date().timeIntervalSince(notificationShownAt) * 1000 < c.mergeWindowMs {
            animate {
                self.notification = n
                self.notificationMergeCount += 1
            }
            scheduleNotificationEnd()
            return
        }
        if phase == .hidden && pendingEvent == nil && coalesceWork == nil {
            showNotification(n)
        } else {
            animate { self.notificationQueue.append(n) }
        }
    }

    /// Settings preview / menu: shows a sample notification card.
    func previewNotification() {
        let sample = IslandNotification(
            source: .system, appName: "메시지", bundleId: "com.apple.MobileSMS",
            title: "민지", subtitle: nil, body: "테마 프리셋 시안 확인했어요. 터미널 테마가 제일 마음에 들어요.")
        if phase == .notification || phase == .hidden {
            notificationWork?.cancel()
            showNotification(sample)
        }
    }

    /// Settings preview: keeps a sample card on screen.
    func showSampleNotification() {
        notificationWork?.cancel()
        collapseWork?.cancel()
        animate {
            self.notification = IslandNotification(
                source: .system, appName: "메시지", bundleId: "com.apple.MobileSMS",
                title: "민지", subtitle: nil, body: "테마 프리셋 시안 확인했어요. 터미널 테마가 제일 마음에 들어요.")
            self.notificationMergeCount = 0
            self.eventSerial &+= 1
            self.phase = .notification
        }
    }

    /// Text of a card after applying notifications.contentMode.
    func visibleText(_ n: IslandNotification) -> (title: String, subtitle: String?, body: String?) {
        switch config.notifications.contentMode.lowercased() {
        case "app": return (n.appName, nil, nil)
        case "title": return (n.title, nil, nil)
        default: return (n.title, n.subtitle, n.body)
        }
    }

    var showsIndicator: Bool {
        config.notifications.keepIndicator && !missedNotifications.isEmpty && !hiddenStyleFades && !isFloating
    }

    /// Distinct apps of the missed notifications, newest first.
    var missedApps: [IslandNotification] {
        var seen = Set<String>()
        return missedNotifications.filter { seen.insert($0.groupKey).inserted }
    }

    private func showNotification(_ n: IslandNotification) {
        collapseWork?.cancel()
        animate {
            self.notification = n
            self.notificationMergeCount = 0
            self.eventSerial &+= 1
            self.phase = .notification
        }
        notificationShownAt = Date()
        scheduleNotificationEnd()
    }

    private func scheduleNotificationEnd() {
        notificationWork?.cancel()
        notificationWork = after(ms: config.notifications.durationMs) { [weak self] in
            guard let self, self.phase == .notification else { return }
            if let n = self.notification { self.addMissed(n) }
            if !self.showNextNotification() {
                self.setPhase(.hidden)
            }
        }
    }

    /// Puts the card back at the front of the queue so it shows again later.
    private func interruptNotification() {
        notificationWork?.cancel()
        if let n = notification {
            notificationQueue.insert(n, at: 0)
        }
        setPhase(.hidden)
    }

    /// Shows the next queued notification when nothing else is on screen.
    @discardableResult
    private func showNextNotification() -> Bool {
        guard !modifierHeld, phase == .hidden || phase == .notification,
              !notificationQueue.isEmpty else { return false }
        let next = notificationQueue.removeFirst()
        showNotification(next)
        return true
    }

    private func addMissed(_ n: IslandNotification) {
        guard config.notifications.keepIndicator else { return }
        let now = Date()
        let timeout = max(config.notifications.indicatorTimeoutMin, 0.1) * 60
        var list = missedNotifications.filter { now.timeIntervalSince($0.date) < timeout }
        list.insert(n, at: 0)
        if list.count > 20 { list.removeLast(list.count - 20) }
        animate { self.missedNotifications = list }
        after(ms: timeout * 1000 + 500) { [weak self] in self?.pruneMissed() }
    }

    private func pruneMissed() {
        let timeout = max(config.notifications.indicatorTimeoutMin, 0.1) * 60
        let now = Date()
        let list = missedNotifications.filter { now.timeIntervalSince($0.date) < timeout }
        guard list.count != missedNotifications.count else { return }
        animate { self.missedNotifications = list }
    }

    func clearMissed() {
        guard !missedNotifications.isEmpty else { return }
        animate { self.missedNotifications = [] }
    }

    private func scheduleDashboard() {
        guard config.dashboard.enabled, !config.dashboard.items.isEmpty else { return }
        dashboardWork = after(ms: config.dashboard.holdMs) { [weak self] in
            guard let self, self.modifierHeld, self.phase == .compact else { return }
            self.setPhase(.dashboard)
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
        case "nextevent": return nextEvent == nil ? 84 : 150
        case "notifications": return 40
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

    static let indicatorEarWidth: CGFloat = 34
    static let notificationCardHeight: CGFloat = 78
    static let dashboardHeight: CGFloat = 112

    var hiddenSize: CGSize {
        let ears = showsIndicator ? 2 * Self.indicatorEarWidth : 0
        return CGSize(width: geometry.width + ears, height: geometry.height)
    }

    var notificationSize: CGSize {
        let width = max(CGFloat(config.appearance.expandedWidth), compactSize.width, 360)
        return CGSize(width: width, height: topStripHeight + Self.notificationCardHeight)
    }

    var dashboardSize: CGSize {
        let width = max(compactSize.width, 380)
        return CGSize(width: width, height: compactSize.height + Self.dashboardHeight)
    }

    var currentSize: CGSize {
        switch phase {
        case .hidden: return hiddenSize
        case .compact: return compactSize
        case .expanded: return expandedSize
        case .notification: return notificationSize
        case .dashboard: return dashboardSize
        }
    }

    /// Distance from the top of the screen to the island's top edge.
    var currentTopOffset: CGFloat {
        isFloating && phase != .hidden ? floatingTop : 0
    }

    /// Largest size the island can take, including the floating gap; the
    /// panel is sized from this.
    var maximumSize: CGSize {
        let sizes = [expandedSize, compactSize, notificationSize, dashboardSize]
        let height = (sizes.map(\.height).max() ?? 0) + (isFloating ? floatingTop : 0)
        let width = sizes.map(\.width).max() ?? 0
        return CGSize(width: max(width, 520), height: max(height, geometry.height))
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
        if phase == .notification {
            notificationWork?.cancel()
            if let n = notification { notificationQueue.insert(n, at: 0) }
        }
        animate {
            self.event = event
            self.eventSerial &+= 1
            self.phase = .expanded
        }
        collapseWork = after(ms: config.behavior.eventDurationMs) { [weak self] in
            guard let self, self.phase == .expanded else { return }
            self.setPhase(self.modifierHeld ? .compact : .hidden)
            self.showNextNotification()
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
