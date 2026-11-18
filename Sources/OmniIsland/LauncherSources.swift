import AppKit

// Sources the launcher asks besides apps and windows, after nanolight's
// settings_panes.zig, files.zig, suggest.zig and currency.zig.

// MARK: - System Settings panes

struct SettingsPane: Equatable {
    let name: String
    let koreanName: String
    /// The settings extension's bundle id; opened as x-apple.systempreferences:<id>.
    let id: String
    /// Bundle name without ".appex", to check that this Mac has the pane.
    let appex: String
    let keywords: [String]

    var url: URL? { URL(string: "x-apple.systempreferences:" + id) }

    /// The name in the language macOS uses.
    var displayName: String { SettingsPanes.prefersKorean ? koreanName : name }
}

enum SettingsPanes {
    static let prefersKorean = Locale.preferredLanguages.first?.hasPrefix("ko") ?? false

    static let all: [SettingsPane] = [
        .init(name: "Wi-Fi", koreanName: "Wi-Fi", id: "com.apple.wifi-settings-extension", appex: "Wi-Fi", keywords: ["wifi", "wireless", "와이파이", "무선"]),
        .init(name: "Bluetooth", koreanName: "Bluetooth", id: "com.apple.BluetoothSettings", appex: "Bluetooth", keywords: ["블루투스"]),
        .init(name: "Network", koreanName: "네트워크", id: "com.apple.Network-Settings.extension", appex: "Network", keywords: ["ethernet", "internet", "firewall", "proxy", "dns", "인터넷", "방화벽", "프록시"]),
        .init(name: "VPN", koreanName: "VPN", id: "com.apple.NetworkExtensionSettingsUI.NESettingsUIExtension", appex: "VPN", keywords: []),
        .init(name: "Notifications", koreanName: "알림", id: "com.apple.Notifications-Settings.extension", appex: "NotificationsSettings", keywords: ["alerts", "banners", "배너"]),
        .init(name: "Sound", koreanName: "사운드", id: "com.apple.Sound-Settings.extension", appex: "Sound", keywords: ["volume", "audio", "speakers", "microphone", "output", "input", "소리", "볼륨", "스피커", "마이크"]),
        .init(name: "Focus", koreanName: "집중 모드", id: "com.apple.Focus-Settings.extension", appex: "FocusSettingsExtension", keywords: ["do not disturb", "dnd", "방해 금지"]),
        .init(name: "Screen Time", koreanName: "스크린 타임", id: "com.apple.Screen-Time-Settings.extension", appex: "ScreenTimePreferencesExtension", keywords: ["parental controls", "app limits", "자녀 보호"]),
        .init(name: "General", koreanName: "일반", id: "com.apple.systempreferences.GeneralSettings", appex: "GeneralSettings", keywords: []),
        .init(name: "About", koreanName: "정보", id: "com.apple.SystemProfiler.AboutExtension", appex: "AboutExtension", keywords: ["about this mac", "serial number", "macos version", "이 mac에 관하여", "일련번호"]),
        .init(name: "Software Update", koreanName: "소프트웨어 업데이트", id: "com.apple.Software-Update-Settings.extension", appex: "SoftwareUpdateSettingsExtension", keywords: ["update macos", "upgrade", "업데이트"]),
        .init(name: "Storage", koreanName: "저장 공간", id: "com.apple.settings.Storage", appex: "Storage", keywords: ["disk space", "free space", "용량", "디스크"]),
        .init(name: "AirDrop & Handoff", koreanName: "AirDrop 및 Handoff", id: "com.apple.AirDrop-Handoff-Settings.extension", appex: "AirDropHandoffExtension", keywords: ["airplay receiver", "continuity", "에어드롭"]),
        .init(name: "Login Items & Extensions", koreanName: "로그인 항목 및 확장 프로그램", id: "com.apple.LoginItems-Settings.extension", appex: "LoginItems", keywords: ["open at login", "startup items", "background items", "extensions", "로그인 항목", "시동 항목"]),
        .init(name: "Language & Region", koreanName: "언어 및 지역", id: "com.apple.Localization-Settings.extension", appex: "Localization", keywords: ["language", "region", "locale", "date format", "언어", "지역"]),
        .init(name: "Date & Time", koreanName: "날짜 및 시간", id: "com.apple.Date-Time-Settings.extension", appex: "DateAndTime Extension", keywords: ["clock", "time zone", "시계", "시간대"]),
        .init(name: "Sharing", koreanName: "공유", id: "com.apple.Sharing-Settings.extension", appex: "Sharing", keywords: ["file sharing", "screen sharing", "remote login", "ssh", "computer name", "화면 공유", "파일 공유", "컴퓨터 이름"]),
        .init(name: "Time Machine", koreanName: "Time Machine", id: "com.apple.Time-Machine-Settings.extension", appex: "TimeMachineSettings", keywords: ["backup", "백업", "타임머신"]),
        .init(name: "Transfer or Reset", koreanName: "전송 또는 재설정", id: "com.apple.Transfer-Reset-Settings.extension", appex: "TransferResetExtension", keywords: ["erase all content", "factory reset", "초기화"]),
        .init(name: "Startup Disk", koreanName: "시동 디스크", id: "com.apple.Startup-Disk-Settings.extension", appex: "StartupDisk", keywords: []),
        .init(name: "Device Management", koreanName: "기기 관리", id: "com.apple.Profiles-Settings.extension", appex: "ProfilesSettingsExt", keywords: ["profiles", "mdm", "프로파일"]),
        .init(name: "Appearance", koreanName: "화면 모드", id: "com.apple.Appearance-Settings.extension", appex: "Appearance", keywords: ["dark mode", "light mode", "accent color", "theme", "다크 모드", "라이트 모드", "강조 색상", "테마", "모양"]),
        .init(name: "Accessibility", koreanName: "손쉬운 사용", id: "com.apple.Accessibility-Settings.extension", appex: "AccessibilitySettingsExtension", keywords: ["voiceover", "zoom", "reduce motion", "동작 줄이기", "확대"]),
        .init(name: "Control Center", koreanName: "제어 센터", id: "com.apple.ControlCenter-Settings.extension", appex: "ControlCenterSettings", keywords: ["menu bar", "메뉴 막대"]),
        .init(name: "Siri", koreanName: "Siri", id: "com.apple.Siri-Settings.extension", appex: "SiriPreferenceExtension", keywords: ["apple intelligence", "dictation", "받아쓰기", "시리"]),
        .init(name: "Spotlight", koreanName: "Spotlight", id: "com.apple.Spotlight-Settings.extension", appex: "SpotlightPreferenceExtension", keywords: ["스포트라이트"]),
        .init(name: "Privacy & Security", koreanName: "개인정보 보호 및 보안", id: "com.apple.settings.PrivacySecurity.extension", appex: "SecurityPrivacyExtension", keywords: ["permissions", "full disk access", "accessibility access", "location services", "camera access", "filevault", "gatekeeper", "권한", "전체 디스크 접근", "위치 서비스", "보안"]),
        .init(name: "Desktop & Dock", koreanName: "데스크탑 및 Dock", id: "com.apple.Desktop-Settings.extension", appex: "DesktopSettings", keywords: ["dock", "mission control", "hot corners", "stage manager", "widgets", "독", "핫 코너", "스테이지 매니저", "위젯"]),
        .init(name: "Displays", koreanName: "디스플레이", id: "com.apple.Displays-Settings.extension", appex: "DisplaysExt", keywords: ["monitor", "resolution", "brightness", "night shift", "모니터", "해상도", "밝기"]),
        .init(name: "Wallpaper", koreanName: "배경화면", id: "com.apple.Wallpaper-Settings.extension", appex: "Wallpaper", keywords: ["background", "desktop picture", "배경"]),
        .init(name: "Battery", koreanName: "배터리", id: "com.apple.Battery-Settings.extension", appex: "PowerPreferences", keywords: ["energy", "power", "low power mode", "저전력", "전원"]),
        .init(name: "Lock Screen", koreanName: "잠금 화면", id: "com.apple.Lock-Screen-Settings.extension", appex: "LockScreen", keywords: ["screen saver", "require password", "화면 보호기"]),
        .init(name: "Touch ID & Password", koreanName: "Touch ID 및 암호", id: "com.apple.Touch-ID-Settings.extension", appex: "Touch ID & Password", keywords: ["fingerprint", "password", "지문", "암호", "비밀번호"]),
        .init(name: "Users & Groups", koreanName: "사용자 및 그룹", id: "com.apple.Users-Groups-Settings.extension", appex: "UsersGroups", keywords: ["accounts", "users", "guest user", "계정", "사용자"]),
        .init(name: "Internet Accounts", koreanName: "인터넷 계정", id: "com.apple.Internet-Accounts-Settings.extension", appex: "InternetAccountsSettingsExtension", keywords: ["mail accounts", "email accounts", "메일 계정"]),
        .init(name: "Game Center", koreanName: "Game Center", id: "com.apple.Game-Center-Settings.extension", appex: "GameCenterMacOSSettingsExtension", keywords: []),
        .init(name: "Game Controllers", koreanName: "게임 컨트롤러", id: "com.apple.Game-Controller-Settings.extension", appex: "GameControllerMacSettings", keywords: ["gamepad", "게임패드"]),
        .init(name: "Wallet & Apple Pay", koreanName: "지갑 및 Apple Pay", id: "com.apple.WalletSettingsExtension", appex: "WalletSettingsExtension", keywords: ["월렛"]),
        .init(name: "Keyboard", koreanName: "키보드", id: "com.apple.Keyboard-Settings.extension", appex: "KeyboardSettings", keywords: ["keyboard shortcuts", "input sources", "key repeat", "단축키", "입력 소스", "키 반복"]),
        .init(name: "Mouse", koreanName: "마우스", id: "com.apple.Mouse-Settings.extension", appex: "MouseExtension", keywords: ["pointer speed", "natural scrolling", "스크롤"]),
        .init(name: "Trackpad", koreanName: "트랙패드", id: "com.apple.Trackpad-Settings.extension", appex: "TrackpadExtension", keywords: ["gestures", "tap to click", "natural scrolling", "제스처", "탭하여 클릭"]),
        .init(name: "Printers & Scanners", koreanName: "프린터 및 스캐너", id: "com.apple.Print-Scan-Settings.extension", appex: "PrinterScannerSettings", keywords: ["printer", "프린터", "스캐너"]),
        .init(name: "Apple Account", koreanName: "Apple 계정", id: "com.apple.systempreferences.AppleIDSettings", appex: "AppleIDSettings", keywords: ["apple id", "icloud", "아이클라우드"]),
        .init(name: "Family", koreanName: "가족", id: "com.apple.Family-Settings.extension", appex: "FamilySettings", keywords: ["family sharing", "가족 공유"]),
    ]

