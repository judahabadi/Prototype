import Foundation

/// Next-word + completion engine backed by n-gram frequency data.
///
/// Backed by bigram/unigram tables built from the OPUS OpenSubtitles corpus
/// (see `scripts/build_ngrams.py`), but `load(unigrams:bigrams:)` accepts any
/// in-memory data so it's deterministic to unit-test without bundled files.
///
/// Lookup is "stupid backoff": try the bigram for the last word; if none, fall
/// back to the most frequent unigrams. Only the top-K next words per head word
/// are kept, to bound memory in the keyboard extension.
final class NextWordEngine {

    private var unigrams: [(word: String, count: Int)] = []   // sorted desc by count
    private var bigrams: [String: [(word: String, count: Int)]] = [:]  // head -> top-K nexts
    private let topKPerHead: Int

    init(topKPerHead: Int = 8) {
        self.topKPerHead = topKPerHead
    }

    // MARK: - Loading

    /// Load from in-memory frequency data. Words are lowercased; unigrams are
    /// sorted by frequency and bigrams are trimmed to the top-K nexts per head.
    func load(unigrams: [(String, Int)], bigrams: [(String, String, Int)]) {
        self.unigrams = unigrams
            .map { (word: $0.0.lowercased(), count: $0.1) }
            .sorted { $0.count > $1.count }

        var grouped: [String: [(word: String, count: Int)]] = [:]
        for (head, next, count) in bigrams {
            grouped[head.lowercased(), default: []].append((next.lowercased(), count))
        }
        self.bigrams = [:]
        for (head, list) in grouped {
            self.bigrams[head] = Array(list.sorted { $0.count > $1.count }.prefix(topKPerHead))
        }
    }

    /// Load bigrams from the project's `ngrams_*.json` format — head word → an
    /// ordered list of likely next words (already sorted, no counts). List
    /// position becomes a descending pseudo-count. Unigrams come from a separate
    /// frequency list (`unigrams_en.txt`).
    func load(bigramLists: [String: [String]], unigrams: [(String, Int)]) {
        self.unigrams = unigrams
            .map { (word: $0.0.lowercased(), count: $0.1) }
            .sorted { $0.count > $1.count }
        self.bigrams = [:]
        for (head, nexts) in bigramLists {
            let scored = nexts.enumerated().map {
                (word: $0.element.lowercased(), count: nexts.count - $0.offset)
            }
            self.bigrams[head.lowercased()] = Array(scored.prefix(topKPerHead))
        }
    }

    /// Build the English engine from the bundled `ngrams_en.json` (bigrams,
    /// top-5 next words per head) and `unigrams_en.txt` (word-frequency list,
    /// trimmed). Returns nil if a resource is missing.
    static func english(in bundle: Bundle = .main) -> NextWordEngine? {
        guard let ngramsURL = bundle.url(forResource: "ngrams_en", withExtension: "json"),
              let unigramURL = bundle.url(forResource: "unigrams_en", withExtension: "txt"),
              let ngramsData = try? Data(contentsOf: ngramsURL),
              let lists = try? JSONDecoder().decode([String: [String]].self, from: ngramsData),
              let unigramText = try? String(contentsOf: unigramURL, encoding: .utf8)
        else { return nil }

        var unigrams: [(String, Int)] = []
        for line in unigramText.split(separator: "\n") {
            let parts = line.split(separator: "\t")
            if parts.count == 2, let count = Int(parts[1]) {
                unigrams.append((String(parts[0]), count))
            }
        }
        let engine = NextWordEngine()
        engine.load(bigramLists: lists, unigrams: unigrams)
        return engine
    }

    /// Load from tab-separated frequency text:
    /// unigram lines are `word\tcount`; bigram lines are
    /// `word1 word2\tcount`. Used at runtime with the bundled data files.
    func loadFromTSV(unigramText: String, bigramText: String) {
        var uni: [(String, Int)] = []
        for line in unigramText.split(separator: "\n") {
            let parts = line.split(separator: "\t")
            guard parts.count == 2, let c = Int(parts[1]) else { continue }
            uni.append((String(parts[0]), c))
        }
        var bi: [(String, String, Int)] = []
        for line in bigramText.split(separator: "\n") {
            let parts = line.split(separator: "\t")
            guard parts.count == 2, let c = Int(parts[1]) else { continue }
            let words = parts[0].split(separator: " ")
            guard words.count == 2 else { continue }
            bi.append((String(words[0]), String(words[1]), c))
        }
        load(unigrams: uni, bigrams: bi)
    }

    // MARK: - Query

    /// Next-word suggestions after `lastWord` (the word just committed). Falls
    /// back to the most frequent unigrams when the bigram has no entry.
    func nextWords(after lastWord: String, limit: Int = 3) -> [String] {
        let head = lastWord.lowercased()
        if let list = bigrams[head], !list.isEmpty {
            return Array(list.prefix(limit).map { $0.word })
        }
        return Array(unigrams.prefix(limit).map { $0.word })
    }

    /// Completions for the partial word currently being typed (prefix match,
    /// most frequent first). Excludes the partial itself.
    func completions(for partial: String, limit: Int = 3) -> [String] {
        let p = partial.lowercased()
        guard !p.isEmpty else { return [] }
        return Array(
            unigrams.lazy
                .filter { $0.word.hasPrefix(p) && $0.word != p }
                .prefix(limit)
                .map { $0.word }
        )
    }
}
