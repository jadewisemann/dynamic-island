import AppKit

/// A built-in app of the launcher. Each one answers the top-level search
/// (when it takes part in it), and the ones with a mode can also be entered
/// on their own by typing their trigger prefix and a space ("c " → the
/// clipboard manager), the way "!" switches Claude Code to shell commands.
@MainActor
protocol LauncherPlugin: AnyObject {
    /// Key in `launcher.prefixes` and in item ids.
    var id: String { get }
    var name: String { get }
    var symbol: String { get }
    /// Words that find the plugin's own row ("clipboard", "클립보드").
    var keywords: [String] { get }
    /// Can be entered with its prefix and lists its own rows there.
    var hasMode: Bool { get }
    /// Rows can be picked several at a time (Tab, ⇧↑↓, ⌘-click) inside the mode.
    var multiSelect: Bool { get }
    var placeholder: String { get }
    /// Takes part in the top-level search.
    var inRoot: Bool { get }

    /// Rows for `query` (already trimmed). Inside the mode the plugin orders
    /// the rows itself; at the top level the launcher ranks them by score.
    func search(_ query: String, inMode: Bool) -> [LauncherItem]
    /// Slow work, run once typing stops. Calls `done` when it has new rows.
    func fetch(_ query: String, inMode: Bool, isCurrent: @escaping @MainActor () -> Bool,
               done: @escaping @MainActor () -> Void)
    /// False for a row that is still waiting for its answer.
    func canActivate(_ item: LauncherItem) -> Bool
    /// Return (or ⌘Return when `alternate`) on one row, or on the picked rows.
    func activate(_ items: [LauncherItem], alternate: Bool)
    /// ⌘⌫ on a row. True when the row was removed.
    func remove(_ item: LauncherItem) -> Bool
    func dragProvider(_ item: LauncherItem) -> NSItemProvider?
    /// The launcher opened again.
    func reset()
}

extension LauncherPlugin {
    var keywords: [String] { [] }
    var hasMode: Bool { false }
    var multiSelect: Bool { false }
    var placeholder: String { "" }
    func fetch(_ query: String, inMode: Bool, isCurrent: @escaping @MainActor () -> Bool,
               done: @escaping @MainActor () -> Void) {}
    func canActivate(_ item: LauncherItem) -> Bool { true }
    func remove(_ item: LauncherItem) -> Bool { false }
    func dragProvider(_ item: LauncherItem) -> NSItemProvider? { nil }
    func reset() {}

    func row(_ key: String, _ kind: LauncherItem.Kind, title: String, subtitle: String?,
             hits: [Int] = [], score: Int = 0, section: String? = nil,
             group: LauncherItem.Group = .local) -> LauncherItem {
        LauncherItem(id: "\(id):\(key)", kind: kind, title: title, subtitle: subtitle, hits: hits,
                     score: score, section: section, group: group, plugin: id)
    }

    /// Inside a mode the best match goes first; ties by name.
    func ranked(_ items: [LauncherItem]) -> [LauncherItem] {
        items.sorted { a, b in
            a.score != b.score ? a.score > b.score
                : a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }
}

private func copyToClipboard(_ text: String) {
    let board = NSPasteboard.general
    board.clearContents()
    board.setString(text, forType: .string)
}

// MARK: - Calculator

@MainActor
final class CalculatorPlugin: LauncherPlugin {
    unowned let host: LauncherModel
    init(host: LauncherModel) { self.host = host }

    let id = "calculator"
    let name = "계산기"
    let symbol = "equal.square.fill"
    var inRoot: Bool { host.config.calculator }

    func search(_ query: String, inMode: Bool) -> [LauncherItem] {
        guard let value = Calculator.evaluate(query) else { return [] }
        return [row("result", .calculation(value), title: "= " + Calculator.format(value),
                    subtitle: "Return을 누르면 결과를 복사합니다", group: .answer)]
    }

    func activate(_ items: [LauncherItem], alternate: Bool) {
        guard case .calculation(let value) = items.first?.kind else { return }
        copyToClipboard(Calculator.plain(value))
    }
}

// MARK: - Currency

@MainActor
final class CurrencyPlugin: LauncherPlugin {
    unowned let host: LauncherModel
    init(host: LauncherModel) { self.host = host }

    let id = "currency"
    let name = "환율"
    let symbol = "dollarsign.circle.fill"
    var inRoot: Bool { host.config.currency }

