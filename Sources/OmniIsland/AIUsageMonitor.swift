import Foundation

/// Claude Code usage shown by the `usage` widgets.
///
/// Token counts come from the transcripts Claude Code writes under
/// `~/.claude/projects` (no network, no sign-in). Plan limits (the 5-hour and
/// weekly percentages `/usage` shows) come from the same endpoint Claude
/// Code itself calls, with the sign-in Claude Code keeps in the keychain;
/// they are left out when that is unavailable.
struct AIUsage: Equatable {
    struct Limit: Equatable, Identifiable {
        /// five_hour | seven_day | seven_day_opus | seven_day_sonnet
        let id: String
        /// 0...100
        let percent: Double
        let resetsAt: Date?

        var label: String {
            switch id {
            case "five_hour": return "5시간"
            case "seven_day": return "주간"
            case "seven_day_opus": return "주간 Opus"
            case "seven_day_sonnet": return "주간 Sonnet"
            default: return id
            }
        }
    }

    /// Tokens of the current 5-hour session (all kinds, cache included).
    var blockTokens = 0
    var blockMessages = 0
    /// When the current 5-hour session ends; nil when none is active.
    var blockEnds: Date?
    var todayTokens = 0
    var todayMessages = 0
    /// Plan limits, most important first. Empty when they could not be read.
    var limits: [Limit] = []
    var updated = Date.distantPast

    var fiveHour: Limit? { limits.first { $0.id == "five_hour" } }
    var weekly: Limit? { limits.first { $0.id == "seven_day" } }

    /// Short text for a wing or a square tile: "42%" or "1.2M".
    var shortText: String {
        if let five = fiveHour { return "\(Int(five.percent.rounded()))%" }
        return Self.tokens(blockEnds == nil ? todayTokens : blockTokens)
    }

    /// When the 5-hour window resets, from the limits or the local session.
    var resetDate: Date? { fiveHour?.resetsAt ?? blockEnds }

    static func tokens(_ n: Int) -> String {
        switch n {
        case ..<1000: return "\(n)"
        case ..<1_000_000: return String(format: n < 10_000 ? "%.1fK" : "%.0fK", Double(n) / 1000)
        default: return String(format: n < 10_000_000 ? "%.2fM" : "%.1fM", Double(n) / 1_000_000)
        }
    }

    /// "2시간 10분 후" / "14분 후".
    static func remaining(until date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        if minutes >= 24 * 60 { return "\(minutes / (24 * 60))일 후" }
        if minutes >= 60 { return minutes % 60 == 0 ? "\(minutes / 60)시간 후" : "\(minutes / 60)시간 \(minutes % 60)분 후" }
        return "\(minutes)분 후"
    }
}

/// Reads Claude Code usage every minute while a `usage` widget is shown.
@MainActor
final class AIUsageMonitor {
    var onChange: ((AIUsage?) -> Void)?

    private var config = IslandConfig.Usage()
    private var active = false
    private var timer: Timer?
    private let queue = DispatchQueue(label: "omni-island.ai-usage", qos: .utility)
    private let scanner = UsageScanner()
    private var reading = false
    private var limits: [AIUsage.Limit] = []
    private var limitsFetchedAt = Date.distantPast
    private var limitsFailures = 0
    private var fetchingLimits = false

