import Foundation
import UIKit

struct AutocorrectService {
    private static let checker = UITextChecker()

    static func correct(word: String, language: Language) -> String? {
        guard !word.isEmpty else { return nil }
        let range = NSRange(location: 0, length: word.utf16.count)
        let misspelled = checker.rangeOfMisspelledWord(
            in: word,
            range: range,
            startingAt: 0,
            wrap: false,
            language: language.isoCode
        )
        guard misspelled.location != NSNotFound else { return nil }
        return checker.guesses(forWordRange: misspelled, in: word, language: language.isoCode)?.first
    }
}
