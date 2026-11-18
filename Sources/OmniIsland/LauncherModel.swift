import AppKit
import SwiftUI

/// An OmniWM window offered by the launcher.
struct LauncherWindow: Equatable {
    let id: String
    let appName: String
    let bundleId: String?
    let title: String
    let workspaceLabel: String
}

/// One row of launcher results.
struct LauncherItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case app(AppEntry)
        case window(LauncherWindow)
        case calculation(Double)
        case currency(CurrencyAnswer?)
        case file(FileHit)
        case pane(SettingsPane)
        case islandSettings
        /// A web address or search: what to open, and an SF Symbol.
        case web(URL, symbol: String)
        /// Something copied earlier, kept on the clipboard shelf.
        case shelf(ShelfItem)
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String?
    /// Character offsets of `title` the query matched.
    let hits: [Int]
    let score: Int
    /// Heading drawn above the first row of a group ("최근에 연 앱", "선반").
    var section: String? = nil

    var kindLabel: String {
        switch kind {
        case .app: return "앱"
        case .window: return "창"
        case .calculation: return "계산기"
        case .currency: return "환율"
        case .file(let f): return f.isDirectory ? "폴더" : "파일"
        case .pane: return "시스템 설정"
        case .islandSettings: return "OmniIsland"
        case .web: return "웹"
        case .shelf: return "선반"
        }
    }
}

/// Query, results and selection of the launcher (the island's search mode).
@MainActor
final class LauncherModel: ObservableObject {
    @Published private(set) var query = ""
    @Published private(set) var results: [LauncherItem] = []
    @Published var selection = 0
    /// Bumped when the text field should take the query from the model
    /// (Esc cleared it, Tab completed it).
    @Published private(set) var querySerial = 0

    let apps = AppIndex()
    var config = IslandConfig.Launcher()
    /// Open windows from OmniWM, in workspace order.
    var windowsProvider: (() -> [LauncherWindow])?
    /// The result list changed size; the island resizes with it.
    var onLayoutChange: (() -> Void)?
    /// Asks the island to close.
    var onClose: (() -> Void)?
    var onOpenApp: ((AppEntry) -> Void)?
    var onRevealApp: ((AppEntry) -> Void)?
    var onFocusWindow: ((LauncherWindow) -> Void)?
    var onSummonWindow: ((LauncherWindow) -> Void)?
    var onOpenSettings: (() -> Void)?
    /// Clipboard shelf, newest first.
    var shelfProvider: (() -> [ShelfItem])?
    var shelfCount = 4
    var onCopyShelf: ((ShelfItem) -> Void)?
    var onPasteShelf: ((ShelfItem) -> Void)?
    var onRemoveShelf: ((ShelfItem) -> Void)?
    var shelfDragProvider: ((ShelfItem) -> NSItemProvider)?

    // Answers that arrive later, each for the query it was asked with.
    private var epoch = 0
    private var asyncWork: DispatchWorkItem?
    private var files: (query: String, hits: [(FileHit, FuzzyMatch)]) = ("", [])
    private var suggestions: (query: String, words: [String]) = ("", [])
    private var suggestionCache: [String: [String]] = [:]
    private var currencyCache: [CurrencyQuery: CurrencyAnswer] = [:]
    private var currencyFailed: Set<CurrencyQuery> = []

    init() {
        apps.onUpdate = { [weak self] in self?.refresh() }
    }

    /// Number of section headings drawn above the rows.
    var sectionCount: Int {
        var count = 0
        var last: String?
        for item in results where item.section != last {
            last = item.section
            if item.section != nil { count += 1 }
        }
        return count
    }

    /// ⌘⌫: drops the selected shelf item.
    func removeSelected() -> Bool {
        guard results.indices.contains(selection), case .shelf(let item) = results[selection].kind else { return false }
        onRemoveShelf?(item)
        refresh()
        return true
    }