    private struct Prepared {
        let pane: SettingsPane
        let names: [FuzzyMatcher.Candidate]
        let keywords: [FuzzyMatcher.Candidate]
    }

    /// Panes this Mac has, looked up once.
    private static let prepared: [Prepared] = {
        let dirs = ["/System/Library/ExtensionKit/Extensions", "/System/Applications/System Settings.app/Contents/PlugIns"]
        let fm = FileManager.default
        return all.filter { pane in
            dirs.contains { fm.fileExists(atPath: "\($0)/\(pane.appex).appex") }
        }.map { pane in
            Prepared(pane: pane,
                     names: [FuzzyMatcher.Candidate(pane.displayName),
                             FuzzyMatcher.Candidate(prefersKorean ? pane.name : pane.koreanName)],
                     keywords: pane.keywords.map(FuzzyMatcher.Candidate.init))
        }
    }()

    /// Below this a match is letters in order or a typo: too loose for a
    /// pane, which would list under nearly every query.
    private static let minScore = 500

    /// Panes this Mac has, in the order of the list above.
    static var available: [SettingsPane] { prepared.map(\.pane) }

    static func search(_ query: String, minLength: Int = 2) -> [(SettingsPane, FuzzyMatch)] {
        var q = query.trimmingCharacters(in: .whitespaces)
        for tail in [" settings", " preferences", " 설정"] where q.lowercased().hasSuffix(tail) && q.count > tail.count {
            q = String(q.dropLast(tail.count)).trimmingCharacters(in: .whitespaces)
        }
        guard q.count >= minLength else { return [] }
        var result: [(SettingsPane, FuzzyMatch)] = []
        for p in prepared {
            var best: FuzzyMatch?
            for (i, name) in p.names.enumerated() {
                guard let m = FuzzyMatcher.match(q, name), m.score >= minScore else { continue }
                // Only the shown name lights its letters.
                let shown = i == 0 ? m : FuzzyMatch(score: m.score - 20, hits: [])
                if shown.score > (best?.score ?? -1) { best = shown }
            }
            for keyword in p.keywords {
                guard let m = FuzzyMatcher.match(q, keyword), m.score >= minScore else { continue }
                if m.score - 40 > (best?.score ?? -1) { best = FuzzyMatch(score: m.score - 40, hits: []) }
            }
            if let best { result.append((p.pane, best)) }
        }
        return result
    }

