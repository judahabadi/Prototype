import Foundation
import UIKit

struct Prediction: Hashable {
    var source: String
    var translation: String
    var highlighted: Bool
    var isLoading: Bool

    static let empty = Prediction(source: "", translation: "", highlighted: false, isLoading: false)
}

final class PredictionEngine {
    private var dict: [String: String] = [:]
    private var loadedPairKey: String = ""
    private var nativeIsoCode: String = "en"
    private let checker = UITextChecker()

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
    }

    func evict() {
        dict.removeAll(keepingCapacity: false)
        loadedPairKey = ""
    }

    func translation(for word: String) -> String? {
        dict[word.lowercased()]
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
}