    /// Return copies a shelf item back, ⌘Return pastes it into the app
    /// that had focus.
    private static let shelfHint = "Return 복사 · ⌘Return 붙여넣기 · ⌘⌫ 삭제"

    private func shelfRow(_ item: ShelfItem, hits: [Int] = [], score: Int = 0, section: String? = nil) -> LauncherItem {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate(Calendar.current.isDateInToday(item.date) ? "HHmm" : "MMMdHHmm")
        let source = [item.sourceApp, f.string(from: item.date)].compactMap { $0 }.joined(separator: " · ")
        return LauncherItem(id: "shelf:" + item.id, kind: .shelf(item), title: item.title,
                            subtitle: source, hits: hits, score: score, section: section)
    }

    /// "선반", "shelf" or "clip", optionally followed by words to filter by.
    private static func shelfQuery(_ q: String) -> String? {
        let lower = q.lowercased()
        for word in ["선반", "shelf", "clip", "클립보드"] {
            if lower == word { return "" }
            if lower.hasPrefix(word + " ") { return String(q.dropFirst(word.count + 1)).trimmingCharacters(in: .whitespaces) }
        }
        return nil
    }

    // MARK: - Lifecycle

    func begin() {
        apps.refreshIfStale()
        query = ""
        selection = 0
        querySerial &+= 1
        files = ("", [])
        suggestions = ("", [])
        refresh()
    }

    func setQuery(_ text: String) {
        let cleaned = text.replacingOccurrences(of: "\n", with: " ")
        guard cleaned != query else { return }
        query = cleaned
        selection = 0
        refresh()
        scheduleAsync()
    }

    /// Esc: clears the query first, closes on an empty one.
    func cancel() {
        if query.isEmpty {
            onClose?()
        } else {
            query = ""
            selection = 0
            querySerial &+= 1
            refresh()
        }
    }

