import Foundation

/// SymSpell-style (Symmetric Delete) candidate generator.
///
/// Precomputes delete-variants of every dictionary word so that all
/// insert/replace/transpose/delete typos within `maxEditDistance` can be found
/// with hash lookups instead of scanning the dictionary. This is the candidate
/// *finder* only (PLAN.md issue 1) — ranking stays with
/// `AutocorrectEngine.weightedDistance` (QWERTY proximity) + frequency.
///
/// Memory note: the delete index is the dominant cost and the reason for the
/// on-device benchmark gate (see `SymSpellBenchmarkTests`). `prefixLength`
/// bounds it: only the first `prefixLength` characters of each word are
/// expanded into deletes (the original SymSpell optimization).
final class SymSpellEngine {

    /// A candidate correction for a typed word.
    struct Candidate {
        let word: String
        let distance: Int   // true edit distance to the input
        let count: Int      // corpus frequency
    }

    let maxEditDistance: Int
    let prefixLength: Int

    /// word -> corpus frequency (also answers "is this a real word")
    private var words: [String: Int] = [:]
    /// delete-variant -> dictionary words that produce it
    private var deletes: [String: [String]] = [:]

    init(maxEditDistance: Int = 2, prefixLength: Int = 7) {
        self.maxEditDistance = maxEditDistance
        self.prefixLength = prefixLength
    }

    // MARK: - Loading

    /// Load from in-memory frequency data (same shape as `NextWordEngine.load`).
    func load(unigrams: [(String, Int)]) {
        words.reserveCapacity(unigrams.count)
        for (word, count) in unigrams {
            let w = word.lowercased()
            words[w] = count
            for variant in deleteVariants(of: w) {
                deletes[variant, default: []].append(w)
            }
        }
    }

    /// Load from the bundled `unigrams_<lang>.txt` format: `word\tcount` lines.
    func load(unigramsText text: String, limit: Int = .max) {
        var pairs: [(String, Int)] = []
        pairs.reserveCapacity(min(50_000, limit))
        for line in text.split(separator: "\n") {
            if pairs.count >= limit { break }
            let parts = line.split(separator: "\t")
            guard parts.count == 2, let count = Int(parts[1]) else { continue }
            pairs.append((String(parts[0]), count))
        }
        load(unigrams: pairs)
    }

    var wordCount: Int { words.count }
    var deleteIndexCount: Int { deletes.count }

    func contains(_ word: String) -> Bool { words[word.lowercased()] != nil }

    // MARK: - Lookup

    /// Correction candidates for `input`, sorted by (edit distance, frequency).
    /// Returns [] when the input is a known word (distance 0) — same contract
    /// as `AutocorrectEngine`: don't correct real words.
    func lookup(_ input: String, limit: Int = 8) -> [Candidate] {
        let typed = input.lowercased()
        guard !typed.isEmpty, words[typed] == nil else { return [] }

        var seen = Set<String>()
        var results: [Candidate] = []
        func consider(_ word: String) {
            guard !seen.contains(word) else { return }
            seen.insert(word)
            let d = editDistance(typed, word, max: maxEditDistance)
            if d <= maxEditDistance {
                results.append(Candidate(word: word, distance: d, count: words[word] ?? 0))
            }
        }
        for variant in deleteVariants(of: typed, includeSelf: true) {
            // The variant may itself be a dictionary word (typo = insertion,
            // e.g. "wants" -> "want") — the delete index excludes self-entries,
            // so check the dictionary directly too.
            if words[variant] != nil { consider(variant) }
            for word in deletes[variant] ?? [] { consider(word) }
        }
        return results
            .sorted { $0.distance != $1.distance ? $0.distance < $1.distance : $0.count > $1.count }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Symmetric delete internals

    /// All strings obtained by deleting up to `maxEditDistance` characters from
    /// the first `prefixLength` characters of `word`.
    private func deleteVariants(of word: String, includeSelf: Bool = false) -> Set<String> {
        let prefix = String(word.prefix(prefixLength))
        var variants: Set<String> = includeSelf ? [prefix] : []
        var frontier: Set<String> = [prefix]
        for _ in 0..<maxEditDistance {
            var next: Set<String> = []
            for w in frontier where w.count > 1 {
                let chars = Array(w)
                for i in 0..<chars.count {
                    var deleted = chars
                    deleted.remove(at: i)
                    next.insert(String(deleted))
                }
            }
            variants.formUnion(next)
            frontier = next
        }
        if word.count > prefixLength {
            // The prefix itself is a reachable "delete" of the full word —
            // index it so deletion typos that land exactly on the prefix match.
            variants.insert(prefix)
        } else if !includeSelf {
            variants.remove(prefix)
        }
        return variants
    }

    /// Plain Levenshtein with early-exit band; returns max+1 when exceeded.
    /// (Unweighted on purpose — QWERTY-weighted ranking happens afterwards in
    /// `AutocorrectEngine.reranked`.)
    func editDistance(_ a: String, _ b: String, max maxD: Int) -> Int {
        let s = Array(a), t = Array(b)
        if abs(s.count - t.count) > maxD { return maxD + 1 }
        if s.isEmpty { return t.count }
        if t.isEmpty { return s.count }
        var prev = Array(0...t.count)
        var cur = [Int](repeating: 0, count: t.count + 1)
        for i in 1...s.count {
            cur[0] = i
            var rowMin = cur[0]
            for j in 1...t.count {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                cur[j] = Swift.min(prev[j - 1] + cost, prev[j] + 1, cur[j - 1] + 1)
                rowMin = Swift.min(rowMin, cur[j])
            }
            if rowMin > maxD { return maxD + 1 }   // whole row over budget — bail
            swap(&prev, &cur)
        }
        return prev[t.count]
    }
}
