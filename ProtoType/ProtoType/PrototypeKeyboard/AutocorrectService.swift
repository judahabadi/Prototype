import Foundation
import UIKit

struct AutocorrectService {
    static func correct(word: String, language: Language) -> String? {
        guard !word.isEmpty else { return nil }
        let checker = UITextChecker()
        let range = NSRange(location: 0, length: word.utf16.count)
        let misspelled = checker.rangeOfMisspelledWord(
            in: word,
            range: range,
            startingAt: 0,
            wrap: false,
            language: language.isoCode
        )
        if misspelled.location == NSNotFound { return nil }
        let guesses = checker.guesses(
            forWordRange: misspelled,
            in: word,
            language: language.isoCode
        ) ?? []
        return guesses.first
    }
}