    static let appPath = "/System/Applications/System Settings.app"
}

// MARK: - Files

struct FileHit: Equatable {
    let path: String
    let isDirectory: Bool
    var name: String { (path as NSString).lastPathComponent }
}

enum FileSearch {
    /// Asks Spotlight for files whose names contain `query`, under the home
    /// folder, and keeps the best `limit` by the launcher's own ranking.
    /// Runs off the main thread; gives up after about a second and a half.
    static func find(_ query: String, limit: Int) -> [(FileHit, FuzzyMatch)] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2, !q.contains("\0") else { return [] }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["-onlyin", home, "-name", q]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
            if process.isRunning { process.terminate() }
        }

        var data = Data()
        var lines = 0
        let handle = pipe.fileHandleForReading
        while lines < 400, let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            data.append(chunk)
            lines += chunk.reduce(0) { $0 + ($1 == 10 ? 1 : 0) }
        }
        if process.isRunning { process.terminate() }

        let text = String(decoding: data, as: UTF8.self)
        let fm = FileManager.default
        var scored: [(FileHit, FuzzyMatch)] = []
        for path in text.split(separator: "\n").prefix(400).map(String.init) where !excluded(path, home: home) {
            let name = (path as NSString).lastPathComponent
            // Spotlight also folds diacritics and matches inside words; those rank last.
            let match = FuzzyMatcher.match(q, FuzzyMatcher.Candidate(name)) ?? FuzzyMatch(score: 100, hits: [])
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir) else { continue }
            scored.append((FileHit(path: path, isDirectory: isDir.boolValue), match))
        }
        scored.sort { a, b in
            a.1.score != b.1.score ? a.1.score > b.1.score : a.0.path.count < b.0.path.count
        }
        return Array(scored.prefix(limit))
    }

    private static func excluded(_ path: String, home: String) -> Bool {
        if path.hasPrefix(home + "/Library/") { return true }
        if path.contains("/.") || path.contains("/node_modules/") { return true }
        // Files inside bundles, and apps (listed as apps already).
        if path.contains(".app/") || path.hasSuffix(".app") { return true }
        return false
    }
}

