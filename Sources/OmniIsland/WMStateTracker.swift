import Foundation

/// One workspace as shown in the island's workspace row.
struct WorkspaceItem: Identifiable, Equatable {
    let id: String
    let label: String
    let number: Int?
    let displayId: String?
    let displayName: String?
    let windowCount: Int
    let isVisible: Bool
    /// Apps on this workspace in layout order, one entry per app.
    var apps: [WorkspaceApp] = []
    /// Same as `apps`, but one entry per window (for the "separate" style).
    var windows: [WorkspaceApp] = []
    /// OmniWM's raw workspace name, for `workspace focus-name`.
    var rawName: String? = nil
}

struct WorkspaceApp: Identifiable, Equatable {
    /// Lower-cased bundle id, or the app name when OmniWM has no bundle id.
    let id: String
    let name: String
    let bundleId: String?
    var windowCount: Int
    var isFocused: Bool
    /// Floating windows are grouped apart from tiled ones.
    var isFloating: Bool = false
    /// OmniWM window ids, in layout order.
    var windowIds: [String] = []
    /// The window to bring forward when the icon is clicked.
    var focusedWindowId: String?

    var appRef: AppRef { AppRef(name: name, bundleId: bundleId) }
    var targetWindowId: String? { focusedWindowId ?? windowIds.first }
}

/// Something that actually happened and deserves an expanded island.
enum IslandEvent: Equatable {
    case workspaceSwitch(from: WorkspaceRef?, to: WorkspaceRef, app: AppRef?)
    case windowMove(app: AppRef?, title: String?, from: WorkspaceRef?, to: WorkspaceRef, count: Int)

    var targetWorkspaceKey: String {
        switch self {
        case .workspaceSwitch(_, let to, _): return to.key
        case .windowMove(_, _, _, let to, _): return to.key
        }
    }

    var sourceWorkspaceKey: String? {
        switch self {
        case .workspaceSwitch(let from, _, _): return from?.key
        case .windowMove(_, _, let from, _, _): return from?.key
        }
    }

    /// Higher wins when two events are coalesced.
    var priority: Int {
        switch self {
        case .workspaceSwitch: return 1
        case .windowMove: return 2
        }
    }
}

/// Keeps the latest OmniWM state and derives "move" events by diffing
/// consecutive snapshots (subscription channels are coalesced state streams,
/// not an event log).
@MainActor
final class WMStateTracker {
    var onStateChange: (() -> Void)?
    var onEvent: ((IslandEvent) -> Void)?

    private(set) var workspaces: [WorkspaceSnapshot] = []
    private(set) var activeDisplay: DisplayRef?
    private(set) var activeWorkspace: WorkspaceRef?
    private(set) var focusedApp: AppRef?
    private(set) var focusedTitle: String?
    /// Id of the focused window, from the `focus` channel. The windows-changed
    /// snapshot is not re-sent when only focus moves, so its `isFocused`
    /// flags go stale; this id is what decides which icon is highlighted.
    private(set) var focusedWindowId: String?
    private var hasFocusInfo = false

    /// window id → workspace it was last seen on.
    private var windowWorkspace: [String: WorkspaceRef] = [:]
    private var windowInfo: [String: WindowSnapshot] = [:]
    /// Latest windows-changed snapshot, in OmniWM's order (workspace, then layout).
    private(set) var windows: [WindowSnapshot] = []
    private var hasWindowBaseline = false
    /// display id → active workspace on that display.
    private var activeByDisplay: [String: WorkspaceRef] = [:]
    private var hasActiveBaseline = false

    func reset() {
        windows.removeAll()
        windowWorkspace.removeAll()
        windowInfo.removeAll()
        hasWindowBaseline = false
        activeByDisplay.removeAll()
        hasActiveBaseline = false
        focusedWindowId = nil
        hasFocusInfo = false
    }

    /// Whether this window is the focused one, preferring the live `focus`
    /// channel over the (possibly stale) flag in the windows snapshot.
    func isFocused(_ window: WindowSnapshot) -> Bool {
        guard hasFocusInfo else { return window.isFocused == true }
        guard let id = window.id, let focusedWindowId else { return false }
        return id == focusedWindowId
    }