    private var cache: [CurrencyQuery: CurrencyAnswer] = [:]
    private var failed: Set<CurrencyQuery> = []

    func search(_ query: String, inMode: Bool) -> [LauncherItem] {
        guard let cq = Currency.parse(query) else { return [] }
        let title = "\(Calculator.format(cq.amount)) \(cq.from) → \(cq.to)"
        if let answer = cache[cq] {
            return [row("answer", .currency(answer),
                        title: "\(Calculator.format((answer.value * 100).rounded() / 100)) \(cq.to)",
                        subtitle: "\(title) · ECB \(answer.date) 기준 · Return을 누르면 복사합니다", group: .answer)]
        }
        return [row("answer", .currency(nil), title: title,
                    subtitle: failed.contains(cq) ? "환율을 가져오지 못했습니다" : "환율을 가져오는 중입니다…",
                    group: .answer)]
    }

    func fetch(_ query: String, inMode: Bool, isCurrent: @escaping @MainActor () -> Bool,
               done: @escaping @MainActor () -> Void) {
        guard let cq = Currency.parse(query), cache[cq] == nil, !failed.contains(cq) else { return }
        Currency.fetch(cq) { [weak self] answer in
            guard let self else { return }
            if let answer { self.cache[cq] = answer } else { self.failed.insert(cq) }
            done()
        }
    }

    func canActivate(_ item: LauncherItem) -> Bool {
        if case .currency(nil) = item.kind { return false }
        return true
    }

    func activate(_ items: [LauncherItem], alternate: Bool) {
        guard case .currency(let answer?) = items.first?.kind else { return }
        copyToClipboard(Calculator.plain((answer.value * 100).rounded() / 100))
    }
}

// MARK: - Apps

@MainActor
final class AppsPlugin: LauncherPlugin {
    unowned let host: LauncherModel
    init(host: LauncherModel) { self.host = host }

    let id = "apps"
    let name = "앱"
    let symbol = "square.grid.2x2"
    let keywords = ["apps", "applications", "앱", "응용 프로그램"]
    let hasMode = true
    let placeholder = "앱 이름을 입력합니다 · ⌘Return은 Finder에서 보기"
    var inRoot: Bool { host.config.searchApps }

    func search(_ query: String, inMode: Bool) -> [LauncherItem] {
        let apps = host.apps
        if query.isEmpty {
            if inMode {
                return ranked(apps.apps.map { app in
                    row(app.path, .app(app), title: app.displayName, subtitle: nil,
                        score: min(apps.launchCount(app), 50))
                })
            }
            guard host.config.showRecent else { return [] }
            let count = min(Int(host.config.recentCount), max(3, Int(host.config.maxResults)))
            return apps.recentApps(limit: count).map { app in
                row(app.path, .app(app), title: app.displayName, subtitle: nil, section: "최근에 연 앱")
            }
        }
        var items: [LauncherItem] = []
        for app in apps.apps {
            guard let names = apps.candidates[app.path] else { continue }
            var best: FuzzyMatch?
            var bestIsDisplay = true
            for (n, name) in names.enumerated() {
                if let m = FuzzyMatcher.match(query, name), m.score > (best?.score ?? -1) {
                    best = m
                    bestIsDisplay = n == 0
                }
            }
            guard let best else { continue }
            let boost = min(apps.launchCount(app), 20) * 8
            let subtitle = app.fileName != app.displayName ? app.fileName : nil
            items.append(row(app.path, .app(app), title: app.displayName, subtitle: subtitle,
                             hits: bestIsDisplay ? best.hits : [], score: best.score + boost))
        }
        return inMode ? ranked(items) : items
    }

    func activate(_ items: [LauncherItem], alternate: Bool) {
        guard case .app(let app) = items.first?.kind else { return }
        if alternate {
            host.onRevealApp?(app)
        } else {
            host.apps.recordLaunch(app)
            host.onOpenApp?(app)
        }
    }
}

// MARK: - Windows

@MainActor
final class WindowsPlugin: LauncherPlugin {
    unowned let host: LauncherModel
    init(host: LauncherModel) { self.host = host }

    let id = "windows"
    let name = "창 관리자"
    let symbol = "macwindow.on.rectangle"
    let keywords = ["windows", "window", "창", "창 관리자"]
    let hasMode = true
    let placeholder = "열린 창을 앱 이름이나 제목으로 찾습니다 · ⌘Return은 여기로 불러오기"
    var inRoot: Bool { host.config.searchWindows }

