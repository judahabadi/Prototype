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

    // completions() binary-searches a separate alphabetically-sorted array
    // (PLAN.md issue 12) instead of scanning `unigrams` — these exercise its
    // boundaries directly.
    @Test func completionsPrefixNotInDictionaryReturnsEmpty() {
        #expect(engine().completions(for: "zzz").isEmpty)
    }

    @Test func completionsAtAlphabeticalUpperBoundary() {
        // "world" alphabetically follows every other loaded word, so this
        // exercises the binary search's upper edge.
        #expect(engine().completions(for: "wor", limit: 1) == ["world"])
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
        // Swapped letters beat an adjacent-key substitution: teh -> the, not ten.
        #expect(e.weightedDistance("teh", "the") < e.weightedDistance("teh", "ten"))
    }

    // PLAN.md issue 1: SymSpell candidates, re-ranked the same way as
    // UITextChecker guesses (keyboard-distance first, frequency to break ties).
    @Test func rerankedCandidatesPrefersAdjacentKeyOverFrequency() {
        let e = AutocorrectEngine()
        let candidates = [
            SymSpellEngine.Candidate(word: "want", distance: 1, count: 1000),
            SymSpellEngine.Candidate(word: "wont", distance: 1, count: 400),
        ]
        // "wint": i->o (wont) is keyboard-adjacent; i->a (want) is far apart.
        // Keyboard distance wins even though "want" is far more frequent.
        #expect(e.rerankedCandidates(candidates, typed: "wint").first == "wont")
    }

    @Test func rerankedCandidatesBreaksTiesByFrequency() {
        let e = AutocorrectEngine()
        let candidates = [
            SymSpellEngine.Candidate(word: "cats", distance: 1, count: 5),
            SymSpellEngine.Candidate(word: "scat", distance: 1, count: 200),
        ]
        // Both are a single insertion away from "cat" — equal weighted
        // distance regardless of QWERTY layout — so frequency breaks the tie.
        #expect(e.rerankedCandidates(candidates, typed: "cat").first == "scat")
    }

    @Test func symSpellSuggestionsUsedForEnglishWhenLoaded() {
        let symSpell = SymSpellEngine(maxEditDistance: 2, prefixLength: 7)
        symSpell.load(unigrams: [("want", 1000), ("wont", 400), ("what", 900)])
        let engine = AutocorrectEngine(symSpell: symSpell)
        // Resolved entirely via SymSpell — never touches UITextChecker, so
        // this is deterministic regardless of the OS dictionary.
        #expect(engine.suggestions(word: "wnat", language: .english).contains("want"))
    }

    @Test func symSpellSkippedForNonEnglishLanguages() {
        let symSpell = SymSpellEngine(maxEditDistance: 2, prefixLength: 7)
        symSpell.load(unigrams: [("want", 1000)])
        let engine = AutocorrectEngine(symSpell: symSpell)
        // Only English has bundled frequency data; other languages must not
        // pull candidates out of the English SymSpell index.
        #expect(engine.suggestions(word: "wnat", language: .spanish).contains("want") == false)
    }

    @Test func noSymSpellEngineFallsBackToDefaultBehavior() {
        // Default init (no SymSpell) must behave exactly as before this change.
        #expect(AutocorrectEngine().suggestions(word: "", language: .english).isEmpty)
    }
}

struct TranslationEngineTests {

    @Test func directLookupIsCaseInsensitive() {
        let e = TranslationEngine()
        e.loadDictionary(["hola": "hello"])
        #expect(e.translation(for: "Hola") == "hello")
    }

    @Test func missingWordReturnsNil() {
        let e = TranslationEngine()
        e.loadDictionary(["hola": "hello"])
        #expect(e.translation(for: "zzz") == nil)
    }
}
