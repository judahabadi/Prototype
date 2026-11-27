import XCTest
import SwiftUI
import UIKit
@testable import ProtoType

/// Feeds typos through the shipped correction engines in the same priority
/// order as `SuggestionService.midWordSuggestions` (contraction → phrase caps →
/// spell-correct), then renders the resulting bar as a PNG attachment.
/// Complements `KeyboardSimTests`, which drives the real keyboard UI.
final class TypoPipelineTests: XCTestCase {

    private static let symSpell: SymSpellEngine = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("PrototypeKeyboard/Resources/unigrams_en.txt")
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        // Same config as SymSpellEngine.english().
        let engine = SymSpellEngine(maxEditDistance: 1, prefixLength: 7)
        engine.load(unigramsText: text)
        return engine
    }()

    private let contractions = ContractionEngine()
    private let phraseCaps = PhraseCapEngine()
    private lazy var autocorrect = AutocorrectEngine(symSpell: Self.symSpell)

    /// The autocorrect the keyboard would apply on space, or nil.
    private func correction(for word: String) -> String? {
        if let c = contractions.contraction(for: word, language: .english) { return c }
        if let c = phraseCaps.fix(word: word) { return c }
        return autocorrect.suggestions(word: word, language: .english, limit: 1).first
    }

    @MainActor
    func testTypoCorrections() {
        let cases: [(typed: String, expected: String?)] = [
            ("teh", "the"),
            ("dont", "don't"),
            ("im", "I'm"),
            ("i", "I"),
            ("recieve", "receive"),
            ("wrld", nil),        // 2 edits: SymSpell skips it; UITextChecker may catch it
            ("hello", nil),       // real word: leave alone
        ]
        var report: [String] = []
        for c in cases {
            let got = correction(for: c.typed)
            report.append("\(c.typed) -> \(got ?? "(no change)")")
            if let expected = c.expected {
                XCTAssertEqual(got, expected, "\(c.typed)")
            }
            attachBar(typed: c.typed, correction: got)
        }
        let a = XCTAttachment(string: report.joined(separator: "\n"))
        a.name = "typo_pipeline_results.txt"
        a.lifetime = .keepAlways
        add(a)
        XCTAssertNil(correction(for: "hello"), "real words must not be corrected")
    }

    @MainActor
    private func attachBar(typed: String, correction: String?) {
        var suggestions = [BarSuggestion(text: "\u{201C}\(typed)\u{201D}")]
        if let correction { suggestions.append(BarSuggestion(text: correction, isAutocorrect: true)) }
        let bar = ChipToolbar(suggestions: suggestions)
            .frame(width: 393, height: ChipToolbar.barHeight)
            .background(Color(uiColor: .secondarySystemBackground))
        let renderer = ImageRenderer(content: bar)
        renderer.scale = 3
        guard let data = renderer.uiImage?.pngData() else { return }
        let a = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        a.name = "typo_bar_\(typed).png"
        a.lifetime = .keepAlways
        add(a)
    }
}
