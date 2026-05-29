import Foundation

final class PredictionEngine {
    private var wordList: [String] = []
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

        let name = "translations_\(pairKey)"
        if let url = Bundle.main.url(forResource: name, withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            wordList = dict.keys.map { $0.lowercased() }.sorted()
        }
        loadedPairKey = pairKey
    }

    func evict() {
        wordList.removeAll(keepingCapacity: false)
        loadedPairKey = ""
    }

    func predictions(for prefix: String, limit: Int = 3) -> [String] {
        let cleaned = prefix.lowercased()
            .trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return Array(Self.fallback.prefix(limit))
        }

        var results: [String] = []
        if !wordList.isEmpty {
            let start = lowerBound(prefix: cleaned)
            var i = start
            while i < wordList.count, wordList[i].hasPrefix(cleaned), results.count < limit {
                results.append(wordList[i])
                i += 1
            }
        }

        if results.count < limit {
            for w in Self.fallback {
                if w.hasPrefix(cleaned), !results.contains(w) {
                    results.append(w)
                    if results.count >= limit { break }
                }
            }
        }

        if results.count < limit {
            for w in Self.fallback {
                if !results.contains(w) {
                    results.append(w)
                    if results.count >= limit { break }
                }
            }
        }

        return Array(results.prefix(limit))
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
