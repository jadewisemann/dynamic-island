import AppKit
import Foundation

/// One coding agent session (a Claude Code or Codex conversation).
struct AgentSession: Identifiable, Equatable {
    enum State: String, Equatable {
        /// Running tools or writing an answer.
        case working
        /// Finished its turn or waiting for the next prompt.
        case waiting
        /// Waiting for a permission decision.
        case approval
        /// Finished its turn (shown until the next prompt).
        case done

        var label: String {
            switch self {
            case .working: return "작업 중"
            case .waiting: return "입력 대기"
            case .approval: return "승인 필요"
            case .done: return "완료"
            }
        }

        /// Dot color, `#RRGGBB`.
        var color: String {
            switch self {
            case .working: return "#0A84FF"
            case .waiting: return "#FFD60A"
            case .approval: return "#FF9F0A"
            case .done: return "#30D158"
            }
        }
    }

    let id: String
    /// "Claude Code" or "Codex".
    var agent: String
    /// Last path component of the working directory.
    var project: String
    var cwd: String
    var state: State
    var detail: String?
    /// OmniWM window of the terminal the agent runs in.
    var windowId: String?
    /// Bundle id of the terminal app, from the hook's environment.
    var bundleId: String?
    var updated: Date
}

/// Turns hook events from `omni-island hook …` into sessions and cards, and
/// holds permission requests until a card button answers them.
@MainActor
final class AgentMonitor {
    var config = IslandConfig.Agents()
    /// Current OmniWM windows and the focused window id.
    var windowsProvider: (() -> (windows: [WindowSnapshot], focusedId: String?))?
    var onSessionsChange: (([AgentSession]) -> Void)?
    var present: ((IslandNotification) -> Void)?
    var dismiss: ((String) -> Void)?

    private var sessions: [String: AgentSession] = [:]
    private struct Pending {
        let sessionId: String
        let reply: ([String: Any]?) -> Void
        let timeout: DispatchWorkItem
    }
    private var pending: [String: Pending] = [:]
    private var pruneTimer: Timer?

    static let allowAction = NotificationAction(id: "allow", label: "허용", role: .primary)
    static let denyAction = NotificationAction(id: "deny", label: "거부", role: .destructive)

