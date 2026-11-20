import Foundation

/// What was picked in the launcher, so the rows people actually choose rise
/// in the results (the way Raycast and Alfred learn): every row keeps a
/// frecency (how often, decaying with time), and every query keeps which
/// rows were picked after typing it ("sa" → Safari, not System Settings).
@MainActor
final class LauncherPicks {
    struct Entry: Codable {
        /// Picks, each worth less the older it is (halves every `halfLife`).
        var weight: Double
        var last: Date
    }

    struct Store: Codable {
        var items: [String: Entry] = [:]
        /// Typed query (lowercased) → row id → picks after typing it.
        var queries: [String: [String: Entry]] = [:]
    }

    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/omni-island/launcher-picks.json")

    /// A pick counts half as much after two weeks.
    static let halfLife: TimeInterval = 14 * 24 * 3600
    /// Points a row gains for being picked often, at most.
    static let maxFrecencyBoost = 160.0
    /// Points a row gains for being picked after typing this very query, at most.
    /// Enough to lift a picked row over a closer name match of another row.
    static let maxQueryBoost = 320.0
    /// Rows and queries kept, so the file does not grow forever.
    static let maxItems = 2000
    static let maxQueries = 1000

    private var store = Store()

    /// `seed` gives the old app launch counts for a first run, so a new
    /// version does not forget which apps were opened often.
    init(seed: () -> [String: Entry] = { [:] }) {
        if let data = try? Data(contentsOf: Self.url) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            store = (try? decoder.decode(Store.self, from: data)) ?? Store()
        } else {
            store.items = seed()
        }
    }

    static func key(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func decayed(_ e: Entry, now: Date) -> Double {
        e.weight * pow(0.5, now.timeIntervalSince(e.last) / halfLife)
    }

    private static func bumped(_ e: Entry?, now: Date) -> Entry {
        Entry(weight: (e.map { decayed($0, now: now) } ?? 0) + 1, last: now)
    }

    func record(_ id: String, query: String) {
        let now = Date()
        store.items[id] = Self.bumped(store.items[id], now: now)
        let q = Self.key(query)
        if !q.isEmpty {
            var picks = store.queries[q] ?? [:]
            picks[id] = Self.bumped(picks[id], now: now)
            store.queries[q] = picks
        }
        prune(now: now)
        save()
    }

    /// Extra points for `id` when `query` is typed.
    func boost(_ id: String, query: String, now: Date = Date()) -> Int {
        var points = 0.0
        if let e = store.items[id] {
            // 1 pick ≈ 40, 4 ≈ 107, levels off near the cap.
            let w = Self.decayed(e, now: now)
            points += Self.maxFrecencyBoost * (1 - pow(0.5, w / 2))
        }
        let q = Self.key(query)
        if !q.isEmpty {
            var w = 0.0
            if let e = store.queries[q]?[id] { w += Self.decayed(e, now: now) }
            // A shorter query typed before ("sa" when "saf" is typed now)
            // counts too, a little less for each letter of difference.
            var shorter = q
            while shorter.count > 1 {
                shorter.removeLast()
                if let e = store.queries[shorter]?[id] {
                    w += Self.decayed(e, now: now) * 0.5 / Double(q.count - shorter.count)
                }
            }
            if w > 0 { points += Self.maxQueryBoost * (1 - pow(0.5, w)) }
        }
        return Int(points.rounded())
    }

    private func prune(now: Date) {
        if store.items.count > Self.maxItems {
            let keep = store.items.sorted { Self.decayed($0.value, now: now) > Self.decayed($1.value, now: now) }
                .prefix(Self.maxItems)
            store.items = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        if store.queries.count > Self.maxQueries {
            let keep = store.queries.sorted { a, b in
                (a.value.values.map(\.last).max() ?? .distantPast) > (b.value.values.map(\.last).max() ?? .distantPast)
            }.prefix(Self.maxQueries)
            store.queries = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(store) else { return }
        let url = Self.url
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
