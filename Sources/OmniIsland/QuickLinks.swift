import AppKit

/// A saved link the launcher finds by name or keyword, like Raycast's Quick
/// Links. `link` is a web address, a URL with any scheme (obsidian://,
/// mailto:), or a file or folder path. `{query}` in it is replaced with what
/// is typed after the keyword or name ("gh owner/repo").
struct QuickLink: Equatable {
    var name = ""
    var link = ""
    /// Short trigger ("gh"). Typing it alone lists the link first; typing it,
    /// a space and some text fills in `{query}`.
    var keyword = ""
    /// App to open the link with: a name ("Safari"), a bundle id, or a path.
    /// Empty uses the default app.
    var app = ""

    static let placeholder = "{query}"

    static let examples = [
        QuickLink(name: "GitHub 저장소", link: "https://github.com/{query}", keyword: "gh"),
        QuickLink(name: "YouTube 검색", link: "https://www.youtube.com/results?search_query={query}", keyword: "yt"),
        QuickLink(name: "다운로드 폴더", link: "~/Downloads", keyword: "dl"),
    ]

    var isValid: Bool { !name.isEmpty && !link.isEmpty }

    /// The link asks for text: it has a `{query}` placeholder.
    var needsInput: Bool { link.range(of: Self.placeholder, options: .caseInsensitive) != nil }

    var isFile: Bool {
        let t = link.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("/") || t.hasPrefix("~") || t.lowercased().hasPrefix("file://")
    }

