import Foundation

/// How well a query matches a name, and which characters matched (drawn
/// brighter in the result row). Case-insensitive.
///
/// Tiers, best first (after nanolight's search.zig): the whole name, its
/// start, a word's start, the words' initials ("vsc" for Visual Studio
/// Code), anywhere inside it, the letters in order (worse the more they
/// spread), and last a typo near the start ("chorme" for Chrome).
/// Hangul initial consonants match too: "ㄱㅅㄱ" finds 계산기.
struct FuzzyMatch: Equatable {
    var score: Int
    /// Character offsets of the name that matched.
    var hits: [Int]
}

enum FuzzyMatcher {
    /// A name prepared once for repeated matching.
    struct Candidate {
        let text: String
        fileprivate let chars: [Character]
        fileprivate let lower: [Character]
        fileprivate let wordStarts: [Int]
        /// Initial consonant of each Hangul syllable (other characters kept).
        fileprivate let choseong: [Character]

        init(_ text: String) {
            let normalized = text.precomposedStringWithCanonicalMapping
            self.text = normalized
            chars = Array(normalized)
            lower = chars.map { Character($0.lowercased().first.map(String.init) ?? String($0)) }
            var starts: [Int] = []
            for i in chars.indices where FuzzyMatcher.isWordStart(chars, i) { starts.append(i) }
            wordStarts = starts
            choseong = chars.map(FuzzyMatcher.choseong)
        }
    }

    static func match(_ query: String, _ candidate: Candidate) -> FuzzyMatch? {
        let q = Array(query.precomposedStringWithCanonicalMapping.lowercased()
            .trimmingCharacters(in: .whitespaces))
        guard !q.isEmpty, !candidate.lower.isEmpty else { return nil }
        let name = candidate.lower
        let slack = min(max(name.count - q.count, 0), 60)

        if q == name { return FuzzyMatch(score: 1000, hits: Array(name.indices)) }
        if name.starts(with: q) { return FuzzyMatch(score: 900 - slack, hits: Array(0..<q.count)) }

        // A later word starts with the query.
        for start in candidate.wordStarts where start > 0 {
            if Array(name[start...]).starts(with: q) {
                return FuzzyMatch(score: 800 - min(start, 40) - slack / 4, hits: Array(start..<start + q.count))
            }
        }

        // Initials: "vsc" → Visual Studio Code.
        if q.count >= 2, q.count <= candidate.wordStarts.count {
            let initials = candidate.wordStarts.map { name[$0] }
            if Array(initials.prefix(q.count)) == q {
                return FuzzyMatch(score: 720 - slack / 4, hits: Array(candidate.wordStarts.prefix(q.count)))
            }
        }

        // Hangul initial consonants: "ㄱㅅ" → 계산기.
        if q.allSatisfy(isCompatibilityConsonant) {
            let cho = candidate.choseong
            if cho.starts(with: q) { return FuzzyMatch(score: 760 - slack, hits: Array(0..<q.count)) }
            if let at = firstIndex(of: q, in: cho) {
                return FuzzyMatch(score: 560 - min(at, 40), hits: Array(at..<at + q.count))
            }
        }

        if let at = firstIndex(of: q, in: name) {
            return FuzzyMatch(score: 600 - min(at, 40) - slack / 4, hits: Array(at..<at + q.count))
        }

        if let sub = subsequence(q, in: name) {
            let spread = (sub.last ?? 0) - (sub.first ?? 0) - (q.count - 1)
            let score = 420 - min(spread * 6, 200) - min(sub.first ?? 0, 40)
            return FuzzyMatch(score: max(score, 150), hits: sub)
        }

        // Typos: the start of the name (or of a word) is one edit away.
        if q.count >= 4 {
            for start in [0] + candidate.wordStarts where start < name.count {
                let rest = Array(name[start...])
                for length in [q.count - 1, q.count, q.count + 1] where length > 0 && length <= rest.count {
                    if editDistance(q, Array(rest.prefix(length)), limit: 1) <= 1 {
                        return FuzzyMatch(score: 200 - min(start, 40), hits: [])
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Helpers

    fileprivate static func isWordStart(_ chars: [Character], _ i: Int) -> Bool {
        if i == 0 { return true }
        let prev = chars[i - 1], ch = chars[i]
        if ch == " " { return false }
        if " -_./(".contains(prev) { return true }
        return ch.isUppercase && prev.isLowercase
    }

    private static let choseongTable: [Character] = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")

    fileprivate static func choseong(_ ch: Character) -> Character {
        guard let scalar = ch.unicodeScalars.first, ch.unicodeScalars.count == 1,
              (0xAC00...0xD7A3).contains(scalar.value) else { return ch }
        let index = Int(scalar.value - 0xAC00) / 588
        return choseongTable[index]
    }

    private static func isCompatibilityConsonant(_ ch: Character) -> Bool {
        guard let scalar = ch.unicodeScalars.first, ch.unicodeScalars.count == 1 else { return false }
        return (0x3131...0x314E).contains(scalar.value)
    }

    private static func firstIndex(of needle: [Character], in hay: [Character]) -> Int? {
        guard needle.count <= hay.count else { return nil }
        for i in 0...(hay.count - needle.count) where hay[i] == needle[0] {
            if Array(hay[i..<i + needle.count]) == needle { return i }
        }
        return nil
    }

    private static func subsequence(_ q: [Character], in name: [Character]) -> [Int]? {
        var hits: [Int] = []
        var j = 0
        for (i, ch) in name.enumerated() where j < q.count && ch == q[j] {
            hits.append(i)
            j += 1
        }
        return j == q.count ? hits : nil
    }

    /// Levenshtein distance with adjacent swaps, stopping early past `limit`.
    private static func editDistance(_ a: [Character], _ b: [Character], limit: Int) -> Int {
        if abs(a.count - b.count) > limit { return limit + 1 }
        var prevPrev = [Int](repeating: 0, count: b.count + 1)
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var current = [Int](repeating: 0, count: b.count + 1)
            current[0] = i
            var rowMin = current[0]
            for j in stride(from: 1, through: b.count, by: 1) {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                var value = min(prev[j] + 1, current[j - 1] + 1, prev[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    value = min(value, prevPrev[j - 2] + 1)
                }
                current[j] = value
                rowMin = min(rowMin, value)
            }
            if rowMin > limit { return limit + 1 }
            prevPrev = prev
            prev = current
        }
        return prev[b.count]
    }
}
