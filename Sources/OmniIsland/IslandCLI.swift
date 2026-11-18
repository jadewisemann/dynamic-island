import Darwin
import Foundation

/// `omni-island <command>`: the app's executable doubles as a small client
/// that talks to the running app over its Unix socket.
///
///     omni-island notify --title "빌드 완료" --body "3분 12초" --icon hammer
///     omni-island dismiss --id build
///     omni-island hook claude        (Claude Code hooks; JSON on stdin)
///     omni-island hook codex <json>  (Codex `notify` program)
enum IslandCLI {
    static let commands: Set<String> = ["notify", "dismiss", "hook", "help", "--help", "-h"]

    /// Runs a command and returns its exit code, or nil when the arguments
    /// are not a command (the app starts normally).
    static func run(_ arguments: [String]) -> Int32? {
        guard arguments.count >= 2, commands.contains(arguments[1]) else { return nil }
        let args = Array(arguments.dropFirst(2))
        switch arguments[1] {
        case "notify": return notify(args)
        case "dismiss": return dismiss(args)
        case "hook": return hook(args)
        default:
            print(usage)
            return 0
        }
    }

    static let usage = """
    사용법: omni-island <명령> [옵션]

      notify   아일랜드에 카드를 띄웁니다.
               --title 제목 (필수)  --body 본문  --app 보낸 곳 이름
               --icon SF Symbol 이름  --color #RRGGBB  --bundle-id 앱 번들 ID
               --id 카드 id (같은 id로 다시 보내면 내용을 바꿉니다)
               --duration 초  --progress 0~1
      dismiss  --id 로 띄운 카드를 닫습니다.
      hook     claude: Claude Code 훅에서 호출합니다 (표준 입력의 JSON).
               codex <json>: Codex의 notify 프로그램으로 호출합니다.
    """

    // MARK: - Commands

    private static func notify(_ args: [String]) -> Int32 {
        let o = options(args)
        guard let title = o["title"] ?? o["_"], !title.isEmpty else {
            fputs("--title이 필요합니다.\n\n\(usage)\n", stderr)
            return 2
        }
        var request: [String: Any] = ["type": "notify", "title": title]
        for key in ["body", "subtitle", "app", "icon", "color", "id", "bundle-id"] {
            if let value = o[key] { request[key] = value }
        }
        if let d = o["duration"].flatMap(Double.init) { request["duration"] = d }
        if let p = o["progress"].flatMap(Double.init) { request["progress"] = p }
        send(request, wait: false)
        return lastSendSucceeded ? 0 : 1
    }

    private static func dismiss(_ args: [String]) -> Int32 {
        guard let id = options(args)["id"] else {
            fputs("--id가 필요합니다.\n", stderr)
            return 2
        }
        send(["type": "dismiss", "id": id], wait: false)
        return lastSendSucceeded ? 0 : 1
    }

    /// Hooks never fail the agent: errors are swallowed and the exit code is 0.
    private static func hook(_ args: [String]) -> Int32 {
        let agent = args.first?.lowercased() ?? "claude"
        var event: [String: Any] = [:]
        if agent == "codex" {
            // Codex passes the event as the last argument.
            if let json = args.dropFirst().last?.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] {
                event = object
            }
        } else {
            let input = FileHandle.standardInput.readDataToEndOfFile()
            event = (try? JSONSerialization.jsonObject(with: input) as? [String: Any]) ?? [:]
        }
        guard !event.isEmpty else { return 0 }
        let name = event["hook_event_name"] as? String ?? ""
        if name == "Stop", let path = event["transcript_path"] as? String,
           let last = lastAssistantText(transcript: path) {
            event["last_message"] = last
        }
        let env = ProcessInfo.processInfo.environment
        let request: [String: Any] = [
            "type": "agent",
            "agent": agent,
            "event": event,
            "pids": ancestors(),
            "bundleId": env["__CFBundleIdentifier"] ?? "",
            "term": env["TERM_PROGRAM"] ?? "",
        ]
        let waits = name == "PermissionRequest"
        // Claude Code's own timeout for this hook is set a bit longer.
        guard let answer = send(request, wait: waits, timeout: waits ? 590 : 2),
              let decision = answer["decision"] as? [String: Any] else { return 0 }
        let output: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": decision,
            ],
        ]
        if let data = try? JSONSerialization.data(withJSONObject: output) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([0x0A]))
        }
        return 0
    }

    // MARK: - Socket

    private static var lastSendSucceeded = false

    /// Sends one request; with `wait`, returns the app's answer.
    @discardableResult
    static func send(_ request: [String: Any], wait: Bool, timeout: Int = 2) -> [String: Any]? {
        lastSendSucceeded = false
        let path = IslandSocketPath.url.path
        guard var addr = IslandSocketPath.address(path),
              var data = try? JSONSerialization.data(withJSONObject: request) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            if !wait && request["type"] as? String != "agent" {
                fputs("OmniIsland가 실행 중이 아닙니다.\n", stderr)
            }
            return nil
        }
        data.append(0x0A)
        let written = data.withUnsafeBytes { raw in write(fd, raw.baseAddress, raw.count) }
        guard written == data.count else { return nil }
        lastSendSucceeded = true
        guard wait else { return nil }
        var tv = timeval(tv_sec: timeout, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        guard let line = IslandSocketServer.readLine(fd) else { return nil }
        return try? JSONSerialization.jsonObject(with: line) as? [String: Any]
    }

    // MARK: - Helpers

    /// `--key value` pairs; a lone first word is stored under "_".
    private static func options(_ args: [String]) -> [String: String] {
        var result: [String: String] = [:]
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg.hasPrefix("--") {
                let key = String(arg.dropFirst(2))
                if let eq = key.firstIndex(of: "=") {
                    result[String(key[..<eq])] = String(key[key.index(after: eq)...])
                } else if i + 1 < args.count, !args[i + 1].hasPrefix("--") {
                    result[key] = args[i + 1]
                    i += 1
                } else {
                    result[key] = "true"
                }
            } else if result["_"] == nil {
                result["_"] = arg
            }
            i += 1
        }
        return result
    }

    /// This process's parent chain, so the app can find the terminal window
    /// the agent runs in.
    private static func ancestors() -> [Int] {
        var result: [Int] = []
        var pid = getppid()
        while pid > 1 && result.count < 32 {
            result.append(Int(pid))
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.stride
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
            guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { break }
            pid = info.kp_eproc.e_ppid
        }
        return result
    }

    /// The text of the last assistant message in a Claude Code transcript
    /// (JSON lines), read from the end of the file.
    private static func lastAssistantText(transcript path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        let start = end > 256 * 1024 ? end - 256 * 1024 : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").reversed() {
            guard line.contains("\"assistant\""),
                  let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  object["type"] as? String == "assistant",
                  let message = object["message"] as? [String: Any] else { continue }
            if let content = message["content"] as? [[String: Any]] {
                let texts = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                if let joined = texts.last, !joined.isEmpty { return joined }
            } else if let content = message["content"] as? String, !content.isEmpty {
                return content
            }
        }
        return nil
    }
}
