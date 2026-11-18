import Foundation

/// Adds and removes OmniIsland's entries in Claude Code's user settings
/// (`~/.claude/settings.json`), leaving every other setting and hook alone.
enum ClaudeHookInstaller {
    static var settingsURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/settings.json")
    }

    /// The app's own executable, which acts as the hook client.
    static var executable: String {
        Bundle.main.executablePath ?? "/Applications/OmniIsland.app/Contents/MacOS/OmniIsland"
    }

    static var command: String { "'\(executable)' hook claude" }

    /// Events OmniIsland listens to, and whether they take a tool matcher.
    private static let events: [(name: String, matcher: Bool, timeout: Int)] = [
        ("SessionStart", false, 5),
        ("UserPromptSubmit", false, 5),
        ("PermissionRequest", true, 600),
        ("PostToolUse", true, 5),
        ("Notification", false, 5),
        ("Stop", false, 10),
        ("SessionEnd", false, 5),
    ]

    private static func isOurs(_ hook: Any) -> Bool {
        guard let command = (hook as? [String: Any])?["command"] as? String else { return false }
        return command.contains("OmniIsland") && command.contains(" hook claude")
    }

    static func isInstalled() -> Bool {
        guard let hooks = load()?["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { event in
            (hooks[event.name] as? [[String: Any]] ?? []).contains { group in
                (group["hooks"] as? [Any] ?? []).contains(where: isOurs)
            }
        }
    }

    static func install() throws {
        var settings = load() ?? [:]
        var hooks = removingOurs(settings["hooks"] as? [String: Any] ?? [:])
        for event in events {
            var groups = hooks[event.name] as? [[String: Any]] ?? []
            var group: [String: Any] = [
                "hooks": [["type": "command", "command": command, "timeout": event.timeout]],
            ]
            if event.matcher { group["matcher"] = "*" }
            groups.append(group)
            hooks[event.name] = groups
        }
        settings["hooks"] = hooks
        try save(settings)
    }

    static func uninstall() throws {
        guard var settings = load() else { return }
        let hooks = removingOurs(settings["hooks"] as? [String: Any] ?? [:])
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        try save(settings)
    }

    private static func removingOurs(_ hooks: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (name, value) in hooks {
            guard let groups = value as? [[String: Any]] else {
                result[name] = value
                continue
            }
            let kept = groups.compactMap { group -> [String: Any]? in
                guard let list = group["hooks"] as? [Any] else { return group }
                let rest = list.filter { !isOurs($0) }
                if rest.isEmpty { return nil }
                var copy = group
                copy["hooks"] = rest
                return copy
            }
            if !kept.isEmpty { result[name] = kept }
        }
        return result
    }

    private static func load() -> [String: Any]? {
        guard let data = try? Data(contentsOf: settingsURL), !data.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    enum InstallError: LocalizedError {
        case unreadable
        var errorDescription: String? {
            "~/.claude/settings.json을 JSON으로 읽을 수 없어서 고치지 않았습니다."
        }
    }

    private static func save(_ settings: [String: Any]) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: settingsURL.path) {
            // Refuse to overwrite a file we could not parse.
            if load() == nil, let data = try? Data(contentsOf: settingsURL), !data.isEmpty {
                throw InstallError.unreadable
            }
            let backup = settingsURL.appendingPathExtension("omni-island-backup")
            try? fm.removeItem(at: backup)
            try? fm.copyItem(at: settingsURL, to: backup)
        } else {
            try fm.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        let data = try JSONSerialization.data(withJSONObject: settings,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: settingsURL, options: .atomic)
    }
}

enum CodexHookInfo {
    /// The line to put in `~/.codex/config.toml`.
    static var configLine: String {
        "notify = [\"\(ClaudeHookInstaller.executable)\", \"hook\", \"codex\"]"
    }
}
