import AppKit
import SQLite3

/// Reads new rows from the database where macOS keeps delivered
/// notifications (usernoted). Unlike banner observation this also sees apps
/// whose alert style is "None", but it needs Full Disk Access and relies on
/// an undocumented format that may change between macOS versions.
///
/// Locations tried, newest first:
/// - ~/Library/Group Containers/group.com.apple.usernoted/db2/db (macOS 15+)
/// - $DARWIN_USER_DIR/com.apple.notificationcenter/db2/db (macOS 14)
enum NotificationDatabaseReader {
    struct Row {
        var id: Int64
        var bundleId: String?
        var title: String?
        var subtitle: String?
        var body: String?
        var delivered: Date?
    }

    enum Failure: Error, Equatable {
        case notFound
        /// The file exists but cannot be opened: Full Disk Access is missing.
        case noPermission
        case unreadable(String)
    }

    static var candidatePaths: [String] {
        var paths = [NSHomeDirectory() + "/Library/Group Containers/group.com.apple.usernoted/db2/db"]
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        if confstr(_CS_DARWIN_USER_DIR, &buffer, buffer.count) > 0 {
            let dir = String(cString: buffer)
            paths.append((dir as NSString).appendingPathComponent("com.apple.notificationcenter/db2/db"))
        }
        return paths
    }

    static func locate() -> Result<String, Failure> {
        let fm = FileManager.default
        var sawFile = false
        for path in candidatePaths where fm.fileExists(atPath: path) {
            sawFile = true
            if fm.isReadableFile(atPath: path) { return .success(path) }
        }
        // Without Full Disk Access the Group Containers folder itself may be
        // hidden, so "not found" can also mean "no permission".
        if sawFile || !canListContainer() {
            return .failure(.noPermission)
        }
        return .failure(.notFound)
    }

    static let containerPath = NSHomeDirectory() + "/Library/Group Containers/group.com.apple.usernoted"

