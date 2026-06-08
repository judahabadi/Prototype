import Foundation
import UIKit

struct AutocorrectService {
    private static let checker = UITextChecker()

    /// Top correction for a misspelled word, or nil if it's spelled correctly
    /// (or is a known personal/lexicon word).
    static func correct(word: String, language: Language, lexicon: Set<String> = []) -> String? {
        guard !word.isEmpty else { return nil }
        if lexicon.contains(word.lowercased()) { return nil }
        let range = NSRange(location: 0, length: word.utf16.count)
        let misspelled = checker.rangeOfMisspelledWord(
            in: word,
            range: range,
            startingAt: 0,
            wrap: false,
            language: language.isoCode
        )
        guard misspelled.location != NSNotFound else { return nil }
        let guesses = checker.guesses(forWordRange: misspelled, in: word, language: language.isoCode) ?? []
        return reranked(guesses, typed: word).first
    }

    /// Multiple ranked correction guesses for a misspelled word; empty when the
    /// word is spelled correctly or is a known personal/lexicon word.
    static func suggestions(word: String, language: Language, limit: Int = 2, lexicon: Set<String> = []) -> [String] {
        guard !word.isEmpty else { return [] }
        if lexicon.contains(word.lowercased()) { return [] }
        let range = NSRange(location: 0, length: word.utf16.count)
        let misspelled = checker.rangeOfMisspelledWord(
            in: word,
            range: range,
            startingAt: 0,
            wrap: false,
            language: language.isoCode
        )
        guard misspelled.location != NSNotFound else { return [] }
        let guesses = checker.guesses(forWordRange: misspelled, in: word, language: language.isoCode) ?? []
        return Array(reranked(guesses, typed: word).prefix(limit))
    }

    // MARK: - Keyboard-aware re-ranking

    /// Re-order UITextChecker's guesses so the one closest to what was actually
    /// typed wins. Apple's spell checker ranks by dictionary likelihood, which
    /// often picks a common word over the obvious typo (e.g. "wint" -> "want"
    /// instead of "wont"). We re-score each guess by a keyboard-key-distance
    /// edit distance — a substitution between adjacent keys (i↔o) costs far less
    /// than between far keys (i↔a) — so "wont" wins. UITextChecker's original
    /// order (its frequency ranking) breaks ties, combining both signals.
    private static func reranked(_ guesses: [String], typed: String) -> [String] {
        guard guesses.count > 1 else { return guesses }
        return guesses.enumerated()
            .sorted { a, b in
                let da = weightedDistance(typed, a.element)
                let db = weightedDistance(typed, b.element)
                return da != db ? da < db : a.offset < b.offset
            }
            .map { $0.element }
    }

    private static let qwertyRows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]

    private static func keyPosition(_ c: Character) -> (row: Int, col: Int)? {
        let lc = Character(c.lowercased())
        for (r, row) in qwertyRows.enumerated() {
            if let i = row.firstIndex(of: lc) {
                return (r, row.distance(from: row.startIndex, to: i))
            }
        }
        return nil
    }

    /// Substitution cost in [0, 1]: ~0 for the same key, ~0.5 for adjacent keys,
    /// 1.0 for far-apart or non-letter keys.
    private static func substitutionCost(_ a: Character, _ b: Character) -> Double {
        if a.lowercased() == b.lowercased() { return 0 }
        guard let pa = keyPosition(a), let pb = keyPosition(b) else { return 1 }
        let dr = Double(pa.row - pb.row), dc = Double(pa.col - pb.col)
        return min((dr * dr + dc * dc).squareRoot() / 2.0, 1.0)
    }

    /// Levenshtein distance where substitutions are weighted by keyboard
    /// proximity; insertions/deletions cost 1 each.
    private static func weightedDistance(_ from: String, _ to: String) -> Double {
        let s = Array(from.lowercased()), t = Array(to.lowercased())
        if s.isEmpty { return Double(t.count) }
        if t.isEmpty { return Double(s.count) }
        var prev = (0...t.count).map(Double.init)
        var cur = [Double](repeating: 0, count: t.count + 1)
        for i in 1...s.count {
            cur[0] = Double(i)
            for j in 1...t.count {
                let sub = prev[j - 1] + substitutionCost(s[i - 1], t[j - 1])
                cur[j] = min(sub, prev[j] + 1, cur[j - 1] + 1)
            }
            swap(&prev, &cur)
        }
        return prev[t.count]
    }

    /// Remember a word so it is no longer flagged as misspelled (persists in the
    /// system text checker). `rangeOfMisspelledWord` automatically respects this.
    static func learn(_ word: String) {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty else { return }
        UITextChecker.learnWord(w)
    }

    private static let frequencyKey = "typedWordFrequency"
    private static let learnThreshold = 3

    /// Count how often the user commits each word and, once one has been typed
    /// `learnThreshold` times, learn it — so words the user uses a lot stop being
    /// flagged/autocorrected and start showing up as suggestions (like Apple's
    /// "learns the words you use" behaviour). Persisted across sessions.
    static func note(typedWord word: String) {
        let w = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard w.count >= 3, w.allSatisfy({ $0.isLetter }) else { return }
        let defaults = AppGroup.defaults
        var counts = defaults.dictionary(forKey: frequencyKey) as? [String: Int] ?? [:]
        let n = (counts[w] ?? 0) + 1
        counts[w] = n
        defaults.set(counts, forKey: frequencyKey)
        if n == learnThreshold {
            learn(word)
        }
    }
}
