import Testing
@testable import ProtoType

struct NextWordEngineTests {

    private func engine() -> NextWordEngine {
        let e = NextWordEngine()
        e.load(
            unigrams: [("the", 1000), ("hello", 300), ("help", 200), ("world", 100)],
            bigrams: [("i", "want", 50), ("i", "am", 30), ("i", "will", 10)]
        )
        return e
    }

    @Test func bigramPreferredAndOrderedByCount() {
        #expect(engine().nextWords(after: "i", limit: 2) == ["want", "am"])
    }

    @Test func backoffToTopUnigramsWhenNoBigram() {
        #expect(engine().nextWords(after: "zzz", limit: 1) == ["the"])
    }

    @Test func completionsArePrefixMatchedByFrequency() {
        #expect(engine().completions(for: "hel", limit: 2) == ["hello", "help"])
    }

    @Test func completionExcludesExactPartial() {
        #expect(engine().completions(for: "the").contains("the") == false)
    }

    @Test func topKPerHeadIsRespected() {
        let e = NextWordEngine(topKPerHead: 1)
        e.load(unigrams: [("a", 1)], bigrams: [("i", "want", 50), ("i", "am", 30)])
        #expect(e.nextWords(after: "i", limit: 5) == ["want"])
    }

    // ngrams_en.json format: head -> ordered next-word list (no counts).
    // List position must be preserved as the ranking.
    @Test func bigramListAdapterPreservesOrder() {
        let e = NextWordEngine()
        e.load(bigramLists: ["i": ["want", "am", "will"]], unigrams: [("the", 100)])
        #expect(e.nextWords(after: "i", limit: 2) == ["want", "am"])
    }
}

struct AutocorrectEngineTests {

    // "wint" -> "want" (i->a, far apart) vs "wont" (i->o, adjacent keys).
    // Keyboard-distance re-ranking must prefer the adjacent-key correction.
    @Test func prefersAdjacentKeyCorrection() {
        #expect(AutocorrectEngine().reranked(["want", "wont"], typed: "wint").first == "wont")
    }

    @Test func singleGuessIsUnchanged() {
        #expect(AutocorrectEngine().reranked(["want"], typed: "wint") == ["want"])
    }

    @Test func identicalWordHasZeroDistance() {
        #expect(AutocorrectEngine().weightedDistance("hello", "hello") == 0)
    }

    @Test func adjacentSubstitutionCostsLessThanFar() {
        let e = AutocorrectEngine()
        // i->o adjacent should be cheaper than i->a (far).
        #expect(e.weightedDistance("wint", "wont") < e.weightedDistance("wint", "want"))
    }
}