    /// Listing the usernoted container fails without Full Disk Access even
    /// when `fileExists` still says the folder is there.
    private static func canListContainer() -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: containerPath) else {
            // macOS 14 keeps the database elsewhere; nothing to judge here.
            return true
        }
        return (try? fm.contentsOfDirectory(atPath: containerPath)) != nil
    }

    /// Best guess at whether this app has Full Disk Access: the notification
    /// database (or, failing that, the user TCC database) can be opened.
    static func hasFullDiskAccess() -> Bool {
        if case .success(let path) = locate(), FileHandle(forReadingAtPath: path) != nil {
            return true
        }
        let tcc = NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db"
        return FileHandle(forReadingAtPath: tcc) != nil
    }

    /// Highest row id, so a fresh start does not replay old notifications.
    static func latestId(path: String) -> Result<Int64, Failure> {
        withDatabase(path) { db in
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT IFNULL(MAX(rec_id), 0) FROM record", -1, &stmt, nil) == SQLITE_OK
            else { return .failure(.unreadable(message(db))) }
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return .failure(.unreadable(message(db))) }
            return .success(sqlite3_column_int64(stmt, 0))
        }
    }

    static func rows(path: String, after id: Int64) -> Result<[Row], Failure> {
        withDatabase(path) { db in
            // Older and newer schemas differ in the date column, so fall back
            // to a query without it.
            let queries = [
                """
                SELECT r.rec_id, a.identifier, r.data, r.delivered_date
                FROM record r LEFT JOIN app a ON a.app_id = r.app_id
                WHERE r.rec_id > ?1 ORDER BY r.rec_id LIMIT 50
                """,
                """
                SELECT r.rec_id, a.identifier, r.data, NULL
                FROM record r LEFT JOIN app a ON a.app_id = r.app_id
                WHERE r.rec_id > ?1 ORDER BY r.rec_id LIMIT 50
                """,
                "SELECT rec_id, NULL, data, NULL FROM record WHERE rec_id > ?1 ORDER BY rec_id LIMIT 50",
            ]
            var stmt: OpaquePointer?
            guard queries.contains(where: { sqlite3_prepare_v2(db, $0, -1, &stmt, nil) == SQLITE_OK })
            else { return .failure(.unreadable(message(db))) }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, id)
            var rows: [Row] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                var row = Row(id: sqlite3_column_int64(stmt, 0))
                if let text = sqlite3_column_text(stmt, 1) {
                    row.bundleId = String(cString: text)
                }
                if let blob = sqlite3_column_blob(stmt, 2) {
                    let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(stmt, 2)))
                    decode(data, into: &row)
                }
                if sqlite3_column_type(stmt, 3) != SQLITE_NULL {
                    row.delivered = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(stmt, 3))
                }
                rows.append(row)
            }
            return .success(rows)
        }
    }

    /// The `data` column is a binary plist: { app, req: { titl, subt, body, … }, … }.
    private static func decode(_ data: Data, into row: inout Row) {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return }
        if row.bundleId == nil { row.bundleId = plist["app"] as? String }
        let req = plist["req"] as? [String: Any] ?? [:]
        func text(_ key: String) -> String? {
            guard let value = req[key] as? String else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        row.title = text("titl")
        row.subtitle = text("subt")
        row.body = text("body")
    }

    private static func withDatabase<T>(_ path: String, _ body: (OpaquePointer) -> Result<T, Failure>) -> Result<T, Failure> {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let status = sqlite3_open_v2(path, &db, flags, nil)
        defer { sqlite3_close(db) }
        guard status == SQLITE_OK, let db else {
            return .failure(status == SQLITE_CANTOPEN || status == SQLITE_AUTH || status == SQLITE_PERM
                            ? .noPermission : .unreadable("sqlite \(status)"))
        }
        sqlite3_busy_timeout(db, 200)
        return body(db)
    }

    private static func message(_ db: OpaquePointer) -> String {
        String(cString: sqlite3_errmsg(db))
    }

    // MARK: - Turning a row into a notification

    static func notification(from row: Row) -> IslandNotification? {
        guard row.title != nil || row.body != nil else { return nil }
        let appName = row.bundleId.flatMap(appName(for:)) ?? row.bundleId ?? "알림"
        return IslandNotification(
            source: .system,
            appName: appName,
            bundleId: row.bundleId,
            title: row.title ?? appName,
            subtitle: row.subtitle,
            body: row.body,
            date: row.delivered ?? Date()
        )
    }

    private static func appName(for bundleId: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
        let bundle = Bundle(url: url)
        let info = bundle?.localizedInfoDictionary ?? [:]
        let fallback = bundle?.infoDictionary ?? [:]
        return (info["CFBundleDisplayName"] ?? info["CFBundleName"]
                ?? fallback["CFBundleDisplayName"] ?? fallback["CFBundleName"]) as? String
            ?? FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

/// Polls the notification database for rows added after launch.
@MainActor
final class NotificationDatabaseWatcher {
    enum Status: Equatable {
        case off
        case running
        case needsFullDiskAccess
        case unavailable(String)

        var label: String {
            switch self {
            case .off: return "꺼짐"
            case .running: return "읽는 중"
            case .needsFullDiskAccess: return "전체 디스크 접근 권한이 필요합니다"
            case .unavailable(let reason): return "읽을 수 없습니다 (\(reason))"
            }
        }
    }

    var onNotification: ((IslandNotification) -> Void)?
    var onStatus: ((Status) -> Void)?
    private(set) var status: Status = .off {
        didSet {
            guard status != oldValue else { return }
            Log.info("notification database: \(status.label)" + (path.map { " (\($0))" } ?? ""))
            onStatus?(status)
        }
    }
    /// Database file being read, for diagnostics.
    var currentPath: String? { path }

    private let queue = DispatchQueue(label: "omni-island.notification-db", qos: .utility)
    private var timer: Timer?
    private var path: String?
    private var lastId: Int64?
    private var reading = false

    func configure(enabled: Bool) {
        if enabled { start() } else { stop() }
    }

    private func start() {
        guard timer == nil else { return }
        // File events below catch most writes at once; the timer is a fallback.
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        t.tolerance = 0.3
        RunLoop.main.add(t, forMode: .common)
        timer = t
        poll()
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        unwatch()
        path = nil
        lastId = nil
        status = .off
    }

    // MARK: - File events

    private var sources: [DispatchSourceFileSystemObject] = []
    private var watchedPath: String?
    private var pollAgain = false

    /// Watches the database and its write-ahead log, so a new row is read
    /// right after usernoted writes it instead of on the next timer tick.
    private func watch(_ path: String) {
        guard watchedPath != path else { return }
        unwatch()
        watchedPath = path
        for file in [path, path + "-wal"] {
            let fd = open(file, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
            source.setEventHandler { [weak self, weak source] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let flags = source?.data ?? []
                    if flags.contains(.delete) || flags.contains(.rename) {
                        // The log was replaced; watch the new file.
                        self.unwatch()
                    }
                    self.poll()
                }
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            sources.append(source)
        }
    }

    private func unwatch() {
        sources.forEach { $0.cancel() }
        sources.removeAll()
        watchedPath = nil
    }

    private func poll() {
        guard !reading else {
            pollAgain = true
            return
        }
        reading = true
        let knownPath = path
        let after = lastId
        queue.async { [weak self] in
            let outcome = Self.read(knownPath: knownPath, after: after)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.reading = false
                    guard self.timer != nil else { return }
                    self.apply(outcome)
                    if let path = self.path { self.watch(path) } else { self.unwatch() }
                    if self.pollAgain {
                        self.pollAgain = false
                        self.poll()
                    }
                }
            }
        }
    }

    private struct Outcome {
        var path: String?
        var lastId: Int64?
        var rows: [NotificationDatabaseReader.Row] = []
        var failure: NotificationDatabaseReader.Failure?
    }

    nonisolated private static func read(knownPath: String?, after: Int64?) -> Outcome {
        let path: String
        if let knownPath {
            path = knownPath
        } else {
            switch NotificationDatabaseReader.locate() {
            case .success(let found): path = found
            case .failure(let failure): return Outcome(failure: failure)
            }
        }
        guard let after else {
            // First read: only remember where the log ends.
            switch NotificationDatabaseReader.latestId(path: path) {
            case .success(let id): return Outcome(path: path, lastId: id)
            case .failure(let failure): return Outcome(failure: failure)
            }
        }
        switch NotificationDatabaseReader.rows(path: path, after: after) {
        case .success(let rows): return Outcome(path: path, lastId: rows.last?.id ?? after, rows: rows)
        case .failure(let failure): return Outcome(failure: failure)
        }
    }

    private func apply(_ outcome: Outcome) {
        if let failure = outcome.failure {
            path = nil
            lastId = nil
            switch failure {
            case .noPermission: status = .needsFullDiskAccess
            case .notFound: status = .unavailable("데이터베이스 파일 없음")
            case .unreadable(let reason): status = .unavailable(reason)
            }
            return
        }
        path = outcome.path
        lastId = outcome.lastId
        status = .running
        for row in outcome.rows {
            Log.info("notification database row \(row.id): \(row.bundleId ?? "?") title=\(row.title != nil) body=\(row.body != nil)")
            if let n = NotificationDatabaseReader.notification(from: row) {
                onNotification?(n)
            }
        }
    }
}

/// Merges notifications from banner observation and the database, so one
/// notification that both sources see is shown once.
@MainActor
final class NotificationDeduplicator {
    private var recent: [(key: String, bundle: String?, at: Date)] = []
    private let window: TimeInterval = 20

    /// Returns false when an equal notification passed through recently.
    func accept(_ n: IslandNotification) -> Bool {
        let now = Date()
        recent.removeAll { now.timeIntervalSince($0.at) > window }
        let key = Self.key(n)
        let bundle = n.bundleId?.lowercased()
        let duplicate = recent.contains { entry in
            guard !key.isEmpty, !entry.key.isEmpty else { return false }
            if entry.key == key { return true }
            if let bundle, let other = entry.bundle, bundle != other { return false }
            guard min(key.count, entry.key.count) >= 4 else { return false }
            return entry.key.contains(key) || key.contains(entry.key)
        }
        recent.append((key, bundle, now))
        return !duplicate
    }

    /// Letters and digits of title, subtitle and body. Banner reading and the
    /// database split the fields differently, so only their content counts.
    private static func key(_ n: IslandNotification) -> String {
        let text = [n.title, n.subtitle ?? "", n.body ?? ""].joined()
        return String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            .map(Character.init))
    }
}
