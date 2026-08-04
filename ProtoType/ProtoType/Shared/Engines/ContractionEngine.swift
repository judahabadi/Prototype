import Foundation

/// Contraction fixer (PLAN.md issue 2).
///
/// SymSpell/edit-distance can't fix `wont -> won't`, `cant -> can't`, etc.,
/// because the un-apostrophe'd forms are usually themselves valid words
/// (distance 0). This is a curated per-language replacement map applied
/// independently of the spell corrector.
///
/// Pure and data-only — it returns a *suggestion*; it does not touch the typing
/// path. Casing of the input is preserved (`Wont -> Won't`, `WONT -> WON'T`).
struct ContractionEngine {

    /// Lowercased de-apostrophe'd form -> correct contraction. English is the
    /// only language with a meaningful set; others stay empty until needed.
    static let maps: [Language: [String: String]] = [
        .english: [
            "im": "I'm", "ive": "I've", "ill": "I'll", "id": "I'd",
            "dont": "don't", "doesnt": "doesn't", "didnt": "didn't",
            "wont": "won't", "wouldnt": "wouldn't", "cant": "can't",
            "couldnt": "couldn't", "shouldnt": "shouldn't", "isnt": "isn't",
            "arent": "aren't", "wasnt": "wasn't", "werent": "weren't",
            "hasnt": "hasn't", "havent": "haven't", "hadnt": "hadn't",
            "youre": "you're", "youve": "you've", "youll": "you'll", "youd": "you'd",
            "theyre": "they're", "theyve": "they've", "theyll": "they'll", "theyd": "they'd",
            "weve": "we've", "wed": "we'd", "well": "we'll", "were": "we're",
            "hes": "he's", "shes": "she's", "its": "it's", "thats": "that's",
            "whats": "what's", "wheres": "where's", "whos": "who's", "hows": "how's",
            "lets": "let's", "aint": "ain't", "yall": "y'all",
        ],
    ]

    /// Ambiguous keys whose un-apostrophe'd form is itself a common, valid word
    /// (`its`/`it's`, `were`/`we're`, `well`/`we'll`, `hes`/`he's`). These are
    /// only offered as a *suggestion*, never auto-applied, until the n-gram
    /// (issue 4) can disambiguate by context.
    static let contextSensitive: Set<String> = ["its", "were", "well", "hes", "wed", "ill", "id", "shes"]

    /// The contraction for a word, or nil if there is no mapping. Preserves the
    /// input's casing.
    func contraction(for word: String, language: Language) -> String? {
        guard let map = Self.maps[language] else { return nil }
        let lower = word.lowercased()
        guard let fixed = map[lower] else { return nil }
        return recase(fixed, like: word)
    }

    /// True when the mapping should be *suggested only*, not auto-applied,
    /// because the typed form is itself a valid word.
    func isContextSensitive(_ word: String) -> Bool {
        Self.contextSensitive.contains(word.lowercased())
    }

    // MARK: - Casing

    /// Re-apply the input word's casing to the replacement: ALL CAPS stays all
    /// caps, leading-cap stays capitalized, anything else is left as written
    /// (the map values already carry correct casing, e.g. "I'm").
    private func recase(_ replacement: String, like input: String) -> String {
        let letters = input.filter { $0.isLetter }
        guard !letters.isEmpty else { return replacement }
        if letters == letters.uppercased() && letters != letters.lowercased() {
            return replacement.uppercased()
        }
        if let first = input.first, first.isUppercase {
            return replacement.prefix(1).uppercased() + replacement.dropFirst()
        }
        return replacement
    }
}
