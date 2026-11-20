import AppKit

/// One installed application.
struct AppEntry: Identifiable, Equatable {
    var id: String { path }
    let path: String
    /// File name without ".app" ("Calculator").
    let fileName: String
    /// Localized name Finder shows ("계산기"); equal to fileName when not localized.
    let displayName: String
    let bundleId: String?

    var url: URL { URL(fileURLWithPath: path) }
}

/// The apps on this Mac, found by scanning the usual folders (after
/// nanolight's apps.zig), plus how often each was opened from the launcher.
@MainActor
final class AppIndex {
    private(set) var apps: [AppEntry] = []
    private(set) var candidates: [String: [FuzzyMatcher.Candidate]] = [:]
    private var lastScan = Date.distantPast
    private var scanning = false
    private var history: [String: HistoryEntry] = [:]

    struct HistoryEntry: Codable {
        var count: Int
        var last: Date
    }

    var onUpdate: (() -> Void)?

    static let historyURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/omni-island/launcher-history.json")

    init() {
        loadHistory()
    }

    /// Rescans when the list is older than a minute (apps come and go rarely).
    func refreshIfStale() {
        guard !scanning, Date().timeIntervalSince(lastScan) > 60 else { return }
        scanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let found = Self.scan()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.scanning = false
                    self.lastScan = Date()
                    self.set(found)
                }
            }
        }
    }

    private func set(_ found: [AppEntry]) {
        apps = found
        var map: [String: [FuzzyMatcher.Candidate]] = [:]
        for app in found {
            var names = [FuzzyMatcher.Candidate(app.displayName)]
            if app.fileName != app.displayName { names.append(FuzzyMatcher.Candidate(app.fileName)) }
            map[app.path] = names
        }
        candidates = map
        onUpdate?()
    }

    // MARK: - History

    func launchCount(_ app: AppEntry) -> Int { history[app.path]?.count ?? 0 }

    func recordLaunch(_ app: AppEntry) {
        var entry = history[app.path] ?? HistoryEntry(count: 0, last: Date())
        entry.count += 1
        entry.last = Date()
        history[app.path] = entry
        saveHistory()
    }

    /// The launch counts as launcher picks, for the first run that learns them.
    func pickSeed() -> [String: LauncherPicks.Entry] {
        Dictionary(uniqueKeysWithValues: history.map { path, e in
            ("apps:" + path, LauncherPicks.Entry(weight: Double(min(e.count, 20)), last: e.last))
        })
    }

    /// Most recently opened first; falls back to running apps when the
    /// launcher has not been used yet.
    func recentApps(limit: Int) -> [AppEntry] {
        guard limit > 0 else { return [] }
        let byPath = Dictionary(apps.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        var result = history.sorted { $0.value.last > $1.value.last }
            .compactMap { byPath[$0.key] }
        if result.count < limit {
            let running = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .compactMap { $0.bundleURL?.path }
                .compactMap { byPath[$0] }
            for app in running where !result.contains(app) { result.append(app) }
        }
        return Array(result.prefix(limit))
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: Self.historyURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        history = (try? decoder.decode([String: HistoryEntry].self, from: data)) ?? [:]
    }

    private func saveHistory() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(history) else { return }
        let url = Self.historyURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Scanning

    nonisolated static func scan() -> [AppEntry] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let roots: [(String, Int)] = [
            ("/Applications", 2),
            ("/System/Applications", 2),
            ("/System/Library/CoreServices/Applications", 1),
            ("\(home)/Applications", 2),
        ]
        var seen = Set<String>()
        var result: [AppEntry] = []
        func add(_ path: String) {
            let resolved = (path as NSString).resolvingSymlinksInPath
            guard seen.insert(resolved).inserted else { return }
            let fileName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            var display = fm.displayName(atPath: path)
            if display.hasSuffix(".app") { display = String(display.dropLast(4)) }
            let bundleId = Bundle(path: path)?.bundleIdentifier
            result.append(AppEntry(path: path, fileName: fileName, displayName: display, bundleId: bundleId))
        }
        func walk(_ dir: String, depth: Int) {
            guard depth > 0, let items = try? fm.contentsOfDirectory(atPath: dir) else { return }
            for item in items where !item.hasPrefix(".") {
                let path = (dir as NSString).appendingPathComponent(item)
                if item.hasSuffix(".app") {
                    add(path)
                } else {
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                        walk(path, depth: depth - 1)
                    }
                }
            }
        }
        for (root, depth) in roots { walk(root, depth: depth) }
        add("/System/Library/CoreServices/Finder.app")
        return result.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
}