    func search(_ query: String, inMode: Bool) -> [LauncherItem] {
        let windows = host.windowsProvider?() ?? []
        if query.isEmpty {
            guard inMode else { return [] }
            // Every window, under its workspace.
            return windows.map { window in
                row(window.id, .window(window), title: window.title.isEmpty ? window.appName : window.title,
                    subtitle: window.appName, section: "워크스페이스 \(window.workspaceLabel)")
            }
        }
        var items: [LauncherItem] = []
        for window in windows {
            let appMatch = FuzzyMatcher.match(query, FuzzyMatcher.Candidate(window.appName))
            let titleMatch = window.title.isEmpty ? nil : FuzzyMatcher.match(query, FuzzyMatcher.Candidate(window.title))
            let score = max(appMatch?.score ?? -1, titleMatch?.score ?? -1)
            guard score >= 0 else { continue }
            let title = window.title.isEmpty ? window.appName : window.title
            let hits = window.title.isEmpty ? (appMatch?.hits ?? []) : (titleMatch?.hits ?? [])
            items.append(row(window.id, .window(window), title: title,
                             subtitle: "\(window.appName) · 워크스페이스 \(window.workspaceLabel)",
                             hits: hits, score: inMode ? score : score - 40))
        }
        return inMode ? ranked(items) : items
    }

    func activate(_ items: [LauncherItem], alternate: Bool) {
        guard case .window(let window) = items.first?.kind else { return }
        if alternate { host.onSummonWindow?(window) } else { host.onFocusWindow?(window) }
    }
}

// MARK: - Settings

@MainActor
final class SettingsPlugin: LauncherPlugin {
    unowned let host: LauncherModel
    init(host: LauncherModel) { self.host = host }

    let id = "settings"
    let name = "설정 관리자"
    let symbol = "gearshape.fill"
    let keywords = ["settings", "preferences", "system settings", "설정", "시스템 설정", "환경설정"]
    let hasMode = true
    let placeholder = "시스템 설정 패널과 OmniIsland 설정을 찾습니다"
    var inRoot: Bool { host.config.searchSettings }

    private static let ownNames = ["settings", "설정", "omniisland", "preferences", "환경설정", "아일랜드"]

    private func islandRow(score: Int, section: String? = nil) -> LauncherItem {
        row("island", .islandSettings, title: "OmniIsland 설정",
            subtitle: "아일랜드의 모양, 위젯, 런처를 바꿉니다", score: score, section: section)
    }

    func search(_ query: String, inMode: Bool) -> [LauncherItem] {
        if query.isEmpty {
            guard inMode else { return [] }
            return [islandRow(score: 0, section: "OmniIsland")]
                + SettingsPanes.available.map { pane in
                    row(pane.id, .pane(pane), title: pane.displayName, subtitle: nil, section: "시스템 설정")
                }
        }
        var items = SettingsPanes.search(query, minLength: inMode ? 1 : 2).map { pane, match in
            row(pane.id, .pane(pane), title: pane.displayName, subtitle: "시스템 설정",
                hits: match.hits, score: inMode ? match.score : match.score - 60)
        }
        let own = Self.ownNames
            .compactMap { FuzzyMatcher.match(query, FuzzyMatcher.Candidate($0)) }
            .filter { $0.score >= (inMode ? 500 : 600) }
            .map(\.score).max()
        if let own { items.append(islandRow(score: inMode ? own : own - 80)) }
        return inMode ? ranked(items) : items
    }

    func activate(_ items: [LauncherItem], alternate: Bool) {
        switch items.first?.kind {
        case .pane(let pane)?:
            if let url = pane.url { NSWorkspace.shared.open(url) }
        case .islandSettings?:
            host.onOpenSettings?()
        default:
            break
        }
    }
}

// MARK: - Files

@MainActor
final class FilesPlugin: LauncherPlugin {
    unowned let host: LauncherModel
    init(host: LauncherModel) { self.host = host }

    let id = "files"
    let name = "파일 검색"
    let symbol = "doc.text.magnifyingglass"
    let keywords = ["files", "finder", "파일", "파일 검색"]
    let hasMode = true
    let placeholder = "홈 폴더의 파일과 폴더를 이름으로 찾습니다 · ⌘Return은 Finder에서 보기"
    var inRoot: Bool { host.config.searchFiles }

