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
        return checker.guesses(forWordRange: misspelled, in: word, language: language.isoCode)?.first
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
        return Array(guesses.prefix(limit))
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
