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

    // Compact storage: Swift's [String: [String]] spent ~27MB on per-entry
    // object overhead for 50k words. Words are stored once and referenced by
    // Int32 index; the delete index is a sorted array of 64-bit variant hashes
    // with offsets into one flat postings array (CSR). Hash collisions are
    // harmless: every candidate is verified with `editDistance`.

    /// Dictionary words in load order, and their corpus frequencies.
    private var wordList: [String] = []
    private var counts: [Int32] = []
    /// word -> index into `wordList` (answers "is this a real word")
    private var wordIndex: [String: Int32] = [:]
    /// Sorted unique variant hashes; postings for `variantHashes[k]` are
    /// `postings[offsets[k] ..< offsets[k + 1]]`.
    private var variantHashes: [UInt64] = []
    private var offsets: [Int32] = []
    private var postings: [Int32] = []

    init(maxEditDistance: Int = 2, prefixLength: Int = 7) {
        self.maxEditDistance = maxEditDistance
        self.prefixLength = prefixLength
    }

    // MARK: - Loading

    /// Load from in-memory frequency data (same shape as `NextWordEngine.load`).
    /// Calling it again adds words and rebuilds the index.
    func load(unigrams: [(String, Int)]) {
        wordList.reserveCapacity(wordList.count + unigrams.count)
        for (word, count) in unigrams {
            let w = word.lowercased()
            if let i = wordIndex[w] { counts[Int(i)] = Int32(clamping: count); continue }
            wordIndex[w] = Int32(wordList.count)
            wordList.append(w)
            counts.append(Int32(clamping: count))
        }
        rebuildIndex()
    }

    private func rebuildIndex() {
        // (hash, word) pairs, sorted, then compacted — avoids a transient
        // dictionary of arrays so peak memory stays near the final size.
        var pairs: [(UInt64, Int32)] = []
        for (i, w) in wordList.enumerated() {
            for variant in deleteVariants(of: w) {
                pairs.append((Self.hash(variant), Int32(i)))
            }
        }
        pairs.sort { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
        variantHashes = []
        offsets = []
        postings = []
        postings.reserveCapacity(pairs.count)
        for (h, i) in pairs {
            if variantHashes.last != h {
                variantHashes.append(h)
                offsets.append(Int32(postings.count))
            }
            if postings.last != i || offsets.last == Int32(postings.count) {
                postings.append(i)
            }
        }
        offsets.append(Int32(postings.count))
    }

    /// FNV-1a over UTF-8 — stable across launches, unlike `Hasher`.
    private static func hash(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return h
    }

    private func postingsFor(_ variant: String) -> ArraySlice<Int32> {
        let h = Self.hash(variant)
        var lo = 0, hi = variantHashes.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if variantHashes[mid] < h { lo = mid + 1 } else { hi = mid }
        }
        guard lo < variantHashes.count, variantHashes[lo] == h else { return [] }
        return postings[Int(offsets[lo]) ..< Int(offsets[lo + 1])]
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

    var wordCount: Int { wordList.count }
    var deleteIndexCount: Int { variantHashes.count }

    func contains(_ word: String) -> Bool { wordIndex[word.lowercased()] != nil }

    /// Build the English engine from the bundled `unigrams_en.txt` frequency
    /// list (same file `NextWordEngine.english()` uses). Returns nil if the
    /// resource is missing.
    static func english(in bundle: Bundle = .main) -> SymSpellEngine? {
        guard let url = bundle.url(forResource: "unigrams_en", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        // maxEditDistance 1 keeps the index small for 50k words (2 edits
        // roughly doubles the delete variants).
        // 2-mistake typos fall back to UITextChecker in AutocorrectEngine.
        // CI enforces this via SymSpellBenchmarkTests.shippedConfigFitsBudget.
        let engine = SymSpellEngine(maxEditDistance: 1, prefixLength: 7)
        engine.load(unigramsText: text)
        return engine
    }

    // MARK: - Lookup

    /// Correction candidates for `input`, sorted by (edit distance, frequency).
    /// Returns [] when the input is a known word (distance 0) — same contract
    /// as `AutocorrectEngine`: don't correct real words.
    func lookup(_ input: String, limit: Int = 8) -> [Candidate] {
        let typed = input.lowercased()
        guard !typed.isEmpty, wordIndex[typed] == nil else { return [] }

        var seen = Set<Int32>()
        var results: [Candidate] = []
        func consider(_ i: Int32) {
            guard seen.insert(i).inserted else { return }
            let word = wordList[Int(i)]
            let d = editDistance(typed, word, max: maxEditDistance)
            if d <= maxEditDistance {
                results.append(Candidate(word: word, distance: d, count: Int(counts[Int(i)])))
            }
        }
        for variant in deleteVariants(of: typed, includeSelf: true) {
            // The variant may itself be a dictionary word (typo = insertion,
            // e.g. "wants" -> "want") — the delete index excludes self-entries,
            // so check the dictionary directly too.
            if let i = wordIndex[variant] { consider(i) }
            for i in postingsFor(variant) { consider(i) }
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

    /// Optimal-string-alignment distance (Levenshtein + adjacent swaps count
    /// as 1, so "teh" -> "the" is 1 edit) with an early-exit band; returns
    /// max+1 when exceeded. (Unweighted on purpose — QWERTY-weighted ranking
    /// happens afterwards in `AutocorrectEngine`.)
    func editDistance(_ a: String, _ b: String, max maxD: Int) -> Int {
        let s = Array(a), t = Array(b)
        if abs(s.count - t.count) > maxD { return maxD + 1 }
        if s.isEmpty { return t.count }
        if t.isEmpty { return s.count }
        var prev2 = [Int](repeating: 0, count: t.count + 1)
        var prev = Array(0...t.count)
        var cur = [Int](repeating: 0, count: t.count + 1)
        var prevRowMin = 0
        for i in 1...s.count {
            cur[0] = i
            var rowMin = cur[0]
            for j in 1...t.count {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                cur[j] = Swift.min(prev[j - 1] + cost, prev[j] + 1, cur[j - 1] + 1)
                if i > 1, j > 1, s[i - 1] == t[j - 2], s[i - 2] == t[j - 1] {
                    cur[j] = Swift.min(cur[j], prev2[j - 2] + 1)
                }
                rowMin = Swift.min(rowMin, cur[j])
            }
            // A swap can reach back two rows, so bail only when both are over.
            if rowMin > maxD && prevRowMin > maxD { return maxD + 1 }
            prevRowMin = rowMin
            (prev2, prev, cur) = (prev, cur, prev2)
        }
        return Swift.min(prev[t.count], maxD + 1)
    }
}