    func handle(_ message: OmniWMMessage) {
        switch message {
        case .subscribed:
            // Fresh (re)subscription: next snapshots are a new baseline.
            reset()
        case .rejected:
            break
        case .activeWorkspace(let p):
            handleActiveWorkspace(p)
        case .focus(let p):
            focusedApp = p.window?.app ?? focusedApp
            focusedTitle = p.window?.title
            focusedWindowId = p.window?.id
            hasFocusInfo = true
            onStateChange?()
        case .windows(let p):
            handleWindows(p.windows ?? [])
        case .workspaces(let p):
            workspaces = p.workspaces ?? []
            onStateChange?()
        }
    }

    // MARK: - Derived state

    /// Workspaces on the given display (or the active display), in order.
    func workspaceItems(displayId: String?, includeEmpty: Bool) -> [WorkspaceItem] {
        let targetDisplay = displayId ?? activeDisplay?.id
        let activeKey = activeWorkspace?.key
        let filtered = workspaces.filter { ws in
            if let targetDisplay, let d = ws.display?.id, d != targetDisplay { return false }
            let key = ws.ref.key
            if key == activeKey || ws.isVisible == true || ws.isCurrent == true { return true }
            return includeEmpty || (ws.counts?.total ?? 0) > 0
        }
        let appsByWorkspace = appsGroupedByWorkspace()
        let windowsByWorkspace = windowsGroupedByWorkspace()
        return filtered.map { ws in
            WorkspaceItem(
                id: ws.ref.key,
                label: ws.ref.label,
                number: ws.number,
                displayId: ws.display?.id,
                displayName: ws.display?.name,
                windowCount: ws.counts?.total ?? 0,
                isVisible: ws.isVisible ?? false,
                apps: appsByWorkspace[ws.ref.key] ?? [],
                windows: windowsByWorkspace[ws.ref.key] ?? [],
                rawName: ws.rawName
            )
        }
    }

    /// workspace key → apps on it, built from the windows-changed snapshot.
    /// Scratchpad windows are left out because they float above workspaces.
    func appsGroupedByWorkspace() -> [String: [WorkspaceApp]] {
        var result: [String: [WorkspaceApp]] = [:]
        for window in windows {
            guard window.isScratchpad != true, let ws = window.workspace else { continue }
            let name = window.app?.name ?? "?"
            let bundleId = window.app?.bundleId
            let floating = window.isFloating
            let appKey = ((bundleId?.lowercased()).flatMap { $0.isEmpty ? nil : $0 } ?? name)
                + (floating ? "~float" : "")
            let wsKey = ws.key
            let focused = isFocused(window)
            var apps = result[wsKey] ?? []
            if let index = apps.firstIndex(where: { $0.id == appKey }) {
                apps[index].windowCount += 1
                if let id = window.id { apps[index].windowIds.append(id) }
                if focused {
                    apps[index].isFocused = true
                    apps[index].focusedWindowId = window.id
                }
            } else {
                apps.append(WorkspaceApp(
                    id: appKey, name: name, bundleId: bundleId,
                    windowCount: 1, isFocused: focused, isFloating: floating,
                    windowIds: window.id.map { [$0] } ?? [],
                    focusedWindowId: focused ? window.id : nil
                ))
            }
            result[wsKey] = apps
        }
        return result.mapValues(Self.tiledFirst)
    }

    /// Tiled windows in layout order, then the floating ones.
    private static func tiledFirst(_ apps: [WorkspaceApp]) -> [WorkspaceApp] {
        apps.filter { !$0.isFloating } + apps.filter(\.isFloating)
    }

    /// workspace key → one entry per window, in layout order.
    func windowsGroupedByWorkspace() -> [String: [WorkspaceApp]] {
        var result: [String: [WorkspaceApp]] = [:]
        var perApp: [String: Int] = [:]
        for window in windows {
            guard window.isScratchpad != true, let ws = window.workspace else { continue }
            let name = window.app?.name ?? "?"
            let bundleId = window.app?.bundleId
            let floating = window.isFloating
            let appKey = ((bundleId?.lowercased()).flatMap { $0.isEmpty ? nil : $0 } ?? name)
                + (floating ? "~float" : "")
            let wsKey = ws.key
            let counterKey = wsKey + "\u{1}" + appKey
            let ordinal = perApp[counterKey, default: 0]
            perApp[counterKey] = ordinal + 1
            let focused = isFocused(window)
            let entry = WorkspaceApp(
                id: appKey + "#" + (window.id ?? String(ordinal)),
                name: name, bundleId: bundleId,
                windowCount: 1, isFocused: focused, isFloating: floating,
                windowIds: window.id.map { [$0] } ?? [],
                focusedWindowId: focused ? window.id : nil
            )
            result[wsKey, default: []].append(entry)
        }
        return result.mapValues(Self.tiledFirst)
    }

