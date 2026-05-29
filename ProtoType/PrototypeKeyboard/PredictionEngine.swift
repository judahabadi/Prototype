import Foundation

struct Prediction: Hashable {
    var source: String
    var translation: String
    var highlighted: Bool
    var isLoading: Bool

    static let empty = Prediction(source: "", translation: "", highlighted: false, isLoading: false)
}

final class PredictionEngine {
    private var wordList: [String] = []
    private var dict: [String: String] = [:]
    private var loadedPairKey: String = ""

    private static let fallback: [String] = [
        "the","be","to","of","and","a","in","that","have","it",
        "for","not","on","with","he","as","you","do","at","this",
        "but","his","by","from","they","we","say","her","she","or",
        "an","will","my","one","all","would","there","their","what",
        "so","up","out","if","about","who","get","which","go","me","when"
    ]

    func load(from: Language, to: Language) {
        let pairKey = "\(from.isoCode)_\(to.isoCode)"
        if pairKey == loadedPairKey, !wordList.isEmpty { return }
        wordList.removeAll(keepingCapacity: false)
        dict.removeAll(keepingCapacity: false)

        let name = "translations_\(pairKey)"
        if let url = Bundle.main.url(forResource: name, withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let parsed = try? JSONDecoder().decode([String: String].self, from: data) {
            for (k, v) in parsed {
                dict[k.lowercased()] = v
            }
            wordList = dict.keys.sorted()
        }
        loadedPairKey = pairKey
    }

    func evict() {
        wordList.removeAll(keepingCapacity: false)
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

        for w in Self.fallback {
            if seen.contains(w) { continue }
            if let v = dict[w] {
                out.append(Prediction(source: w, translation: v, highlighted: false, isLoading: false))
                seen.insert(w)
                if out.count >= limit { return out }
            }
        }

        for w in wordList {
            if seen.contains(w) { continue }
            let v = dict[w] ?? ""
            out.append(Prediction(source: w, translation: v, highlighted: false, isLoading: false))
            seen.insert(w)
            if out.count >= limit { return out }
        }

        while out.count < limit {
            out.append(.empty)
        }
        return out
    }

    func predictions(for prefix: String, limit: Int = 3) -> [Prediction] {
        let cleaned = prefix.lowercased()
            .trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return topPredictions(limit: limit)
        }

        var out: [Prediction] = []
        var seen = Set<String>()
        if !wordList.isEmpty {
            let start = lowerBound(prefix: cleaned)
            var i = start
            while i < wordList.count, wordList[i].hasPrefix(cleaned), out.count < limit {
                let key = wordList[i]
                let v = dict[key] ?? ""
                out.append(Prediction(source: key, translation: v, highlighted: false, isLoading: false))
                seen.insert(key)
                i += 1
            }
        }

        if out.count < limit {
            for w in Self.fallback where w.hasPrefix(cleaned) && !seen.contains(w) {
                let v = dict[w] ?? ""
                out.append(Prediction(source: w, translation: v, highlighted: false, isLoading: false))
                seen.insert(w)
                if out.count >= limit { break }
            }
        }

        while out.count < limit {
            out.append(.empty)
        }
        return out
    }

    private func lowerBound(prefix: String) -> Int {
        var lo = 0
        var hi = wordList.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if wordList[mid] < prefix {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return lo
    }
}
