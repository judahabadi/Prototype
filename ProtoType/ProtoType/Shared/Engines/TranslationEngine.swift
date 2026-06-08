import Foundation
import NaturalLanguage

/// Offline, on-device translation — local JSON dictionaries only, no network.
///
/// Loads `translations_{from}_{to}.json` (a flat `{ "word": "translation" }`
/// map) and looks a word up directly, falling back to the word's lemma so
/// inflected forms ("running", "gatos") still hit base-form entries
/// ("run", "gato"). Returns nil when there is no offline translation.
///
/// Lives in `Shared/` so the keyboard extension, the in-app demo, and tests can
/// all use it. `loadDictionary(_:nativeIso:)` allows deterministic unit tests
/// without bundled files.
final class TranslationEngine {

    private var dict: [String: String] = [:]
    private var loadedPairKey = ""
    private var nativeIso = "en"
    private lazy var lemmaTagger = NLTagger(tagSchemes: [.lemma])

    // MARK: - Loading

    /// Load the bundled dictionary for a language pair. No-op if already loaded.
    func load(from: Language, to: Language, bundle: Bundle = .main) {
        let pairKey = "\(from.isoCode)_\(to.isoCode)"
        guard pairKey != loadedPairKey else { return }
        dict.removeAll(keepingCapacity: false)
        nativeIso = from.isoCode
        if let url = bundle.url(forResource: "translations_\(pairKey)", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let parsed = try? JSONDecoder().decode([String: String].self, from: data) {
            for (k, v) in parsed { dict[k.lowercased()] = v }
        }
        loadedPairKey = pairKey
    }

    /// Seed an in-memory dictionary directly (tests / previews).
    func loadDictionary(_ dictionary: [String: String], nativeIso: String = "en") {
        dict = Dictionary(dictionary.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
        self.nativeIso = nativeIso
        loadedPairKey = "seeded"
    }

    func evict() {
        dict.removeAll(keepingCapacity: false)
        loadedPairKey = ""
    }

    // MARK: - Lookup

    /// Offline translation for a word, or nil if there is none. Tries the exact
    /// (lowercased) word, then its lemma.
    func translation(for word: String) -> String? {
        let key = word.lowercased()
        if let hit = dict[key] { return hit }
        if let lemma = lemma(of: key), lemma != key, let hit = dict[lemma] { return hit }
        return nil
    }

    private func lemma(of word: String) -> String? {
        guard !word.isEmpty else { return nil }
        lemmaTagger.string = word
        let range = word.startIndex..<word.endIndex
        lemmaTagger.setLanguage(NLLanguage(rawValue: nativeIso), range: range)
        let (tag, _) = lemmaTagger.tag(at: word.startIndex, unit: .word, scheme: .lemma)
        guard let result = tag?.rawValue.lowercased(), !result.isEmpty else { return nil }
        return result
    }
}
