import Foundation

// Lenient mirrors of the OmniWM IPC (protocol v23) types this app reads.
// Every field is optional so that a newer OmniWM adding or dropping fields
// does not break decoding. Source of truth:
// OmniWM/Sources/OmniWMIPC/IPCQueryModels.swift and IPCModels.swift

struct EnvelopeHeader: Decodable {
    let kind: String?
    let channel: String?
    let ok: Bool?
    let status: String?
    let code: String?
    let message: String?
    let result: ResultHeader?

    struct ResultHeader: Decodable {
        let kind: String?
    }
}

struct Envelope<Payload: Decodable>: Decodable {
    let result: Body?

    struct Body: Decodable {
        let kind: String?
        let payload: Payload?
    }
}

struct WorkspaceRef: Decodable, Equatable, Hashable {
    let id: String?
    let rawName: String?
    let displayName: String?
    let number: Int?

    var label: String {
        if let d = displayName, !d.isEmpty { return d }
        if let r = rawName, !r.isEmpty { return r }
        if let n = number { return String(n) }
        return id ?? "?"
    }

    /// Stable key: OmniWM's workspace id, falling back to the raw name.
    var key: String { id ?? rawName ?? label }
}

struct DisplayRef: Decodable, Equatable, Hashable {
    let id: String?
    let name: String?
    let isMain: Bool?
}

struct AppRef: Decodable, Equatable, Hashable {
    let name: String?
    let bundleId: String?
}

/// Channel `active-workspace` → result kind `active-workspace`.
struct ActiveWorkspacePayload: Decodable {
    let display: DisplayRef?
    let workspace: WorkspaceRef?
    let focusedApp: AppRef?
}

/// Channel `focus` → result kind `focused-window`.
struct FocusedWindowPayload: Decodable {
    let window: WindowSnapshot?
}

/// Channel `windows-changed` → result kind `windows`.
struct WindowsPayload: Decodable {
    let windows: [WindowSnapshot]?
}

struct WindowSnapshot: Decodable, Equatable {
    let id: String?
    let workspace: WorkspaceRef?
    let display: DisplayRef?
    let app: AppRef?
    let title: String?
    let isFocused: Bool?
    let isScratchpad: Bool?
    /// "tiling" or "floating".
    let mode: String?
    let pid: Int?

    var isFloating: Bool { mode?.lowercased() == "floating" }
}

/// Channel `layout-changed` → result kind `workspaces`.
struct WorkspacesPayload: Decodable {
    let workspaces: [WorkspaceSnapshot]?
}

struct WorkspaceSnapshot: Decodable, Equatable {
    let id: String?
    let rawName: String?
    let displayName: String?
    let number: Int?
    let display: DisplayRef?
    let isFocused: Bool?
    let isVisible: Bool?
    let isCurrent: Bool?
    let counts: Counts?

    struct Counts: Decodable, Equatable {
        let total: Int?
        let tiled: Int?
        let floating: Int?
        let scratchpad: Int?
    }

    var ref: WorkspaceRef {
        WorkspaceRef(id: id, rawName: rawName, displayName: displayName, number: number)
    }
}

/// Decoded messages handed from the IPC client to the state tracker.
enum OmniWMMessage {
    case subscribed
    case rejected(code: String?, message: String?)
    case activeWorkspace(ActiveWorkspacePayload)
    case focus(FocusedWindowPayload)
    case windows(WindowsPayload)
    case workspaces(WorkspacesPayload)
}

enum OmniWMDecoder {
    private static let decoder = JSONDecoder()

    static func decode(line: Data) -> OmniWMMessage? {
        guard let header = try? decoder.decode(EnvelopeHeader.self, from: line) else { return nil }

        if header.kind == "subscribe" || header.status == "subscribed" {
            return header.ok == false ? .rejected(code: header.code, message: header.message) : .subscribed
        }
        if header.ok == false {
            return .rejected(code: header.code, message: header.message)
        }

        switch header.result?.kind {
        case "active-workspace":
            return (try? decoder.decode(Envelope<ActiveWorkspacePayload>.self, from: line))?
                .result?.payload.map(OmniWMMessage.activeWorkspace)
        case "focused-window":
            return (try? decoder.decode(Envelope<FocusedWindowPayload>.self, from: line))?
                .result?.payload.map(OmniWMMessage.focus)
        case "windows":
            return (try? decoder.decode(Envelope<WindowsPayload>.self, from: line))?
                .result?.payload.map(OmniWMMessage.windows)
        case "workspaces":
            return (try? decoder.decode(Envelope<WorkspacesPayload>.self, from: line))?
                .result?.payload.map(OmniWMMessage.workspaces)
        default:
            return nil
        }
    }
}
