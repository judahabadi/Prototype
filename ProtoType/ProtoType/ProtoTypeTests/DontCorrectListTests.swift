import Testing
@testable import ProtoType

private final class MemoryStore: DontCorrectList.Store {
    var strings: [String: [String]] = [:]
    var dicts: [String: [String: Int]] = [:]
    func stringArray(forKey key: String) -> [String]? { strings[key] }
    func dictionary(forKey key: String) -> [String: Int]? { dicts[key] }
    func set(_ value: Any?, forKey key: String) {
        if let v = value as? [String] { strings[key] = v }
        else if let v = value as? [String: Int] { dicts[key] = v }
    }
}

struct DontCorrectListTests {

    private func list(threshold: Int = 2) -> (DontCorrectList, MemoryStore) {
        let store = MemoryStore()
        return (DontCorrectList(store: store, revertThreshold: threshold), store)
    }

    @Test func addsAfterThresholdReverts() {
        let (l, _) = list(threshold: 2)
        #expect(l.recordRevert(of: "teh") == false)   // 1st
        #expect(l.shouldSkip("teh") == false)
        #expect(l.recordRevert(of: "teh") == true)    // 2nd -> added
        #expect(l.shouldSkip("teh"))
    }

    @Test func caseInsensitive() {
        let (l, _) = list(threshold: 1)
        _ = l.recordRevert(of: "Naomi")
        #expect(l.shouldSkip("naomi"))
        #expect(l.shouldSkip("NAOMI"))
    }

    @Test func alreadyListedDoesNotReAdd() {
        let (l, _) = list(threshold: 1)
        #expect(l.recordRevert(of: "x") == true)
        #expect(l.recordRevert(of: "x") == false)
    }

    @Test func clearEmptiesList() {
        let (l, _) = list(threshold: 1)
        _ = l.recordRevert(of: "x")
        l.clear()
        #expect(l.shouldSkip("x") == false)
    }

    @Test func emptyWordIgnored() {
        let (l, _) = list(threshold: 1)
        #expect(l.recordRevert(of: "") == false)
    }

    @Test func persistsAcrossInstances() {
        let store = MemoryStore()
        let a = DontCorrectList(store: store, revertThreshold: 1)
        _ = a.recordRevert(of: "café")
        let b = DontCorrectList(store: store, revertThreshold: 1)
        #expect(b.shouldSkip("café"))
    }
}
