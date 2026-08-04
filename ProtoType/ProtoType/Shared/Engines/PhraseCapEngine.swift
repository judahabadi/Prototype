import Foundation

/// Proper-noun and phrase capitalization (PLAN.md issue 3).
///
/// Rule-based autocap can capitalize sentence starts, but "i -> I",
/// "paris -> Paris", and multi-word names ("world cup -> World Cup") need a
/// dictionary — the words are only capitalized *as names*, and phrases only
/// capitalize *together*.
///
/// Pure suggestion engine: given the last few typed words it returns the cased
/// replacement or nil. It never touches the typing path itself. Only fires when
/// the user typed all-lowercase — intentional casing is never fought.
///
/// Seed data below covers high-frequency cases; `load(entries:)` accepts a
/// bigger per-language list later (Wikidata CC0 labels, per the locked plan).
/// Latin/Cyrillic languages only — zh/ja/ar/hi/bn/pa have no capitals.
struct PhraseCapEngine {

    /// lowercased key -> correctly cased form. Keys may be 1–3 words
    /// (space-separated); longest match wins.
    private var entries: [String: String]
    private let maxPhraseWords: Int

    init(entries: [String: String] = PhraseCapEngine.englishSeed) {
        self.entries = entries
        self.maxPhraseWords = entries.keys.map { $0.split(separator: " ").count }.max() ?? 1
    }

    /// Replace the seed with a full per-language list (e.g. Wikidata-derived).
    mutating func load(entries: [String: String]) {
        self = PhraseCapEngine(entries: entries)
    }

    /// A capitalization fix for the tail of `words` (the last 1...3 typed
    /// words), or nil. Returns the number of trailing words to replace and the
    /// replacement text. Longest phrase wins ("new york times" beats "new york").
    func fix(forTrailing words: [String]) -> (wordCount: Int, replacement: String)? {
        guard !words.isEmpty else { return nil }
        let tail = words.suffix(maxPhraseWords).map { String($0) }
        for length in stride(from: tail.count, through: 1, by: -1) {
            let candidate = tail.suffix(length).joined(separator: " ")
            // Only fire on all-lowercase input — respect intentional casing.
            guard candidate == candidate.lowercased() else { continue }
            if let cased = entries[candidate], cased != candidate {
                return (length, cased)
            }
        }
        return nil
    }

    /// Convenience for the single-word path (e.g. checking on each word break).
    func fix(word: String) -> String? {
        guard word == word.lowercased(), let cased = entries[word], cased != word else { return nil }
        return cased
    }

    // MARK: - Seed data (English)

    /// High-frequency proper nouns and phrases. A fuller list ships later as a
    /// per-language data file built from Wikidata (CC0) labels.
    static let englishSeed: [String: String] = [
        // The pronoun — the single most common miss.
        "i": "I", "i'm": "I'm", "i've": "I've", "i'll": "I'll", "i'd": "I'd",

        // Days and months.
        "monday": "Monday", "tuesday": "Tuesday", "wednesday": "Wednesday",
        "thursday": "Thursday", "friday": "Friday", "saturday": "Saturday",
        "sunday": "Sunday",
        "january": "January", "february": "February", "march": "March",
        "april": "April", "june": "June", "july": "July", "august": "August",
        "september": "September", "october": "October", "november": "November",
        "december": "December",
        // "may" deliberately omitted — far more often the verb than the month.

        // Common places and demonyms.
        "america": "America", "american": "American", "england": "England",
        "english": "English", "london": "London", "paris": "Paris",
        "europe": "Europe", "european": "European", "africa": "Africa",
        "asia": "Asia", "india": "India", "china": "China", "japan": "Japan",
        "france": "France", "germany": "Germany", "spain": "Spain",
        "russia": "Russia", "brazil": "Brazil", "mexico": "Mexico",
        "canada": "Canada", "australia": "Australia", "texas": "Texas",
        "california": "California", "chicago": "Chicago", "boston": "Boston",

        // Multi-word names — the "world cup" class.
        "world cup": "World Cup", "new york": "New York",
        "new york city": "New York City", "los angeles": "Los Angeles",
        "san francisco": "San Francisco", "las vegas": "Las Vegas",
        "united states": "United States", "united kingdom": "United Kingdom",
        "middle east": "Middle East", "south america": "South America",
        "north america": "North America", "new zealand": "New Zealand",
        "super bowl": "Super Bowl", "olympic games": "Olympic Games",

        // Brands people type constantly.
        "iphone": "iPhone", "ipad": "iPad", "google": "Google",
        "youtube": "YouTube", "instagram": "Instagram", "whatsapp": "WhatsApp",
        "tiktok": "TikTok", "netflix": "Netflix", "amazon": "Amazon",
        "facebook": "Facebook", "spotify": "Spotify", "uber": "Uber",
    ]
}
