import Foundation
import UIKit
import NaturalLanguage

struct Prediction: Hashable {
    var source: String
    var translation: String
    var highlighted: Bool
    var isLoading: Bool
    var quoted: Bool = false

    static let empty = Prediction(source: "", translation: "", highlighted: false, isLoading: false)
}

final class PredictionEngine {
    private var dict: [String: String] = [:]
    private var ngrams: [String: [String]] = [:]
    private var loadedPairKey: String = ""
    private var loadedNgramLang: String = ""
    private let checker = UITextChecker()
    private lazy var lemmaTagger = NLTagger(tagSchemes: [.lemma])

    private var nativeIsoCode: String = "en"

    private static let fallback = [
        "the","be","to","of","and","a","in","that","have","it",
        "for","not","on","with","he","as","you","do","at","this"
    ]

    func load(from: Language, to: Language) {
        let pairKey = "\(from.isoCode)_\(to.isoCode)"
        if pairKey == loadedPairKey { return }
        dict.removeAll(keepingCapacity: false)
        nativeIsoCode = from.isoCode

        let name = "translations_\(pairKey)"
        if let url = Bundle.main.url(forResource: name, withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let parsed = try? JSONDecoder().decode([String: String].self, from: data) {
            for (k, v) in parsed { dict[k.lowercased()] = v }
        }
        loadedPairKey = pairKey
        loadNgrams(for: from.isoCode)
    }

    func evict() {
        dict.removeAll(keepingCapacity: false)
        ngrams.removeAll(keepingCapacity: false)
        loadedPairKey = ""
        loadedNgramLang = ""
    }

    func translation(for word: String) -> String? {
        let key = word.lowercased()
        if let hit = dict[key] { return hit }
        // Fallback: try the word's base form so inflected words ("running",
        // "gatos") still hit the base-form dictionary ("run", "gato").
        if let lemma = lemma(of: key), lemma != key, let hit = dict[lemma] {
            return hit
        }
        return nil
    }

    private func lemma(of word: String) -> String? {
        guard !word.isEmpty else { return nil }
        lemmaTagger.string = word
        let range = word.startIndex..<word.endIndex
        lemmaTagger.setLanguage(NLLanguage(rawValue: nativeIsoCode), range: range)
        let (tag, _) = lemmaTagger.tag(at: word.startIndex, unit: .word, scheme: .lemma)
        guard let result = tag?.rawValue.lowercased(), !result.isEmpty else { return nil }
        return result
    }

    // Next-word prediction: call when the user just finished a word
    func nextWords(after previousWord: String, limit: Int = 3) -> [Prediction] {
        let key = previousWord.lowercased()
            .trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty, let nexts = ngrams[key] {
            var out: [Prediction] = []
            for w in nexts where out.count < limit {
                out.append(Prediction(source: w, translation: dict[w] ?? "", highlighted: false, isLoading: false))
            }
            while out.count < limit { out.append(.empty) }
            return out
        }
        return topPredictions(limit: limit)
    }

    // Prefix completion: call while the user is mid-word
    func predictions(for prefix: String, limit: Int = 3) -> [Prediction] {
        let cleaned = prefix.lowercased()
            .trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return topPredictions(limit: limit)
        }

        let range = NSRange(location: 0, length: cleaned.utf16.count)
        let completions = checker.completions(
            forPartialWordRange: range,
            in: cleaned,
            language: nativeIsoCode
        ) ?? []

        var out: [Prediction] = []
        var seen = Set<String>()
        for word in completions where out.count < limit {
            let key = word.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(Prediction(source: word, translation: dict[key] ?? "", highlighted: false, isLoading: false))
        }
        while out.count < limit { out.append(.empty) }
        return out
    }

    func topPredictions(excluding: String? = nil, limit: Int = 3) -> [Prediction] {
        var seen = Set<String>()
        if let ex = excluding { seen.insert(ex.lowercased()) }
        var out: [Prediction] = []
        for w in Self.fallback where !seen.contains(w) && out.count < limit {
            out.append(Prediction(source: w, translation: dict[w] ?? "", highlighted: false, isLoading: false))
            seen.insert(w)
        }
        while out.count < limit { out.append(.empty) }
        return out
    }

    private func loadNgrams(for isoCode: String) {
        if isoCode == loadedNgramLang { return }
        ngrams.removeAll(keepingCapacity: false)
        let name = "ngrams_\(isoCode)"
        if let url = Bundle.main.url(forResource: name, withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let parsed = try? JSONDecoder().decode([String: [String]].self, from: data) {
            ngrams = parsed
        }
        loadedNgramLang = isoCode
    }
}