    /// Tab / →: takes the top result's name (or Google's first completion)
    /// when it starts with the query.
    func complete() -> Bool {
        guard !query.isEmpty else { return false }
        let lower = query.lowercased()
        let candidates = results.prefix(1).map(\.title) + currentSuggestions.prefix(1)
        guard let pick = candidates.first(where: { $0.lowercased().hasPrefix(lower) && $0.count > query.count })
        else { return false }
        query = pick
        querySerial &+= 1
        refresh()
        scheduleAsync()
        return true
    }

    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + delta + results.count) % results.count
    }

    /// Return (or a click): runs a row. `alternate` is ⌘Return.
    func activate(index: Int? = nil, alternate: Bool = false) {
        let i = index ?? selection
        guard results.indices.contains(i) else { return }
        let item = results[i]
        if case .currency(nil) = item.kind { return }
        onClose?()
        switch item.kind {
        case .app(let app):
            if alternate {
                onRevealApp?(app)
            } else {
                apps.recordLaunch(app)
                onOpenApp?(app)
            }
        case .window(let window):
            if alternate { onSummonWindow?(window) } else { onFocusWindow?(window) }
        case .calculation(let value):
            copy(Calculator.plain(value))
        case .currency(let answer):
            if let answer { copy(Calculator.plain((answer.value * 100).rounded() / 100)) }
        case .file(let file):
            let url = URL(fileURLWithPath: file.path)
            if alternate { NSWorkspace.shared.activateFileViewerSelecting([url]) } else { NSWorkspace.shared.open(url) }
        case .pane(let pane):
            if let url = pane.url { NSWorkspace.shared.open(url) }
        case .islandSettings:
            onOpenSettings?()
        case .web(let url, _):
            NSWorkspace.shared.open(url)
        case .shelf(let shelfItem):
            if alternate { onPasteShelf?(shelfItem) } else { onCopyShelf?(shelfItem) }
        }
    }

    private func copy(_ text: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
    }

    // MARK: - Answers that arrive later

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    private func scheduleAsync() {
        asyncWork?.cancel()
        epoch &+= 1
        let q = trimmedQuery
        guard !q.isEmpty else { return }
        let asked = epoch
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.ask(q, epoch: asked) }
        }
        asyncWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func ask(_ q: String, epoch asked: Int) {
        guard asked == epoch else { return }
        if config.searchFiles {
            let limit = max(1, Int(config.maxFiles))
            DispatchQueue.global(qos: .userInitiated).async {
                let found = FileSearch.find(q, limit: limit)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { [weak self] in
                        guard let self, asked == self.epoch else { return }
                        self.files = (q, found)
                        self.refresh()
                    }
                }
            }
        }
        if config.webSearch && config.suggestions && WebSearch.eligible(q) {
            if let cached = suggestionCache[q.lowercased()] {
                suggestions = (q, cached)
                refresh()
            } else {
                WebSearch.suggestions(for: q) { [weak self] words in
                    guard let self, let words else { return }
                    self.suggestionCache[q.lowercased()] = words
                    guard asked == self.epoch else { return }
                    self.suggestions = (q, words)
                    self.refresh()
                }
            }
        }
        if config.currency, let cq = Currency.parse(q), currencyCache[cq] == nil, !currencyFailed.contains(cq) {
            Currency.fetch(cq) { [weak self] answer in
                guard let self else { return }
                if let answer { self.currencyCache[cq] = answer } else { self.currencyFailed.insert(cq) }
                self.refresh()
            }
        }
    }

    /// Completions for the query, or the ones for fewer letters that still
    /// begin with it, so the rows don't blink at every key.
    private var currentSuggestions: [String] {
        let q = trimmedQuery.lowercased()
        guard !q.isEmpty, !suggestions.words.isEmpty, q.hasPrefix(suggestions.query.lowercased()) else { return [] }
        return suggestions.words.filter { $0.lowercased().hasPrefix(q) && $0.lowercased() != q }
    }

    // MARK: - Searching

    private func refresh() {
        let selectedId = results.indices.contains(selection) ? results[selection].id : nil
        results = search(query)
        if let selectedId, selection != 0, let kept = results.firstIndex(where: { $0.id == selectedId }) {
            selection = kept
        } else if selection >= results.count {
            selection = 0
        }
        onLayoutChange?()
    }

    private func search(_ text: String) -> [LauncherItem] {
        let limit = max(3, Int(config.maxResults))
        let q = text.trimmingCharacters(in: .whitespaces)
        let shelf = shelfProvider?() ?? []
        if q.isEmpty {
            var list: [LauncherItem] = []
            if config.showRecent {
                list = apps.recentApps(limit: min(Int(config.recentCount), limit)).map { app in
                    LauncherItem(id: "app:" + app.path, kind: .app(app), title: app.displayName,
                                 subtitle: nil, hits: [], score: 0, section: "최근에 연 앱")
                }
            }
            list += shelf.prefix(max(0, shelfCount)).map { shelfRow($0, section: "선반 · " + Self.shelfHint) }
            return list
        }

        // "선반 …" lists only the shelf.
        if let filter = Self.shelfQuery(q) {
            let matching = filter.isEmpty ? shelf : shelf.filter { $0.searchText.localizedCaseInsensitiveContains(filter) }
            return matching.prefix(max(limit, 12)).map { shelfRow($0, section: "선반 · " + Self.shelfHint) }
        }

        // Answers on top.
        var answers: [LauncherItem] = []
        if config.calculator, let value = Calculator.evaluate(q) {
            answers.append(LauncherItem(id: "calc", kind: .calculation(value), title: "= " + Calculator.format(value),
                                        subtitle: "Return을 누르면 결과를 복사합니다", hits: [], score: 0))
        }
        if config.currency, let cq = Currency.parse(q) {
            let title = "\(Calculator.format(cq.amount)) \(cq.from) → \(cq.to)"
            if let answer = currencyCache[cq] {
                answers.append(LauncherItem(
                    id: "currency", kind: .currency(answer),
                    title: "\(Calculator.format((answer.value * 100).rounded() / 100)) \(cq.to)",
                    subtitle: "\(title) · ECB \(answer.date) 기준 · Return을 누르면 복사합니다", hits: [], score: 0))
            } else {
                let failed = currencyFailed.contains(cq)
                answers.append(LauncherItem(id: "currency", kind: .currency(nil), title: title,
                                            subtitle: failed ? "환율을 가져오지 못했습니다" : "환율을 가져오는 중입니다…",
                                            hits: [], score: 0))
            }
        }

        // Local results, ranked together.
        var items: [LauncherItem] = []
        if config.searchApps {
            for app in apps.apps {
                guard let names = apps.candidates[app.path] else { continue }
                var best: FuzzyMatch?
                var bestIsDisplay = true
                for (n, name) in names.enumerated() {
                    if let m = FuzzyMatcher.match(q, name), m.score > (best?.score ?? -1) {
                        best = m
                        bestIsDisplay = n == 0
                    }
                }
                guard let best else { continue }
                let boost = min(apps.launchCount(app), 20) * 8
                let subtitle = app.fileName != app.displayName ? app.fileName : nil
                items.append(LauncherItem(id: "app:" + app.path, kind: .app(app), title: app.displayName,
                                          subtitle: subtitle, hits: bestIsDisplay ? best.hits : [],
                                          score: best.score + boost))
            }
        }

        if config.searchWindows, let windows = windowsProvider?() {
            for window in windows {
                let appMatch = FuzzyMatcher.match(q, FuzzyMatcher.Candidate(window.appName))
                let titleMatch = window.title.isEmpty ? nil : FuzzyMatcher.match(q, FuzzyMatcher.Candidate(window.title))
                let score = max(appMatch?.score ?? -1, titleMatch?.score ?? -1)
                guard score >= 0 else { continue }
                let title = window.title.isEmpty ? window.appName : window.title
                let hits = window.title.isEmpty ? (appMatch?.hits ?? []) : (titleMatch?.hits ?? [])
                items.append(LauncherItem(
                    id: "window:" + window.id, kind: .window(window), title: title,
                    subtitle: "\(window.appName) · 워크스페이스 \(window.workspaceLabel)",
                    hits: hits, score: score - 40))
            }
        }

        if config.searchSettings {
            for (pane, match) in SettingsPanes.search(q) {
                items.append(LauncherItem(id: "pane:" + pane.id, kind: .pane(pane), title: pane.displayName,
                                          subtitle: "시스템 설정", hits: match.hits, score: match.score - 60))
            }
            let own = ["settings", "설정", "omniisland", "preferences", "환경설정"]
                .compactMap { FuzzyMatcher.match(q, FuzzyMatcher.Candidate($0)) }
                .filter { $0.score >= 600 }
                .map(\.score).max()
            if let own {
                items.append(LauncherItem(id: "island-settings", kind: .islandSettings, title: "OmniIsland 설정",
                                          subtitle: "아일랜드의 모양, 위젯, 런처를 바꿉니다", hits: [], score: own - 80))
            }
        }

        if config.searchFiles, !files.hits.isEmpty, q.lowercased().hasPrefix(files.query.lowercased()) {
            for (file, _) in files.hits {
                // Re-rank against what is typed now; drop what no longer matches.
                // Spotlight's own matches (diacritics, inside words) stay for the query they answered.
                var match = FuzzyMatcher.match(q, FuzzyMatcher.Candidate(file.name))
                if match == nil && q == files.query { match = FuzzyMatch(score: 100, hits: []) }
                guard let match else { continue }
                let folder = (file.path as NSString).deletingLastPathComponent
                    .replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
                items.append(LauncherItem(id: "file:" + file.path, kind: .file(file), title: file.name,
                                          subtitle: folder, hits: match.hits, score: match.score - 120))
            }
        }

        if q.count >= 2 {
            for item in shelf {
                if let m = FuzzyMatcher.match(q, FuzzyMatcher.Candidate(item.title)), m.score >= 400 {
                    items.append(shelfRow(item, hits: m.hits, score: m.score - 150))
                } else if item.searchText.localizedCaseInsensitiveContains(q) {
                    items.append(shelfRow(item, score: 60))
                }
            }
        }

        items.sort { a, b in
            a.score != b.score ? a.score > b.score
                : a.title.localizedStandardCompare(b.title) == .orderedAscending
        }

        // The web last: an address, a search for exactly what is typed, then
        // Google's completions and the other engines.
        var web: [LauncherItem] = []
        if let address = WebSearch.address(q) {
            web.append(LauncherItem(id: "address", kind: .web(address, symbol: "safari"),
                                    title: address.absoluteString, subtitle: "브라우저에서 열기", hits: [], score: 0))
        }
        if config.webSearch, let url = WebSearch.googleURL(q) {
            web.append(LauncherItem(id: "google", kind: .web(url, symbol: "magnifyingglass"),
                                    title: q, subtitle: "Google에서 검색", hits: [], score: 0))
            if config.suggestions {
                for word in currentSuggestions.prefix(max(0, Int(config.maxSuggestions))) {
                    guard let url = WebSearch.googleURL(word) else { continue }
                    web.append(LauncherItem(id: "suggest:" + word, kind: .web(url, symbol: "magnifyingglass"),
                                            title: word, subtitle: "Google 추천 검색어",
                                            hits: Array(min(q.count, word.count)..<word.count), score: 0))
                }
            }
        }
        if config.askClaude, let url = WebSearch.url("https://claude.ai/new", "q", q) {
            web.append(LauncherItem(id: "claude", kind: .web(url, symbol: "sparkles"),
                                    title: q, subtitle: "Claude에게 묻기", hits: [], score: 0))
        }
        if config.askGrok, let url = WebSearch.url("https://grok.com/", "q", q) {
            web.append(LauncherItem(id: "grok", kind: .web(url, symbol: "bubble.left.and.text.bubble.right"),
                                    title: q, subtitle: "Grok에게 묻기", hits: [], score: 0))
        }
        if config.searchX, let url = WebSearch.url("https://x.com/search", "q", q) {
            web.append(LauncherItem(id: "x", kind: .web(url, symbol: "number"),
                                    title: q, subtitle: "X에서 검색", hits: [], score: 0))
        }

        // Answers and local rows first; the web keeps at least its first row
        // (a search for what is typed) so Return always does something.
        let reservedForWeb = min(web.count, max(1, limit - answers.count - items.count))
        let localRoom = max(0, limit - answers.count - reservedForWeb)
        var list = answers + items.prefix(localRoom)
        list += web.prefix(limit - list.count)
        return list
    }

    // MARK: - Layout

    static let fieldHeight: CGFloat = 40
    static let rowHeight: CGFloat = 40
    static let headerHeight: CGFloat = 22
    static let messageHeight: CGFloat = 34
    static let verticalPadding: CGFloat = 14

    /// Height of the launcher part below the workspace row.
    var bodyHeight: CGFloat {
        var height = Self.fieldHeight + Self.verticalPadding
        height += CGFloat(sectionCount) * Self.headerHeight
        if results.isEmpty && !query.isEmpty {
            height += Self.messageHeight
        } else {
            height += CGFloat(results.count) * Self.rowHeight
        }
        return height
    }

    /// Tallest the launcher can get, for sizing the panel.
    var maximumBodyHeight: CGFloat {
        Self.fieldHeight + Self.verticalPadding + 2 * Self.headerHeight
            + CGFloat(max(max(3, Int(config.maxResults)), Int(config.recentCount) + shelfCount, 12)) * Self.rowHeight
    }
}
