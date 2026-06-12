import Testing
import Foundation
@testable import ProtoType

struct SymSpellEngineTests {

    private func engine() -> SymSpellEngine {
        let e = SymSpellEngine(maxEditDistance: 2, prefixLength: 7)
        e.load(unigrams: [
            ("want", 1000), ("wont", 400), ("won't", 350), ("what", 900),
            ("hello", 300), ("help", 200), ("world", 100), ("word", 150),
        ])
        return e
    }

    @Test func knownWordReturnsNoCandidates() {
        #expect(engine().lookup("want").isEmpty)
    }

    @Test func singleEditTypoFindsCandidates() {
        let words = engine().lookup("wnat").map(\.word)
        #expect(words.contains("want"))
        #expect(words.contains("what"))
    }

    @Test func candidatesSortedByDistanceThenFrequency() {
        // "wint" is distance 1 from both "want" and "wont"; "want" is more frequent.
        let result = engine().lookup("wint")
        #expect(result.first?.word == "want")
        #expect(result.first?.distance == 1)
    }

    @Test func twoEditTypoStillFound() {
        #expect(engine().lookup("wrld").map(\.word).contains("world"))
    }

    @Test func distanceBeyondMaxExcluded() {
        // "zzzzzz" is nowhere near anything within 2 edits.
        #expect(engine().lookup("zzzzzz").isEmpty)
    }

    @Test func editDistanceEarlyExit() {
        let e = engine()
        #expect(e.editDistance("abc", "abc", max: 2) == 0)
        #expect(e.editDistance("abc", "abd", max: 2) == 1)
        #expect(e.editDistance("abcdef", "zzzzzz", max: 2) == 3) // capped at max+1
    }

    @Test func caseInsensitive() {
        #expect(engine().lookup("Wnat").map(\.word).contains("want"))
    }
}

/// PLAN.md issue 1 GATE: SymSpell delete-index memory on the real 50k English
/// dictionary. Run this on a REAL DEVICE (memory behaves differently in the
/// simulator) and read the printed footprint numbers.
///
/// Budget: the whole keyboard extension must stay under ~40MB (jetsam reality,
/// not the documented 70MB). If the index alone eats a large share at
/// maxEditDistance 2, drop to prefixLength 5 or maxEditDistance 1 and re-run.
struct SymSpellBenchmarkTests {

    private func loadUnigramsText() throws -> String {
        // Resources are bundled with the keyboard extension; from the test
        // target, walk to the file relative to this source file instead.
        let here = URL(fileURLWithPath: #filePath)
        let url = here
            .deletingLastPathComponent()                    // ProtoTypeTests/
            .deletingLastPathComponent()                    // ProtoType/
            .appendingPathComponent("PrototypeKeyboard/Resources/unigrams_en.txt")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1 }
        return Double(info.phys_footprint) / 1_048_576.0
    }

    @Test func memoryFootprint50kEnglish() throws {
        let text = try loadUnigramsText()

        for (maxEdit, prefix) in [(2, 7), (2, 5), (1, 7)] {
            let before = footprintMB()
            var engine: SymSpellEngine? = SymSpellEngine(maxEditDistance: maxEdit, prefixLength: prefix)
            let start = Date()
            engine!.load(unigramsText: text)
            let buildSeconds = Date().timeIntervalSince(start)
            let after = footprintMB()

            print("""
            [SymSpell benchmark] maxEdit=\(maxEdit) prefixLength=\(prefix): \
            +\(String(format: "%.1f", after - before))MB \
            (\(String(format: "%.0f", before))→\(String(format: "%.0f", after))MB), \
            build \(String(format: "%.2f", buildSeconds))s, \
            \(engine!.wordCount) words, \(engine!.deleteIndexCount) delete keys
            """)

            // Sanity: it still corrects after loading the real dictionary.
            #expect(!engine!.lookup("teh").isEmpty)
            engine = nil   // release before the next configuration
        }
    }

    @Test func lookupLatencyOnRealDictionary() throws {
        let engine = SymSpellEngine(maxEditDistance: 2, prefixLength: 7)
        engine.load(unigramsText: try loadUnigramsText())

        let typos = ["teh", "wnat", "keybaord", "definately", "recieve", "wrld"]
        let start = Date()
        let iterations = 200
        for i in 0..<iterations {
            _ = engine.lookup(typos[i % typos.count])
        }
        let perLookupMs = Date().timeIntervalSince(start) / Double(iterations) * 1000
        print("[SymSpell benchmark] avg lookup \(String(format: "%.2f", perLookupMs))ms")
        // Keystroke budget: must be comfortably under one 60fps frame (~16ms).
        #expect(perLookupMs < 16)
    }
}