    /// `used`: some wing, panel or dashboard item shows usage.
    func configure(_ config: IslandConfig.Usage, used: Bool) {
        let changed = config != self.config
        self.config = config
        let shouldRun = config.enabled && used
        if changed {
            limitsFailures = 0
            limitsFetchedAt = .distantPast
            if !config.planLimits { limits = [] }
        }
        if shouldRun && !active {
            active = true
            let t = Timer(timeInterval: max(config.refreshSec, 15), repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            t.tolerance = 5
            RunLoop.main.add(t, forMode: .common)
            timer = t
            refresh()
        } else if !shouldRun && active {
            active = false
            timer?.invalidate()
            timer = nil
            onChange?(nil)
        } else if shouldRun && changed {
            refresh()
        }
    }

    func refresh() {
        guard active else { return }
        readLocal()
        if config.planLimits { fetchLimitsIfDue() }
    }

    private func readLocal() {
        guard !reading else { return }
        reading = true
        let scanner = scanner
        queue.async { [weak self] in
            let summary = scanner.scan(now: Date())
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.reading = false
                    guard self.active else { return }
                    self.publish(summary)
                }
            }
        }
    }

    private var lastSummary = UsageScanner.Summary()

    private func publish(_ summary: UsageScanner.Summary? = nil) {
        if let summary { lastSummary = summary }
        let s = lastSummary
        var usage = AIUsage()
        usage.blockTokens = s.blockTokens
        usage.blockMessages = s.blockMessages
        usage.blockEnds = s.blockEnds
        usage.todayTokens = s.todayTokens
        usage.todayMessages = s.todayMessages
        // Limits whose window has already reset are stale.
        let now = Date()
        usage.limits = limits.filter { ($0.resetsAt ?? .distantFuture) > now }
        usage.updated = now
        onChange?(usage)
    }

    private func fetchLimitsIfDue() {
        guard !fetchingLimits else { return }
        // Every 5 minutes; slower after failures (10, 20, 40 … up to 60).
        let interval = limitsFailures == 0 ? 300.0 : min(3600, 300 * pow(2, Double(limitsFailures)))
        guard Date().timeIntervalSince(limitsFetchedAt) >= interval else { return }
        fetchingLimits = true
        limitsFetchedAt = Date()
        Task { [weak self] in
            let result = await PlanLimitsReader.fetch()
            guard let self else { return }
            self.fetchingLimits = false
            switch result {
            case .success(let list):
                self.limitsFailures = 0
                self.limits = list
            case .failure(let error):
                self.limitsFailures += 1
                Log.info("ai usage: plan limits unavailable (\(error))")
            }
            self.publish()
        }
    }
}

// MARK: - Local transcripts

/// Sums token usage from Claude Code's JSONL transcripts. Reads each file
/// only from where the previous scan stopped. Used on one queue only.
final class UsageScanner: @unchecked Sendable {
    struct Summary: Equatable {
        var blockTokens = 0
        var blockMessages = 0
        var blockEnds: Date?
        var todayTokens = 0
        var todayMessages = 0
    }

    private struct Entry {
        let date: Date
        let tokens: Int
        let key: String
    }

    private var offsets: [String: UInt64] = [:]
    private var entries: [Entry] = []
    private var seen = Set<String>()
    /// Entries older than this are dropped; enough for today and a 5-hour
    /// session that started yesterday.
    private let keep: TimeInterval = 30 * 3600

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso = ISO8601DateFormatter()

    static func parseDate(_ text: String) -> Date? {
        isoFractional.date(from: text) ?? iso.date(from: text)
    }

