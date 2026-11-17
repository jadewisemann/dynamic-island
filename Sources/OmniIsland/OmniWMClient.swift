import Foundation

/// Runs `omniwmctl subscribe … --reconnect --format ndjson` and turns its
/// stdout into `OmniWMMessage`s on the main actor.
///
/// `--reconnect` already survives OmniWM relaunches once connected. This
/// class additionally restarts the process (with backoff) when the very first
/// connection fails, e.g. because IPC is not enabled yet.
@MainActor
final class OmniWMClient {
    enum Status: Equatable {
        case stopped
        case connecting
        case connected
        case failed(String)

        var label: String {
            switch self {
            case .stopped: return "중지됨"
            case .connecting: return "OmniWM에 연결하는 중…"
            case .connected: return "OmniWM에 연결됨"
            case .failed(let reason): return "연결 실패: \(reason)"
            }
        }
    }

    static let channels = "active-workspace,focus,windows-changed,layout-changed"

    var onMessage: ((OmniWMMessage) -> Void)?
    var onStatus: ((Status) -> Void)?
    private(set) var status: Status = .stopped {
        didSet { if status != oldValue { onStatus?(status) } }
    }

    private var process: Process?
    private var buffer = Data()
    private var stderrTail = ""
    private var retryDelay: TimeInterval = 1
    private var retryWork: DispatchWorkItem?
    private var wantsRunning = false
    private var executablePath: String?
    private var socketPath: String?

    func start(executablePath: String?, socketPath: String?) {
        self.executablePath = executablePath
        self.socketPath = socketPath
        wantsRunning = true
        retryDelay = 1
        launch()
    }

    func restart(executablePath: String?, socketPath: String?) {
        stop()
        start(executablePath: executablePath, socketPath: socketPath)
    }

    func stop() {
        wantsRunning = false
        retryWork?.cancel()
        retryWork = nil
        if let p = process {
            p.terminationHandler = nil
            (p.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            (p.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            if p.isRunning { p.terminate() }
        }
        process = nil
        buffer.removeAll()
        status = .stopped
    }

    // MARK: - Process

    private func launch() {
        guard wantsRunning else { return }
        guard let exe = Self.resolveExecutable(configured: executablePath) else {
            status = .failed("omniwmctl을 찾지 못했습니다")
            scheduleRetry()
            return
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = ["subscribe", Self.channels, "--reconnect", "--format", "ndjson"]
        var env = ProcessInfo.processInfo.environment
        if let socketPath { env["OMNIWM_SOCKET"] = socketPath }
        p.environment = env

        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice

        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.consume(chunk) }
            }
        }
        err.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty, let text = String(data: chunk, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.consumeStderr(text) }
            }
        }
        p.terminationHandler = { [weak self] proc in
            let code = proc.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.processExited(proc, code: code) }
            }
        }

        do {
            buffer.removeAll()
            stderrTail = ""
            status = .connecting
            try p.run()
            process = p
            Log.info("started \(exe) \(p.arguments?.joined(separator: " ") ?? "")")
        } catch {
            status = .failed("omniwmctl 실행 실패: \(error.localizedDescription)")
            scheduleRetry()
        }
    }

    private func processExited(_ proc: Process, code: Int32) {
        guard proc === process else { return }
        (proc.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        (proc.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        process = nil
        guard wantsRunning else { return }
        let detail = stderrTail.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason: String
        switch code {
        case 2: reason = "OmniWM IPC에 연결할 수 없습니다 (메뉴에서 Enable IPC를 켰는지 확인하세요)"
        case 1: reason = "OmniWM이 구독을 거부했습니다" + (detail.isEmpty ? "" : " – \(detail)")
        default: reason = "omniwmctl 종료 (코드 \(code))" + (detail.isEmpty ? "" : " – \(detail)")
        }
        status = .failed(reason)
        Log.info(reason)
        scheduleRetry()
    }

    private func scheduleRetry() {
        guard wantsRunning else { return }
        retryWork?.cancel()
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, 30)
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.launch() }
        }
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Stream parsing

    private func consume(_ chunk: Data) {
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            guard !line.isEmpty else { continue }
            handle(line: line)
        }
        // Guard against a runaway line without newline.
        if buffer.count > 8 * 1024 * 1024 { buffer.removeAll() }
    }

    private func handle(line: Data) {
        guard let message = OmniWMDecoder.decode(line: line) else { return }
        switch message {
        case .subscribed:
            status = .connected
            retryDelay = 1
        case .rejected(let code, let msg):
            status = .failed([code, msg].compactMap { $0 }.joined(separator: ": "))
        default:
            if status != .connected { status = .connected }
        }
        onMessage?(message)
    }

    private func consumeStderr(_ text: String) {
        stderrTail = String((stderrTail + text).suffix(400))
        if text.contains("reconnected") {
            status = .connected
        } else if text.contains("lost") || text.contains("retry") {
            status = .connecting
        }
        Log.info("omniwmctl: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    // MARK: - Locating omniwmctl

    static func resolveExecutable(configured: String?) -> String? {
        let fm = FileManager.default
        if let configured, !configured.isEmpty {
            return fm.isExecutableFile(atPath: configured) ? configured : nil
        }
        let home = fm.homeDirectoryForCurrentUser.path
        var candidates: [String] = []
        // GUI apps get a minimal PATH, so add the usual places explicitly.
        let pathDirs = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map(String.init)
        candidates += pathDirs.map { "\($0)/omniwmctl" }
        candidates += [
            "\(home)/.local/bin/omniwmctl",
            "\(home)/bin/omniwmctl",
            "/opt/homebrew/bin/omniwmctl",
            "/usr/local/bin/omniwmctl",
            "/Applications/OmniWM.app/Contents/MacOS/omniwmctl",
            "\(home)/Applications/OmniWM.app/Contents/MacOS/omniwmctl",
        ]
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }
}