    func start() {
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.prune() }
        }
    }

    var sortedSessions: [AgentSession] {
        sessions.values.sorted { $0.updated > $1.updated }
    }

    func session(id: String) -> AgentSession? { sessions[id] }

    // MARK: - Events

    /// Handles one `agent` request. Calls `reply` once: right away, or when
    /// a permission request is answered or times out.
    func handle(_ request: [String: Any], reply: @escaping ([String: Any]?) -> Void) {
        guard config.enabled else { return reply(nil) }
        let agent = (request["agent"] as? String ?? "claude").lowercased()
        let event = request["event"] as? [String: Any] ?? [:]
        let pids = (request["pids"] as? [Any] ?? []).compactMap { ($0 as? NSNumber)?.intValue }
        let bundleId = (request["bundleId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        switch agent {
        case "codex":
            handleCodex(event, pids: pids, bundleId: bundleId)
            reply(nil)
        default:
            handleClaude(event, pids: pids, bundleId: bundleId, reply: reply)
        }
    }

    private func handleClaude(_ event: [String: Any], pids: [Int], bundleId: String?,
                              reply: @escaping ([String: Any]?) -> Void) {
        let name = event["hook_event_name"] as? String ?? ""
        let rawId = event["session_id"] as? String ?? "unknown"
        let id = "claude:" + rawId
        let cwd = event["cwd"] as? String ?? ""

        if name == "SessionEnd" {
            cancelPending(sessionId: id)
            sessions[id] = nil
            dismiss?("agent:" + id)
            publish()
            return reply(nil)
        }

        var session = sessions[id] ?? AgentSession(
            id: id, agent: "Claude Code", project: Self.project(cwd), cwd: cwd, state: .waiting,
            detail: nil, windowId: nil, bundleId: bundleId, updated: Date())
        if !cwd.isEmpty {
            session.cwd = cwd
            session.project = Self.project(cwd)
        }
        if let bundleId { session.bundleId = bundleId }
        session.updated = Date()
        // The user just typed into this terminal, so the focused window is a
        // good guess for which of several terminal windows runs the agent.
        if session.windowId == nil || name == "UserPromptSubmit" || name == "SessionStart" {
            session.windowId = resolveWindow(pids: pids, cwd: session.cwd, bundleId: session.bundleId,
                                             preferFocused: true) ?? session.windowId
        }

        switch name {
        case "SessionStart":
            session.state = .waiting
            session.detail = nil
        case "UserPromptSubmit":
            cancelPending(sessionId: id)
            session.state = .working
            session.detail = Self.clip(event["prompt"] as? String)
            dismiss?("agent:" + id)
        case "PreToolUse", "PostToolUse":
            // A tool ran, so any permission prompt was answered (maybe in
            // the terminal).
            if cancelPending(sessionId: id) { dismiss?("agent:" + id) }
            session.state = .working
            if let tool = event["tool_name"] as? String { session.detail = tool }
        case "PermissionRequest":
            session.state = .approval
            let tool = event["tool_name"] as? String ?? "도구"
            let summary = Self.summary(tool: tool, input: event["tool_input"] as? [String: Any])
            session.detail = summary
            sessions[id] = session
            publish()
            askPermission(session: session, tool: tool, summary: summary, reply: reply)
            return
        case "Notification":
            let type = event["notification_type"] as? String ?? ""
            let message = event["message"] as? String ?? ""
            if type == "permission_prompt" || message.localizedCaseInsensitiveContains("permission") {
                // Already on a card with buttons; otherwise point at the terminal.
                if pending.values.contains(where: { $0.sessionId == id }) { break }
                session.state = .approval
                if config.notifyWaiting {
                    present?(card(session, title: "터미널에서 승인이 필요합니다", body: message, sticky: false))
                }
            } else {
                session.state = .waiting
                if config.notifyWaiting {
                    present?(card(session, title: "입력을 기다립니다", body: message, sticky: false))
                }
            }
        case "Stop", "SubagentStop":
            guard name == "Stop" else { break }
            cancelPending(sessionId: id)
            session.state = .done
            let last = Self.clip(event["last_message"] as? String, limit: 160)
            session.detail = last
            if config.notifyDone {
                present?(card(session, title: "작업을 마쳤습니다", body: last, sticky: false))
            }
        default:
            break
        }
        sessions[id] = session
        publish()
        reply(nil)
    }

    private func handleCodex(_ event: [String: Any], pids: [Int], bundleId: String?) {
        guard (event["type"] as? String) == "agent-turn-complete" else { return }
        let cwd = event["cwd"] as? String ?? ""
        let rawId = event["thread-id"] as? String ?? event["turn-id"] as? String ?? cwd
        let id = "codex:" + rawId
        var session = sessions[id] ?? AgentSession(
            id: id, agent: "Codex", project: Self.project(cwd), cwd: cwd, state: .done,
            detail: nil, windowId: nil, bundleId: bundleId, updated: Date())
        session.state = .done
        session.updated = Date()
        session.detail = Self.clip(event["last-assistant-message"] as? String, limit: 160)
        session.windowId = resolveWindow(pids: pids, cwd: cwd, bundleId: bundleId, preferFocused: false)
            ?? session.windowId
        sessions[id] = session
        publish()
        if config.notifyDone {
            present?(card(session, title: "작업을 마쳤습니다", body: session.detail, sticky: false))
        }
    }

    // MARK: - Permissions

    private func askPermission(session: AgentSession, tool: String, summary: String,
                               reply: @escaping ([String: Any]?) -> Void) {
        guard config.approvals else {
            if config.notifyWaiting {
                present?(card(session, title: "\(tool) 승인이 필요합니다", body: summary, sticky: false))
            }
            return reply(nil)
        }
        cancelPending(sessionId: session.id)
        let requestId = UUID().uuidString
        let seconds = max(config.approvalTimeoutSec, 10)
        let timeout = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                // No answer: Claude Code falls back to its own prompt.
                guard let self, let p = self.pending.removeValue(forKey: requestId) else { return }
                p.reply(nil)
                self.dismiss?("agent:" + session.id)
            }
        }
        pending[requestId] = Pending(sessionId: session.id, reply: reply, timeout: timeout)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: timeout)

        var n = card(session, title: "\(tool) 실행을 허용할까요?", body: summary, sticky: true)
        n.actions = [Self.allowAction, Self.denyAction]
        n.durationMs = seconds * 1000
        n.payload = requestId
        present?(n)
    }

    /// A card button was pressed.
    func perform(_ action: NotificationAction, on n: IslandNotification) {
        guard let requestId = n.payload, let p = pending.removeValue(forKey: requestId) else { return }
        p.timeout.cancel()
        let allow = action.id == Self.allowAction.id
        var decision: [String: Any] = ["behavior": allow ? "allow" : "deny"]
        if !allow { decision["message"] = "OmniIsland에서 거부했습니다." }
        p.reply(["decision": decision])
        if var session = sessions[p.sessionId] {
            session.state = allow ? .working : .waiting
            session.updated = Date()
            sessions[p.sessionId] = session
            publish()
        }
    }

    /// Answers an open permission request with "no decision". Returns
    /// whether there was one.
    @discardableResult
    private func cancelPending(sessionId: String) -> Bool {
        let keys = pending.filter { $0.value.sessionId == sessionId }.map(\.key)
        for key in keys {
            guard let p = pending.removeValue(forKey: key) else { continue }
            p.timeout.cancel()
            p.reply(nil)
        }
        return !keys.isEmpty
    }

    // MARK: - Cards

    private func card(_ session: AgentSession, title: String, body: String?, sticky: Bool) -> IslandNotification {
        var n = IslandNotification(source: .agent, appName: "\(session.agent) · \(session.project)",
                                   bundleId: session.bundleId, title: title, subtitle: nil, body: body)
        n.symbol = session.agent == "Codex" ? "chevron.left.forwardslash.chevron.right" : "sparkle"
        n.tint = session.state.color
        n.windowId = session.windowId
        n.externalId = "agent:" + session.id
        n.group = "agent:" + session.id
        if !sticky { n.durationMs = max(config.cardDurationMs, 1000) }
        return n
    }

    private func publish() {
        onSessionsChange?(sortedSessions)
    }

    private func prune() {
        let now = Date()
        let before = sessions.count
        sessions = sessions.filter { _, s in
            let age = now.timeIntervalSince(s.updated)
            if pending.values.contains(where: { $0.sessionId == s.id }) { return true }
            return s.state == .done ? age < config.keepDoneMin * 60 : age < 6 * 3600
        }
        if sessions.count != before { publish() }
    }

    // MARK: - Windows

    /// Finds the terminal window: an OmniWM window owned by one of the hook
    /// process's ancestors, preferring the focused one or one whose title
    /// names the project.
    private func resolveWindow(pids: [Int], cwd: String, bundleId: String?, preferFocused: Bool) -> String? {
        guard let state = windowsProvider?() else { return nil }
        let ancestors = Set(pids)
        var candidates = state.windows.filter { w in
            guard w.id != nil, let pid = w.pid else { return false }
            return ancestors.contains(pid)
        }
        // tmux and similar detach the agent from the terminal's process
        // tree; fall back to windows of the terminal app.
        if candidates.isEmpty, let bundleId {
            candidates = state.windows.filter { $0.id != nil && $0.app?.bundleId == bundleId }
        }
        guard !candidates.isEmpty else { return nil }
        if candidates.count == 1 { return candidates[0].id }
        let project = Self.project(cwd)
        if preferFocused, let focused = state.focusedId, candidates.contains(where: { $0.id == focused }) {
            return focused
        }
        if !project.isEmpty, let titled = candidates.first(where: { ($0.title ?? "").contains(project) }) {
            return titled.id
        }
        return candidates.first?.id
    }

    // MARK: - Text

    static func project(_ cwd: String) -> String {
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? "세션" : name
    }

    static func clip(_ text: String?, limit: Int = 80) -> String? {
        guard let text else { return nil }
        let line = text.split(whereSeparator: \.isNewline).map(String.init)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.count > limit ? String(trimmed.prefix(limit - 1)) + "…" : trimmed
    }

    /// "Bash: npm test", "Edit: Sources/App.swift" …
    static func summary(tool: String, input: [String: Any]?) -> String {
        let input = input ?? [:]
        let keys = ["command", "file_path", "path", "url", "pattern", "query", "description", "prompt"]
        for key in keys {
            if let value = input[key] as? String, let text = clip(value, limit: 120) {
                return "\(tool): \(text)"
            }
        }
        return tool
    }
}