    /// Folders Claude Code keeps transcripts in.
    static var roots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var list: [URL] = []
        if let env = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
            for part in env.split(separator: ",") {
                list.append(URL(fileURLWithPath: String(part).trimmingCharacters(in: .whitespaces)))
            }
        }
        list.append(home.appendingPathComponent(".claude"))
        list.append(home.appendingPathComponent(".config/claude"))
        return list.map { $0.appendingPathComponent("projects") }
    }

    func scan(now: Date) -> Summary {
        let cutoff = now.addingTimeInterval(-keep)
        let fm = FileManager.default
        var present = Set<String>()
        for root in Self.roots {
            guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                                             options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in walker where url.pathExtension == "jsonl" {
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                guard let modified = values?.contentModificationDate, modified > cutoff else { continue }
                let path = url.path
                present.insert(path)
                let size = UInt64(values?.fileSize ?? 0)
                var offset = offsets[path] ?? 0
                if size < offset { offset = 0 } // rewritten
                guard size > offset else { continue }
                offsets[path] = read(url, from: offset, cutoff: cutoff)
            }
        }
        offsets = offsets.filter { present.contains($0.key) }
        prune(cutoff)
        return summarize(now: now)
    }

    /// Reads complete lines from `offset` and returns where the next scan
    /// starts (after the last newline).
    private func read(_ url: URL, from offset: UInt64, cutoff: Date) -> UInt64 {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return offset }
        defer { try? handle.close() }
        do { try handle.seek(toOffset: offset) } catch { return offset }
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return offset }
        guard let lastNewline = data.lastIndex(of: 0x0A) else { return offset }
        let complete = data[data.startIndex...lastNewline]
        for line in complete.split(separator: 0x0A, omittingEmptySubsequences: true) {
            // Cheap filter before parsing JSON.
            guard line.count > 20, line.range(of: Data("\"usage\"".utf8)) != nil else { continue }
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let message = object["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let stamp = object["timestamp"] as? String,
                  let date = Self.parseDate(stamp), date > cutoff else { continue }
            func int(_ key: String) -> Int { (usage[key] as? NSNumber)?.intValue ?? 0 }
            let tokens = int("input_tokens") + int("output_tokens")
                + int("cache_creation_input_tokens") + int("cache_read_input_tokens")
            guard tokens > 0 else { continue }
            // A streamed reply is written once per content block with the
            // same usage; count each message once.
            let id = (message["id"] as? String) ?? ""
            let request = (object["requestId"] as? String) ?? ""
            let key = id.isEmpty && request.isEmpty ? (object["uuid"] as? String ?? stamp) : id + ":" + request
            guard seen.insert(key).inserted else { continue }
            entries.append(Entry(date: date, tokens: tokens, key: key))
        }
        return offset + UInt64(complete.count)
    }

    private func prune(_ cutoff: Date) {
        guard entries.contains(where: { $0.date <= cutoff }) else { return }
        let dropped = entries.filter { $0.date <= cutoff }
        entries.removeAll { $0.date <= cutoff }
        for e in dropped { seen.remove(e.key) }
    }

    private func summarize(now: Date) -> Summary {
        var s = Summary()
        let sorted = entries.sorted { $0.date < $1.date }
        let startOfDay = Calendar.current.startOfDay(for: now)
        for e in sorted where e.date >= startOfDay {
            s.todayTokens += e.tokens
            s.todayMessages += 1
        }
        // 5-hour sessions as Claude Code counts them: a session starts at
        // the hour of its first message and lasts five hours.
        let length: TimeInterval = 5 * 3600
        var blockStart: Date?
        var tokens = 0
        var messages = 0
        for e in sorted {
            if let start = blockStart, e.date < start.addingTimeInterval(length) {
                tokens += e.tokens
                messages += 1
            } else {
                blockStart = Self.floorToHour(e.date)
                tokens = e.tokens
                messages = 1
            }
        }
        if let start = blockStart, now < start.addingTimeInterval(length) {
            s.blockTokens = tokens
            s.blockMessages = messages
            s.blockEnds = start.addingTimeInterval(length)
        }
        return s
    }

    private static func floorToHour(_ date: Date) -> Date {
        let t = date.timeIntervalSince1970
        return Date(timeIntervalSince1970: t - t.truncatingRemainder(dividingBy: 3600))
    }
}

// MARK: - Plan limits

/// Reads the plan limits with the sign-in Claude Code stores, from the
/// endpoint Claude Code's own `/usage` screen uses.
enum PlanLimitsReader {
    enum Failure: Error, CustomStringConvertible {
        case noCredentials
        case expired
        case http(Int)
        case network(String)
        case format

        var description: String {
            switch self {
            case .noCredentials: return "no Claude Code sign-in found"
            case .expired: return "Claude Code sign-in expired; it renews the next time Claude Code runs"
            case .http(let code): return "HTTP \(code)"
            case .network(let text): return text
            case .format: return "unexpected response"
            }
        }
    }

    static func fetch() async -> Result<[AIUsage.Limit], Failure> {
        let token: String
        switch await Task.detached(priority: .utility, operation: { accessToken() }).value {
        case .success(let t): token = t
        case .failure(let f): return .failure(f)
        }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("omni-island", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else { return .failure(.http(code)) }
            guard let list = parse(data) else { return .failure(.format) }
            return .success(list)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    static func parse(_ data: Data) -> [AIUsage.Limit]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let order = ["five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet"]
        var list: [AIUsage.Limit] = []
        for key in order {
            guard let entry = object[key] as? [String: Any],
                  let value = entry["utilization"] as? NSNumber else { continue }
            let reset = (entry["resets_at"] as? String).flatMap(UsageScanner.parseDate)
            list.append(AIUsage.Limit(id: key, percent: min(max(value.doubleValue, 0), 100), resetsAt: reset))
        }
        return list
    }

    /// The OAuth access token from the keychain item Claude Code writes,
    /// or from `~/.claude/.credentials.json` on setups without a keychain.
    private static func accessToken() -> Result<String, Failure> {
        var json: Data?
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        if (try? process.run()) != nil {
            let data = out.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if process.terminationStatus == 0, !data.isEmpty { json = data }
        }
        if json == nil {
            let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json")
            json = try? Data(contentsOf: file)
        }
        guard let json,
              let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let oauth = object["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return .failure(.noCredentials) }
        if let expires = (oauth["expiresAt"] as? NSNumber)?.doubleValue,
           Date(timeIntervalSince1970: expires / 1000) < Date() {
            return .failure(.expired)
        }
        return .success(token)
    }
}
