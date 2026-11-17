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
    @Published private(set) var focusedApp: AppRef?
    @Published private(set) var event: IslandEvent?
    @Published private(set) var eventSerial = 0
    @Published private(set) var config = IslandConfig()
    /// Dock notification badges, keyed by lower-cased bundle id.
    @Published private(set) var badges: [String: String] = [:]
    @Published var geometry = NotchGeometry(width: 200, height: 32, hasNotch: false)

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
        let app = tracker.focusedApp
        guard items != workspaces || key != activeWorkspaceKey || label != activeWorkspaceLabel || app != focusedApp
        else { return }
        animate {
            self.workspaces = items
            self.activeWorkspaceKey = key
            self.activeWorkspaceLabel = label
            self.focusedApp = app
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

    var pillFont: NSFont {
        NSFont.systemFont(ofSize: CGFloat(config.appearance.fontSize) * 0.9, weight: .semibold)
    }

    var pillSwiftUIFont: Font {
        .system(size: CGFloat(config.appearance.fontSize) * 0.9, weight: .semibold)
    }

    func pillWidth(for label: String) -> CGFloat {
        let text = (label as NSString).size(withAttributes: [.font: pillFont]).width
        return max(CGFloat(config.appearance.pillSize), ceil(text) + 14)
    }

    var usesAppStyle: Bool { config.appearance.workspaceStyle.lowercased() != "pills" }

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
        let label = pillWidth(for: ws.label) - 8
        let apps = displayedApps(for: ws)
        let shown = min(apps.count, maxAppsPerWorkspace)
        var width = Self.groupPadding * 2 + label
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
        let items = workspaces.map { usesAppStyle ? groupWidth(for: $0) : pillWidth(for: $0.label) }
        let spacing = CGFloat(a.pillSpacing) * CGFloat(max(workspaces.count - 1, 0))
        return items.reduce(0, +) + spacing
    }

    var compactSize: CGSize {
        let a = config.appearance
        let wings: CGFloat = a.showFocusedApp ? 76 : 28
        let width = max(geometry.width + 2 * wings, rowContentWidth + 40)
        return CGSize(width: width, height: geometry.height + rowHeight)
    }

    var expandedSize: CGSize {
        let a = config.appearance
        let width = max(CGFloat(a.expandedWidth), compactSize.width)
        return CGSize(
            width: width,
            height: geometry.height + rowHeight + CGFloat(a.expandedHeaderHeight)
        )
    }

    var currentSize: CGSize {
        switch phase {
        case .hidden: return CGSize(width: geometry.width, height: geometry.height)
        case .compact: return compactSize
        case .expanded: return expandedSize
        }
    }

    /// Largest size the island can take; the panel is sized from this.
    var maximumSize: CGSize {
        let e = expandedSize
        return CGSize(width: max(e.width, 520), height: e.height)
    }

    var swiftUIAnimation: Animation? {
        let n = config.motion
        let d = max(n.durationMs, 1) / 1000
        switch n.style.lowercased() {
        case "none": return nil
        case "easeinout", "ease": return .easeInOut(duration: d)
        case "bouncy": return .bouncy(duration: d)
        case "smooth": return .smooth(duration: d)
        case "snappy": return .snappy(duration: d)
        default:
            return .spring(response: max(n.response, 0.05), dampingFraction: min(max(n.dampingFraction, 0.05), 1))
        }
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
