import Testing
@testable import ProtoType

struct ContractionEngineTests {

    private let engine = ContractionEngine()

    @Test func mapsCommonContractions() {
        #expect(engine.contraction(for: "wont", language: .english) == "won't")
        #expect(engine.contraction(for: "cant", language: .english) == "can't")
        #expect(engine.contraction(for: "dont", language: .english) == "don't")
    }

    @Test func preservesLeadingCapital() {
        #expect(engine.contraction(for: "Wont", language: .english) == "Won't")
    }

    @Test func preservesAllCaps() {
        #expect(engine.contraction(for: "WONT", language: .english) == "WON'T")
    }

    @Test func imAlwaysCapitalI() {
        #expect(engine.contraction(for: "im", language: .english) == "I'm")
    }

    @Test func unknownWordReturnsNil() {
        #expect(engine.contraction(for: "hello", language: .english) == nil)
    }

    @Test func nonEnglishHasNoMapYet() {
        #expect(engine.contraction(for: "wont", language: .french) == nil)
    }

    @Test func contextSensitiveFlagged() {
        #expect(engine.isContextSensitive("its"))
        #expect(engine.isContextSensitive("well"))
        #expect(engine.isContextSensitive("dont") == false)
    }
}
