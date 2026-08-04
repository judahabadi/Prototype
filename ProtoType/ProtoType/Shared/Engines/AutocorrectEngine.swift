import Foundation
import UIKit

/// Autocorrect built on Apple's `UITextChecker` (detection + candidate words),
/// re-ranked so the candidate closest to what was actually typed wins.
///
/// `UITextChecker` ranks by dictionary likelihood, which often picks a common
/// word over the obvious typo (e.g. "wint" -> "want" instead of "wont"). We
/// re-score each candidate by a keyboard-key-distance edit distance — a
/// substitution between adjacent keys (i↔o) costs far less than between far
/// keys (i↔a) — so "wont" wins. The checker's original order (its frequency
/// ranking) breaks ties, combining both signals.
///
/// Lives in `Shared/` so the keyboard extension, the in-app demo, and the test
/// target can all use it. The pure re-ranking helpers are `internal` (not
/// `private`) so they can be unit-tested deterministically without depending on
/// the OS dictionary's guess output.
///
/// PLAN.md issue 1: when a `SymSpellEngine` is supplied (English only, for
/// now — it's the only language with a bundled word-frequency list), its
/// delete-index candidates are the primary source, re-ranked the same way as
/// before (keyboard-distance, then frequency). `UITextChecker` is the safety
/// net: used whenever SymSpell isn't loaded, isn't English, or finds nothing.
struct AutocorrectEngine {

    private let checker = UITextChecker()
    private let symSpell: SymSpellEngine?

    init(symSpell: SymSpellEngine? = nil) {
        self.symSpell = symSpell
    }

    /// Top correction for a misspelled word, or nil if it is spelled correctly
    /// or is a known personal/lexicon word.
    func correct(word: String, language: Language, lexicon: Set<String> = []) -> String? {
        suggestions(word: word, language: language, limit: 1, lexicon: lexicon).first
    }

    /// Ranked correction candidates for a misspelled word; empty when the word
    /// is spelled correctly or is a known personal/lexicon word.
    func suggestions(word: String, language: Language, limit: Int = 2, lexicon: Set<String> = []) -> [String] {
        guard !word.isEmpty, !lexicon.contains(word.lowercased()) else { return [] }

        if language == .english, let symSpellResult = symSpellSuggestions(for: word) {
            return Array(symSpellResult.prefix(limit))
        }

        guard let guesses = uiTextCheckerGuesses(for: word, language: language) else { return [] }
        return Array(reranked(guesses, typed: word).prefix(limit))
    }

    /// SymSpell candidates for `word`, re-ranked, or nil to fall back to
    /// `UITextChecker` (no engine loaded, word is a known word, or no
    /// delete-index candidates were found within the edit-distance budget).
    private func symSpellSuggestions(for word: String) -> [String]? {
        guard let symSpell, symSpell.wordCount > 0, !symSpell.contains(word) else { return nil }
        let candidates = symSpell.lookup(word, limit: 8)
        guard !candidates.isEmpty else { return nil }
        return rerankedCandidates(candidates, typed: word)
    }

    /// `UITextChecker` guesses for a word, or nil when the word is not flagged
    /// as misspelled (correctly spelled, or a known lexicon word). Lexicon/
    /// empty-word checks already happened in `suggestions`.
    private func uiTextCheckerGuesses(for word: String, language: Language) -> [String]? {
        let range = NSRange(location: 0, length: word.utf16.count)
        let misspelled = checker.rangeOfMisspelledWord(
            in: word, range: range, startingAt: 0, wrap: false, language: language.isoCode
        )
        guard misspelled.location != NSNotFound else { return nil }
        return checker.guesses(forWordRange: misspelled, in: word, language: language.isoCode) ?? []
    }

    /// Remember a word so it is no longer flagged as misspelled (persists in the
    /// system text checker).
    func learn(_ word: String) {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty else { return }
        UITextChecker.learnWord(w)
    }

    // MARK: - Keyboard-aware re-ranking (pure, unit-testable)

    /// Re-order candidates so the one closest to what was typed (by keyboard
    /// distance) wins; the original order breaks ties.
    func reranked(_ guesses: [String], typed: String) -> [String] {
        guard guesses.count > 1 else { return guesses }
        return guesses.enumerated()
            .sorted { a, b in
                let da = weightedDistance(typed, a.element)
                let db = weightedDistance(typed, b.element)
                return da != db ? da < db : a.offset < b.offset
            }
            .map { $0.element }
    }

    /// Re-order SymSpell candidates the same way as `reranked`, but breaking
    /// ties by corpus frequency (`Candidate.count`) instead of original order —
    /// SymSpell candidates arrive unordered by keyboard distance.
    func rerankedCandidates(_ candidates: [SymSpellEngine.Candidate], typed: String) -> [String] {
        candidates
            .sorted { a, b in
                let da = weightedDistance(typed, a.word)
                let db = weightedDistance(typed, b.word)
                return da != db ? da < db : a.count > b.count
            }
            .map { $0.word }
    }

    private static let qwertyRows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]

    private func keyPosition(_ c: Character) -> (row: Int, col: Int)? {
        let lc = Character(c.lowercased())
        for (r, row) in Self.qwertyRows.enumerated() {
            if let i = row.firstIndex(of: lc) {
                return (r, row.distance(from: row.startIndex, to: i))
            }
        }
        return nil
    }

    /// Substitution cost in [0, 1]: ~0 for the same key, ~0.5 for adjacent keys,
    /// 1.0 for far-apart or non-letter keys.
    private func substitutionCost(_ a: Character, _ b: Character) -> Double {
        if a.lowercased() == b.lowercased() { return 0 }
        guard let pa = keyPosition(a), let pb = keyPosition(b) else { return 1 }
        let dr = Double(pa.row - pb.row), dc = Double(pa.col - pb.col)
        return min((dr * dr + dc * dc).squareRoot() / 2.0, 1.0)
    }

    /// Levenshtein distance where substitutions are weighted by keyboard
    /// proximity; insertions/deletions cost 1 each.
    func weightedDistance(_ from: String, _ to: String) -> Double {
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
}