    private var found: (query: String, hits: [(FileHit, FuzzyMatch)]) = ("", [])

    func reset() { found = ("", []) }

    func search(_ query: String, inMode: Bool) -> [LauncherItem] {
        guard !query.isEmpty, !found.hits.isEmpty,
              query.lowercased().hasPrefix(found.query.lowercased()) else { return [] }
        var items: [LauncherItem] = []
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for (file, _) in found.hits {
            // Re-rank against what is typed now; drop what no longer matches.
            // Spotlight's own matches (diacritics, inside words) stay for the query they answered.
            var match = FuzzyMatcher.match(query, FuzzyMatcher.Candidate(file.name))
            if match == nil && query == found.query { match = FuzzyMatch(score: 100, hits: []) }
            guard let match else { continue }
            let folder = (file.path as NSString).deletingLastPathComponent.replacingOccurrences(of: home, with: "~")
            items.append(row(file.path, .file(file), title: file.name, subtitle: folder,
                             hits: match.hits, score: inMode ? match.score : match.score - 120))
        }
        return inMode ? ranked(items) : items
    }

    func fetch(_ query: String, inMode: Bool, isCurrent: @escaping @MainActor () -> Bool,
               done: @escaping @MainActor () -> Void) {
        let limit = inMode ? 40 : max(1, Int(host.config.maxFiles))
        DispatchQueue.global(qos: .userInitiated).async {
            let hits = FileSearch.find(query, limit: limit)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { [weak self] in
                    guard let self, isCurrent() else { return }
                    self.found = (query, hits)
                    done()
                }
            }
        }
    }

    func activate(_ items: [LauncherItem], alternate: Bool) {
        let urls = items.compactMap { item -> URL? in
            if case .file(let file) = item.kind { return URL(fileURLWithPath: file.path) }
            return nil
        }
        guard let first = urls.first else { return }
        if alternate { NSWorkspace.shared.activateFileViewerSelecting(urls) } else { NSWorkspace.shared.open(first) }
    }
}

// MARK: - Clipboard manager

/// Everything copied, newest first. Inside the mode Return pastes into the
/// app that had focus, ⌘Return only copies, and Tab, ⇧↑↓ or ⌘-click pick
/// several rows to paste at once.
@MainActor
final class ClipboardPlugin: LauncherPlugin {
    unowned let host: LauncherModel
    init(host: LauncherModel) { self.host = host }

    let id = "clipboard"
    let name = "클립보드 관리자"
    let symbol = "doc.on.clipboard"
    let keywords = ["clipboard", "clip", "history", "클립보드", "복사 기록", "선반"]
    let hasMode = true
    let multiSelect = true
    let placeholder = "복사 기록을 검색합니다"
    var inRoot: Bool { host.config.searchClipboard }

    static let hint = "Return 붙여넣기 · ⌘Return 복사 · Tab 여러 개 고르기 · ⌘⌫ 삭제"

    private func clipRow(_ item: ShelfItem, hits: [Int] = [], score: Int = 0, section: String? = nil) -> LauncherItem {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate(Calendar.current.isDateInToday(item.date) ? "HHmm" : "MMMdHHmm")
        let source = [item.sourceApp, f.string(from: item.date)].compactMap { $0 }.joined(separator: " · ")
        return row(item.id, .shelf(item), title: item.title, subtitle: source, hits: hits, score: score, section: section)
    }

    func search(_ query: String, inMode: Bool) -> [LauncherItem] {
        let history = host.shelfProvider?() ?? []
        if inMode {
            let section = history.isEmpty ? nil : Self.hint
            guard !query.isEmpty else { return history.map { clipRow($0, section: section) } }
            // Newest first, like the list without a query.
            return history.compactMap { item -> LauncherItem? in
                let fuzzy = FuzzyMatcher.match(query, FuzzyMatcher.Candidate(item.title))
                if let fuzzy, fuzzy.score >= 700 {
                    return clipRow(item, hits: fuzzy.hits, section: section)
                }
                guard item.searchText.localizedCaseInsensitiveContains(query) else { return nil }
                return clipRow(item, section: section)
            }
        }
        guard query.count >= 2 else { return [] }
        return history.compactMap { item -> LauncherItem? in
            if let m = FuzzyMatcher.match(query, FuzzyMatcher.Candidate(item.title)), m.score >= 400 {
                return clipRow(item, hits: m.hits, score: m.score - 150)
            }
            return item.searchText.localizedCaseInsensitiveContains(query) ? clipRow(item, score: 60) : nil
        }
    }

