import Foundation
import Observation

/// Minimal keyboard state. KeyboardKit owns typing, case, and the autocomplete
/// suggestions now, so this only holds the language selection and the picker flag.
@Observable
final class KeyboardState {
    var nativeLanguage: Language
    var targetLanguage: Language
    var showLanguagePicker: Bool = false

    init(native: Language, target: Language) {
        self.nativeLanguage = native
        self.targetLanguage = target
    }
}
