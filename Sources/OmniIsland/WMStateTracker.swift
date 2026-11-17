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

    /// window id → workspace it was last seen on.
    private var windowWorkspace: [String: WorkspaceRef] = [:]
    private var windowInfo: [String: WindowSnapshot] = [:]
    private var hasWindowBaseline = false
    /// display id → active workspace on that display.
    private var activeByDisplay: [String: WorkspaceRef] = [:]
    private var hasActiveBaseline = false

    func reset() {
        windowWorkspace.removeAll()
        windowInfo.removeAll()
        hasWindowBaseline = false
        activeByDisplay.removeAll()
        hasActiveBaseline = false
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
        return filtered.map { ws in
            WorkspaceItem(
                id: ws.ref.key,
                label: ws.ref.label,
                number: ws.number,
                displayId: ws.display?.id,
                displayName: ws.display?.name,
                windowCount: ws.counts?.total ?? 0,
                isVisible: ws.isVisible ?? false
            )
        }
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
        hasWindowBaseline = true
        if let focused = windows.first(where: { $0.isFocused == true }) {
            focusedApp = focused.app ?? focusedApp
            focusedTitle = focused.title
        }
        onStateChange?()
    }
}