    /// Bundle ids of every managed app, for the Dock badge reader.
    var managedBundleIds: Set<String> {
        Set(windows.compactMap { $0.app?.bundleId?.lowercased() }.filter { !$0.isEmpty })
    }

    // MARK: - Diffing

    private func handleActiveWorkspace(_ p: ActiveWorkspacePayload) {
        let previousActive = activeWorkspace
        activeDisplay = p.display ?? activeDisplay
        if let app = p.focusedApp { focusedApp = app }

        if let ws = p.workspace {
            activeWorkspace = ws
            let displayKey = p.display?.id ?? "_"
            let previousOnDisplay = activeByDisplay[displayKey]
            activeByDisplay[displayKey] = ws

            if hasActiveBaseline {
                // Same display, different workspace → a switch. Moving focus to
                // another monitor whose workspace did not change is not a switch.
                if let prev = previousOnDisplay, prev.key != ws.key {
                    onEvent?(.workspaceSwitch(from: prev, to: ws, app: focusedApp))
                } else if previousOnDisplay == nil, let prev = previousActive, prev.key != ws.key,
                          activeByDisplay.count == 1 {
                    onEvent?(.workspaceSwitch(from: prev, to: ws, app: focusedApp))
                }
            }
            hasActiveBaseline = true
        }
        onStateChange?()
    }

    /// The snapshot in the order the windows sit on screen: workspaces as
    /// OmniWM lists them, then tiled windows by Niri column (tiles of one
    /// column in OmniWM's order), then floating windows. OmniWM's own order
    /// follows the layout only in newer versions, so the column index decides.
    static func layoutOrdered(_ windows: [WindowSnapshot]) -> [WindowSnapshot] {
        var workspaceRank: [String: Int] = [:]
        for w in windows {
            let key = w.workspace?.key ?? ""
            if workspaceRank[key] == nil { workspaceRank[key] = workspaceRank.count }
        }
        return windows.enumerated().sorted { a, b in
            let ka = (workspaceRank[a.element.workspace?.key ?? ""] ?? 0, a.element.isFloating ? 1 : 0,
                      a.element.columnIndex ?? Int.max, a.offset)
            let kb = (workspaceRank[b.element.workspace?.key ?? ""] ?? 0, b.element.isFloating ? 1 : 0,
                      b.element.columnIndex ?? Int.max, b.offset)
            return ka < kb
        }.map(\.element)
    }

    private func handleWindows(_ windows: [WindowSnapshot]) {
        var nextWorkspace: [String: WorkspaceRef] = [:]
        var nextInfo: [String: WindowSnapshot] = [:]
        for w in windows {
            guard let id = w.id else { continue }
            nextInfo[id] = w
            if let ws = w.workspace { nextWorkspace[id] = ws }
        }

        if hasWindowBaseline {
            var moved: [(WindowSnapshot, WorkspaceRef?, WorkspaceRef)] = []
            for (id, ws) in nextWorkspace {
                guard let old = windowWorkspace[id], old.key != ws.key, let info = nextInfo[id] else { continue }
                moved.append((info, old, ws))
            }
            if !moved.isEmpty {
                // Prefer the focused window; it is almost always the one the
                // user just moved.
                let primary = moved.first { $0.0.isFocused == true } ?? moved[0]
                onEvent?(.windowMove(
                    app: primary.0.app,
                    title: primary.0.title,
                    from: primary.1,
                    to: primary.2,
                    count: moved.count
                ))
            }
        }

        windowWorkspace = nextWorkspace
        windowInfo = nextInfo
        self.windows = Self.layoutOrdered(windows)
        hasWindowBaseline = true
        if let focused = windows.first(where: { $0.isFocused == true }) {
            focusedApp = focused.app ?? focusedApp
            focusedTitle = focused.title
            if let id = focused.id {
                focusedWindowId = id
                hasFocusInfo = true
            }
        }
        onStateChange?()
    }
}
