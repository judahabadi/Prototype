import Foundation
import Observation

@Observable
final class KeyboardState {
    var nativeLanguage: Language
    var targetLanguage: Language
    var predictions: [Prediction] = []
    var showLanguagePicker: Bool = false
    var capsLock: Bool = false
    var shiftOnce: Bool = false
    var isSymbolMode: Bool = false
    var isExtendedSymbols: Bool = false
    var currentPartial: String = ""

    init(native: Language, target: Language) {
        self.nativeLanguage = native
        self.targetLanguage = target
    }
}