// MARK: - Web

enum WebSearch {
    /// Whether `text` may be sent to Google for completions: nothing that
    /// reads as an address (a dot, a slash, a colon, an @) goes out.
    static func eligible(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2, t.count <= 120 else { return false }
        if t.lowercased().hasPrefix("www") || t.lowercased().hasPrefix("localhost") { return false }
        return !t.contains { ":@\\/.".contains($0) || $0.isNewline }
    }

    static func googleURL(_ text: String) -> URL? {
        url("https://www.google.com/search", "q", text)
    }

    static func url(_ base: String, _ key: String, _ text: String) -> URL? {
        var components = URLComponents(string: base)
        components?.queryItems = [URLQueryItem(name: key, value: text)]
        return components?.url
    }

    /// The text as a web address, when it looks like one ("github.com/x").
    static func address(_ text: String) -> URL? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.contains(" "), t.contains("."), t.count >= 4 else { return nil }
        if t.hasPrefix("http://") || t.hasPrefix("https://") { return URL(string: t) }
        let host = t.split(separator: "/").first.map(String.init) ?? t
        guard let tld = host.split(separator: ".").last, tld.count >= 2, tld.allSatisfy(\.isLetter) else { return nil }
        return URL(string: "https://" + t)
    }

    /// Google's completions (the endpoint Firefox uses); nil on failure.
    @MainActor static func suggestions(for text: String, completion: @escaping @MainActor ([String]?) -> Void) {
        guard eligible(text),
              var components = URLComponents(string: "https://suggestqueries.google.com/complete/search") else {
            completion(nil)
            return
        }
        components.queryItems = [
            URLQueryItem(name: "client", value: "firefox"),
            URLQueryItem(name: "ie", value: "utf-8"),
            URLQueryItem(name: "oe", value: "utf-8"),
            URLQueryItem(name: "q", value: text),
        ]
        guard let url = components.url else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.httpShouldHandleCookies = false
        URLSession.shared.dataTask(with: request) { data, _, _ in
            var list: [String]?
            if let data, data.count < 32 * 1024,
               let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
               array.count >= 2, let words = array[1] as? [String] {
                list = words.filter { $0.count <= 120 }
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(list) }
            }
        }.resume()
    }
}

