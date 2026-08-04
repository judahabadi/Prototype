import Testing
@testable import ProtoType

struct PhraseCapEngineTests {

    private let engine = PhraseCapEngine()

    @Test func standaloneIBecomesCapital() {
        #expect(engine.fix(word: "i") == "I")
    }

    @Test func singleProperNoun() {
        #expect(engine.fix(word: "paris") == "Paris")
        #expect(engine.fix(word: "monday") == "Monday")
    }

    @Test func phraseCapitalizesTogether() {
        let fix = engine.fix(forTrailing: ["the", "world", "cup"])
        #expect(fix?.wordCount == 2)
        #expect(fix?.replacement == "World Cup")
    }

    @Test func wordsAloneNotCapitalized() {
        // "world" and "cup" alone are common nouns — no fix.
        #expect(engine.fix(word: "world") == nil)
        #expect(engine.fix(word: "cup") == nil)
    }

    @Test func longestPhraseWins() {
        let fix = engine.fix(forTrailing: ["visit", "new", "york", "city"])
        #expect(fix?.wordCount == 3)
        #expect(fix?.replacement == "New York City")
    }

    @Test func respectsIntentionalCasing() {
        // User already typed it their way — never fight it.
        #expect(engine.fix(word: "Paris") == nil)
        #expect(engine.fix(forTrailing: ["World", "cup"]) == nil)
    }

    @Test func brandCasing() {
        #expect(engine.fix(word: "iphone") == "iPhone")
        #expect(engine.fix(word: "youtube") == "YouTube")
    }

    @Test func mayNotCapitalized() {
        // Deliberately excluded: "may" is usually the verb.
        #expect(engine.fix(word: "may") == nil)
    }

    @Test func unknownWordsUntouched() {
        #expect(engine.fix(word: "hello") == nil)
        #expect(engine.fix(forTrailing: ["just", "some", "words"]) == nil)
    }

    @Test func customEntriesLoadable() {
        var e = PhraseCapEngine(entries: ["mount fuji": "Mount Fuji"])
        #expect(e.fix(forTrailing: ["mount", "fuji"])?.replacement == "Mount Fuji")
        e.load(entries: ["rio": "Rio"])
        #expect(e.fix(word: "rio") == "Rio")
        #expect(e.fix(forTrailing: ["mount", "fuji"]) == nil)
    }
}