    private func shelfItems(_ items: [LauncherItem]) -> [ShelfItem] {
        items.compactMap { item -> ShelfItem? in
            if case .shelf(let shelfItem) = item.kind { return shelfItem }
            return nil
        }
    }

    func activate(_ items: [LauncherItem], alternate: Bool) {
        let picked = shelfItems(items)
        guard !picked.isEmpty else { return }
        if alternate { host.onCopyShelf?(picked) } else { host.onPasteShelf?(picked) }
    }

    func remove(_ item: LauncherItem) -> Bool {
        guard let shelfItem = shelfItems([item]).first else { return false }
        host.onRemoveShelf?(shelfItem)
        return true
    }

    func dragProvider(_ item: LauncherItem) -> NSItemProvider? {
        guard let shelfItem = shelfItems([item]).first else { return nil }
        return host.shelfDragProvider?(shelfItem)
    }
}

// MARK: - Web

@MainActor
final class WebPlugin: LauncherPlugin {
    unowned let host: LauncherModel
    init(host: LauncherModel) { self.host = host }

    let id = "web"
    let name = "웹 검색"
    let symbol = "globe"
    var inRoot: Bool { true }

    private var suggestions: (query: String, words: [String]) = ("", [])
    private var cache: [String: [String]] = [:]

    func reset() { suggestions = ("", []) }

    /// Google's completions for the query, or the ones for fewer letters
    /// that still begin with it, so the rows don't blink at every key.
    func completions(for query: String) -> [String] {
        let q = query.lowercased()
        guard !q.isEmpty, !suggestions.words.isEmpty, q.hasPrefix(suggestions.query.lowercased()) else { return [] }
        return suggestions.words.filter { $0.lowercased().hasPrefix(q) && $0.lowercased() != q }
    }

    func search(_ q: String, inMode: Bool) -> [LauncherItem] {
        guard !q.isEmpty else { return [] }
        let config = host.config
        var web: [LauncherItem] = []
        if let address = WebSearch.address(q) {
            web.append(row("address", .web(address, symbol: "safari"), title: address.absoluteString,
                           subtitle: "브라우저에서 열기", group: .web))
        }
        if config.webSearch, let url = WebSearch.googleURL(q) {
            web.append(row("google", .web(url, symbol: "magnifyingglass"), title: q,
                           subtitle: "Google에서 검색", group: .web))
            if config.suggestions {
                for word in completions(for: q).prefix(max(0, Int(config.maxSuggestions))) {
                    guard let url = WebSearch.googleURL(word) else { continue }
                    web.append(row("suggest:" + word, .web(url, symbol: "magnifyingglass"), title: word,
                                   subtitle: "Google 추천 검색어",
                                   hits: Array(min(q.count, word.count)..<word.count), group: .web))
                }
            }
        }
        if config.askClaude, let url = WebSearch.url("https://claude.ai/new", "q", q) {
            web.append(row("claude", .web(url, symbol: "sparkles"), title: q, subtitle: "Claude에게 묻기", group: .web))
        }
        if config.askGrok, let url = WebSearch.url("https://grok.com/", "q", q) {
            web.append(row("grok", .web(url, symbol: "bubble.left.and.text.bubble.right"), title: q,
                           subtitle: "Grok에게 묻기", group: .web))
        }
        if config.searchX, let url = WebSearch.url("https://x.com/search", "q", q) {
            web.append(row("x", .web(url, symbol: "number"), title: q, subtitle: "X에서 검색", group: .web))
        }
        return web
    }

    func fetch(_ q: String, inMode: Bool, isCurrent: @escaping @MainActor () -> Bool,
               done: @escaping @MainActor () -> Void) {
        let config = host.config
        guard config.webSearch && config.suggestions && WebSearch.eligible(q) else { return }
        if let cached = cache[q.lowercased()] {
            suggestions = (q, cached)
            done()
            return
        }
        WebSearch.suggestions(for: q) { [weak self] words in
            guard let self, let words else { return }
            self.cache[q.lowercased()] = words
            guard isCurrent() else { return }
            self.suggestions = (q, words)
            done()
        }
    }

    func activate(_ items: [LauncherItem], alternate: Bool) {
        guard case .web(let url, _) = items.first?.kind else { return }
        NSWorkspace.shared.open(url)
    }
}