    /// Characters left as they are in a filled-in web address. "/" stays so
    /// "github.com/{query}" takes "owner/repo"; "&", "=", "?", "#" and "+"
    /// are escaped so the text can't break the query string.
    private static let allowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~/:@!$'()*,;")
        return set
    }()

    /// The address to open, with `{query}` replaced by `argument`.
    func url(argument: String? = nil) -> URL? {
        var template = link.trimmingCharacters(in: .whitespaces)
        guard !template.isEmpty else { return nil }
        let arg = (argument ?? "").trimmingCharacters(in: .whitespaces)
        if arg.isEmpty && needsInput { template = Self.withoutQuery(template) }
        if isFile {
            let text = Self.fill(template, with: arg)
            if text.lowercased().hasPrefix("file://") { return URL(string: text) }
            return URL(fileURLWithPath: (text as NSString).expandingTildeInPath)
        }
        let encoded = arg.addingPercentEncoding(withAllowedCharacters: Self.allowed) ?? arg
        var text = Self.fill(template, with: encoded)
        if !Self.hasScheme(text) {
            text = (text.lowercased().hasPrefix("localhost") || text.hasPrefix("127.") ? "http://" : "https://") + text
        }
        return URL(string: text)
    }

    /// What to open when a `{query}` link gets no text: the part before the
    /// placeholder ("https://github.com/{query}" → https://github.com/), or
    /// the site itself when the placeholder is in the query string
    /// ("youtube.com/results?search_query={query}" → youtube.com).
    static func withoutQuery(_ template: String) -> String {
        guard let r = template.range(of: placeholder, options: .caseInsensitive) else { return template }
        let before = template[..<r.lowerBound]
        guard let mark = before.firstIndex(where: { $0 == "?" || $0 == "#" }) else { return String(before) }
        let path = before[..<mark]
        // Keep the scheme and host, drop the path.
        if let scheme = path.range(of: "://") {
            let rest = path[scheme.upperBound...]
            let host = rest.firstIndex(of: "/").map { rest[..<$0] } ?? rest
            return String(path[..<scheme.upperBound]) + host + "/"
        }
        return String(path.split(separator: "/").first ?? Substring(path))
    }

    /// Text split into words and joined with single spaces ("gh  bb " → "gh bb"),
    /// and whether it ended with a space.
    static func words(_ text: String) -> (text: String, trailingSpace: Bool) {
        let parts = text.split(whereSeparator: \.isWhitespace)
        return (parts.joined(separator: " "), !parts.isEmpty && (text.last?.isWhitespace ?? false))
    }

    private static func fill(_ template: String, with value: String) -> String {
        template.replacingOccurrences(of: placeholder, with: value, options: .caseInsensitive)
    }

    /// "https://…", "obsidian://…", "mailto:…" have one; "github.com/x" and
    /// "localhost:3000" don't.
    private static func hasScheme(_ text: String) -> Bool {
        if text.contains("://") { return true }
        guard let colon = text.firstIndex(of: ":") else { return false }
        let scheme = text[..<colon]
        guard let first = scheme.first, first.isLetter,
              scheme.allSatisfy({ $0.isLetter || $0.isNumber || "+-.".contains($0) }),
              !scheme.contains(".") else { return false }
        let rest = text[text.index(after: colon)...]
        return !(rest.first?.isNumber ?? false)
    }

    /// The app chosen in `app`, if it can be found.
    var appURL: URL? {
        let t = app.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let fm = FileManager.default
        if t.hasPrefix("/") || t.hasPrefix("~") {
            let path = (t as NSString).expandingTildeInPath
            return fm.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        if t.contains("."), !t.lowercased().hasSuffix(".app"),
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: t) {
            return url
        }
        let file = t.lowercased().hasSuffix(".app") ? t : t + ".app"
        let home = fm.homeDirectoryForCurrentUser.path
        for folder in ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                       "/Applications/Utilities", home + "/Applications"] {
            let path = folder + "/" + file
            if fm.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
        }
        return nil
    }

    /// The app that will open the link, for its icon.
    var handlerPath: String? {
        if let appURL { return appURL.path }
        if isFile, let url = url(argument: needsInput ? "" : nil), url.isFileURL {
            let path = url.path
            return FileManager.default.fileExists(atPath: path) ? path : nil
        }
        guard let url = url(argument: "x") else { return nil }
        return NSWorkspace.shared.urlForApplication(toOpen: url)?.path
    }

    func open(argument: String? = nil) {
        guard let url = url(argument: argument) else { return }
        if let appURL {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Plugin

/// Quick Links in the launcher. A link is found by its name or keyword.
/// Keywords can have several words ("gh bb stg"), so typing "gh " lists
/// every link under gh, like folders. "gh owner/repo" fills `{query}` of the
/// link whose keyword is "gh"; Return on it with nothing typed opens the
/// address without the placeholder. Tab completes the next word.
@MainActor
final class QuickLinksPlugin: LauncherPlugin {
    unowned let host: LauncherModel
    init(host: LauncherModel) { self.host = host }

    let id = "quicklinks"
    let name = "Quick Links"
    let symbol = "link"
    let keywords = ["quicklinks", "quick links", "links", "bookmarks", "링크", "바로가기", "북마크"]
    let hasMode = true
    let placeholder = "저장한 링크를 이름이나 키워드로 찾습니다 · Tab 키워드 완성 · ⌘Return 주소 복사"
    var inRoot: Bool { host.config.searchQuickLinks }

    /// Hint rows (keywords that go on from what is typed) at most.
    private static let maxHints = 6

    private var links: [QuickLink] { host.config.quickLinks.filter(\.isValid) }

    /// What to type before the text a link asks for: its keyword, or its name.
    static func trigger(of link: QuickLink) -> String {
        let keyword = QuickLink.words(link.keyword).text
        return keyword.isEmpty ? link.name : keyword
    }

    /// What Tab puts in the field on a link's row: the keyword up to the end
    /// of its next word ("g" → "gh ", "gh " → "gh bb "), and a space after
    /// the whole keyword of a link that asks for text. Nil when there is
    /// nothing more to complete.
    static func completion(for link: QuickLink, typed raw: String) -> String? {
        let keyword = QuickLink.words(link.keyword).text
        let trigger = keyword.isEmpty ? (link.needsInput ? link.name : "") : keyword
        guard !trigger.isEmpty else { return nil }
        let typed = QuickLink.words(raw)
        let key = (typed.trailingSpace ? typed.text + " " : typed.text).lowercased()
        let lower = trigger.lowercased()
        if lower == key { return link.needsInput ? trigger + " " : nil }
        guard lower.hasPrefix(key), trigger.count > key.count else { return nil }
        let rest = trigger.dropFirst(key.count)
        if let space = rest.firstIndex(of: " ") { return String(trigger[..<space]) + " " }
        return trigger + (link.needsInput ? " " : "")
    }

    /// The keyword word that ends `path` as written in the link (for the
    /// pill), when `path` is a level with links under it or a `{query}`
    /// link ("gh" for "gh bb stg" or "gh {query}"). Nil otherwise.
    func levelWord(path: [String]) -> String? {
        guard !path.isEmpty else { return nil }
        let lower = path.map { $0.lowercased() }
        for link in links {
            let words = QuickLink.words(link.keyword).text.split(separator: " ").map(String.init)
            guard words.count >= lower.count,
                  zip(words, lower).allSatisfy({ $0.lowercased() == $1 }) else { continue }
            if words.count > lower.count || link.needsInput { return words[lower.count - 1] }
        }
        return nil
    }

    private func key(_ index: Int, _ link: QuickLink) -> String { "\(index):\(link.name)" }

    private func subtitle(_ link: QuickLink, argument: String?) -> String {
        if link.needsInput && (argument ?? "").isEmpty {
            let base = link.url(argument: nil).map(Self.display) ?? link.link
            return argument == nil
                ? "\(Self.trigger(of: link)) 다음에 스페이스를 누르고 입력합니다 · Return은 \(base) 열기"
                : "열 내용을 입력합니다 · Return은 \(base) 열기"
        }
        return link.url(argument: argument).map(Self.display) ?? link.link
    }

    private static func display(_ url: URL) -> String {
        url.isFileURL ? (url.path as NSString).abbreviatingWithTildeInPath : url.absoluteString
    }

    private func linkRow(_ index: Int, _ link: QuickLink, argument: String? = nil, hits: [Int] = [],
                         badgeHits: Int = 0, score: Int = 0, group: LauncherItem.Group = .local) -> LauncherItem {
        let filled = argument.map { !$0.isEmpty } ?? false
        var item = row(key(index, link) + (filled ? ":arg" : ""), .quickLink(link, argument: argument),
                       title: filled ? "\(link.name): \(argument ?? "")" : link.name,
                       subtitle: subtitle(link, argument: argument),
                       hits: hits, score: score, group: group)
        let keyword = QuickLink.words(link.keyword).text
        if !keyword.isEmpty {
            item.badge = keyword
            item.badgeHits = min(badgeHits, keyword.count)
        }
        return item
    }

    func search(_ query: String, inMode: Bool) -> [LauncherItem] {
        let saved = links
        guard !saved.isEmpty else { return [] }
        let inPills = !host.linkPath.isEmpty
        if query.isEmpty && !inPills {
            guard inMode else { return [] }
            return saved.enumerated().map { i, link in linkRow(i, link) }
        }

        // The field as typed, so "gh " with its space already counts.
        let typed = QuickLink.words(host.linkTyped)
        let typedLower = typed.text.lowercased()
        let typedKey = typed.trailingSpace ? typedLower + " " : typedLower

        var answers: [LauncherItem] = []
        var hints: [LauncherItem] = []
        var used = Set<Int>()
        for (i, link) in saved.enumerated() {
            let keyword = QuickLink.words(link.keyword).text.lowercased()
            // "gh owner/repo": the text after a keyword (or a name) fills {query}.
            if link.needsInput,
               let t = [keyword, link.name.lowercased()].first(where: { !$0.isEmpty && typedKey.hasPrefix($0 + " ") }) {
                let argument = String(typed.text.dropFirst(t.count)).trimmingCharacters(in: .whitespaces)
                // With nothing typed yet it leads; with text, links further
                // down the keyword ("gh bb stg" for "gh b") go first.
                answers.append(linkRow(i, link, argument: argument, badgeHits: keyword.count,
                                       score: argument.isEmpty ? 9_500 : 7_000, group: .answer))
                used.insert(i)
                continue
            }
            guard !keyword.isEmpty else { continue }
            if keyword == typedLower && !typed.trailingSpace {
                answers.append(linkRow(i, link, badgeHits: keyword.count, score: 10_000, group: .answer))
                used.insert(i)
            } else if inPills && host.query.isEmpty && keyword == typedLower {
                // The pill's own link ("gh" itself), under the links below it.
                answers.append(linkRow(i, link, badgeHits: keyword.count, score: 6_000, group: .answer))
                used.insert(i)
            } else if keyword.hasPrefix(typedKey) {
                // A hint: the keyword goes on from what is typed ("g" → gh, "gh " → gh bb stg).
                hints.append(linkRow(i, link, badgeHits: typedKey.count,
                                     score: 8_000 - min(keyword.count - typedKey.count, 900), group: .answer))
                used.insert(i)
            }
        }
        let byScore: (LauncherItem, LauncherItem) -> Bool = { a, b in
            a.score != b.score ? a.score > b.score : a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
        hints.sort(by: byScore)
        if inPills { return (answers + hints).sorted(by: byScore) }
        var rows = (answers + hints.prefix(Self.maxHints)).sorted(by: byScore)
        if inMode { rows += hints.dropFirst(Self.maxHints) }

        // The rest by name.
        var items: [LauncherItem] = []
        for (i, link) in saved.enumerated() where !used.contains(i) {
            guard let match = FuzzyMatcher.match(query, FuzzyMatcher.Candidate(link.name)),
                  match.score >= (inMode ? 0 : 300) else { continue }
            items.append(linkRow(i, link, hits: match.hits, score: inMode ? match.score : match.score - 30))
        }
        rows += inMode ? ranked(items) : items
        return rows
    }

    func activate(_ items: [LauncherItem], alternate: Bool) {
        guard case .quickLink(let link, let argument)? = items.first?.kind else { return }
        if alternate {
            guard let url = link.url(argument: argument) else { return }
            let board = NSPasteboard.general
            board.clearContents()
            board.setString(url.isFileURL ? url.path : url.absoluteString, forType: .string)
        } else {
            link.open(argument: argument)
        }
    }
}