// MARK: - Currency

struct CurrencyQuery: Equatable, Hashable {
    let amount: Double
    let from: String
    let to: String
}

struct CurrencyAnswer: Equatable {
    let query: CurrencyQuery
    let value: Double
    let date: String
}

enum Currency {
    /// ISO codes Frankfurter publishes (ECB daily rates).
    static let codes: Set<String> = [
        "AUD", "BRL", "CAD", "CHF", "CNY", "CZK", "DKK", "EUR", "GBP", "HKD",
        "HUF", "IDR", "ILS", "INR", "ISK", "JPY", "KRW", "MXN", "MYR", "NOK",
        "NZD", "PHP", "PLN", "RON", "SEK", "SGD", "THB", "TRY", "USD", "ZAR",
    ]

    /// Korean and symbol names for the common ones.
    static let aliases: [String: String] = [
        "달러": "USD", "불": "USD", "$": "USD", "원": "KRW", "₩": "KRW", "엔": "JPY", "¥": "JPY",
        "유로": "EUR", "€": "EUR", "파운드": "GBP", "£": "GBP", "위안": "CNY", "프랑": "CHF",
    ]

    /// "100 USD to EUR", "100usd in sgd", "50 EUR GBP", "100달러", "100 달러 엔".
    /// A single currency converts to KRW (or to USD when it is KRW).
    static func parse(_ text: String) -> CurrencyQuery? {
        var s = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
        guard s.count >= 3 else { return nil }
        // Leading amount.
        var digits = ""
        while let c = s.first, c.isNumber || c == "." {
            digits.append(c)
            s.removeFirst()
        }
        guard !digits.isEmpty, let amount = Double(digits), amount.isFinite else { return nil }
        let words = s.lowercased()
            .split(whereSeparator: { $0 == " " })
            .map(String.init)
            .filter { !["to", "in", "as", "into", "→", "->", "="].contains($0) }
        func code(_ w: String) -> String? {
            let upper = w.uppercased()
            if codes.contains(upper) { return upper }
            if let alias = aliases[w] { return alias }
            // "달러로", "엔으로", "원에"
            for suffix in ["으로", "로", "에"] where w.hasSuffix(suffix) {
                if let alias = aliases[String(w.dropLast(suffix.count))] { return alias }
            }
            return nil
        }
        let found = words.compactMap(code)
        guard found.count == words.count, (1...2).contains(found.count) else { return nil }
        let from = found[0]
        let to = found.count == 2 ? found[1] : (from == "KRW" ? "USD" : "KRW")
        guard from != to else { return nil }
        return CurrencyQuery(amount: amount, from: from, to: to)
    }

    @MainActor static func fetch(_ q: CurrencyQuery, completion: @escaping @MainActor (CurrencyAnswer?) -> Void) {
        var components = URLComponents(string: "https://api.frankfurter.dev/v1/latest")
        components?.queryItems = [
            URLQueryItem(name: "amount", value: Calculator.plain(q.amount)),
            URLQueryItem(name: "from", value: q.from),
            URLQueryItem(name: "to", value: q.to),
        ]
        guard let url = components?.url else {
            completion(nil)
            return
        }
        URLSession.shared.dataTask(with: URLRequest(url: url, timeoutInterval: 4)) { data, _, _ in
            var answer: CurrencyAnswer?
            if let data, data.count < 8 * 1024,
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let rates = object["rates"] as? [String: Any],
               let value = (rates[q.to] as? NSNumber)?.doubleValue {
                answer = CurrencyAnswer(query: q, value: value, date: object["date"] as? String ?? "")
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(answer) }
            }
        }.resume()
    }
}
