import Foundation
import KeyboardKit

/// Feeds our next-word/autocorrect suggestions into KeyboardKit's native
/// autocomplete system. KeyboardKit owns all typing, capitalization, and
/// autocorrect-on-space; this only supplies *what* to show and *what* to
/// autocorrect — there is no custom typing code, so capitalization can't break.
///
/// - The word being typed → its autocorrect candidate (marked `.autocorrect`, so
///   KeyboardKit applies it on space) plus completions.
/// - After a space → next-word predictions.
///
/// Translation glosses are no longer attached here: they come from Apple's
/// Translation framework (async) via `AppleTranslator`, which the bar reads
/// directly. This service only produces the words.
final class SuggestionService: AutocompleteService {

    var locale: Locale
    private let nextWord: NextWordEngine
    private let autocorrect = AutocorrectEngine()
    private let language: () -> Language

    init(
        locale: Locale,
        nextWord: NextWordEngine,
        language: @escaping () -> Language
    ) {
        self.locale = locale
        self.nextWord = nextWord
        self.language = language
    }

    func autocomplete(_ text: String) async throws -> Autocomplete.Result {
        let current = trailingWord(in: text)
        let suggestions: [Autocomplete.Suggestion]
        if current.isEmpty {
            suggestions = afterSpaceSuggestions(in: text)
        } else {
            suggestions = midWordSuggestions(for: current)
        }
        return Autocomplete.Result(inputText: text, suggestions: suggestions)
    }

    // MARK: - Suggestion building

    /// Just hit space: keep the word just committed in slot 0 (so its translation
    /// stays visible), then fill slots 1–2 with next-word predictions.
    private func afterSpaceSuggestions(in text: String) -> [Autocomplete.Suggestion] {
        let prev = previousWord(in: text)
        var out: [Autocomplete.Suggestion] = []
        if !prev.isEmpty {
            out.append(Autocomplete.Suggestion(text: prev, type: .unknown))
        }
        for word in nextWord.nextWords(after: prev, limit: 3) where out.count < 3 {
            guard word.lowercased() != prev.lowercased() else { continue }
            out.append(regular(word))
        }
        return Array(out.prefix(3))
    }

    private func midWordSuggestions(for word: String) -> [Autocomplete.Suggestion] {
        var out: [Autocomplete.Suggestion] = []
        // Slot 0: the literal typed word ("keep my spelling").
        out.append(Autocomplete.Suggestion(text: word, type: .unknown))

        // Autocorrect candidate (marked so KeyboardKit applies it on space).
        let corrections = autocorrect.suggestions(word: word, language: language(), limit: 2)
        if let top = corrections.first {
            out.append(Autocomplete.Suggestion(text: top, type: .autocorrect))
        }

        // Fill the remaining slot(s) with completions.
        for completion in nextWord.completions(for: word, limit: 3) where out.count < 3 {
            let lower = completion.lowercased()
            guard lower != word.lowercased(), !corrections.contains(where: { $0.lowercased() == lower }) else { continue }
            out.append(regular(completion))
        }
        return Array(out.prefix(3))
    }

    private func regular(_ word: String) -> Autocomplete.Suggestion {
        Autocomplete.Suggestion(text: word, type: .regular)
    }

    // MARK: - Word helpers

    /// The run of letters immediately before the cursor (the word being typed).
    private func trailingWord(in text: String) -> String {
        var chars: [Character] = []
        for ch in text.reversed() {
            if ch.isLetter { chars.append(ch) } else { break }
        }
        return String(chars.reversed())
    }

    /// The last completed word before the cursor (for next-word prediction).
    private func previousWord(in text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        return trimmed.components(separatedBy: separators).filter { !$0.isEmpty }.last ?? ""
    }

    // MARK: - Word management (KeyboardKit AutocompleteService requirements)

    var canIgnoreWords: Bool { false }
    var canLearnWords: Bool { true }
    var ignoredWords: [String] { [] }
    var learnedWords: [String] { [] }
    func hasIgnoredWord(_ word: String) -> Bool { false }
    func hasLearnedWord(_ word: String) -> Bool { false }
    func ignoreWord(_ word: String) {}
    func learnWord(_ word: String) { autocorrect.learn(word) }
    func removeIgnoredWord(_ word: String) {}
    func unlearnWord(_ word: String) {}
}
