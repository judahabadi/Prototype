import Foundation
import Observation

@Observable
final class KeyboardState {
    var nativeLanguage: Language
    var targetLanguage: Language
    var sourceWord: String = ""
    var currentTranslation: String = ""
    var predictions: [String] = []
    var isLoadingTranslation: Bool = false
    var showLanguagePicker: Bool = false
    var capsLock: Bool = false
    var shiftOnce: Bool = false
    var isSymbolMode: Bool = false
    var isExtendedSymbols: Bool = false
    var currentPartial: String = ""
    var correctionApplied: String? = nil

    init(native: Language, target: Language) {
        self.nativeLanguage = native
        self.targetLanguage = target
    }
}
