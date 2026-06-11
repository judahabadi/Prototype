import Foundation
import Observation

@Observable
final class AppState {
    private(set) var keyboardHasLoaded: Bool = AppGroup.defaults.bool(forKey: "keyboardDidLoad")

    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    var nativeLanguage: Language {
        get { Language(rawValue: AppGroup.defaults.string(forKey: AppGroup.nativeKey) ?? "") ?? .english }
        set { AppGroup.defaults.set(newValue.rawValue, forKey: AppGroup.nativeKey) }
    }

    var targetLanguage: Language {
        get { Language(rawValue: AppGroup.defaults.string(forKey: AppGroup.targetKey) ?? "") ?? .spanish }
        set { AppGroup.defaults.set(newValue.rawValue, forKey: AppGroup.targetKey) }
    }

    var hapticFeedback: Bool {
        get { AppGroup.defaults.object(forKey: AppGroup.hapticsKey) == nil
              ? true
              : AppGroup.defaults.bool(forKey: AppGroup.hapticsKey) }
        set { AppGroup.defaults.set(newValue, forKey: AppGroup.hapticsKey) }
    }

    var keyboardClicks: Bool {
        get { AppGroup.defaults.bool(forKey: AppGroup.clicksKey) }
        set { AppGroup.defaults.set(newValue, forKey: AppGroup.clicksKey) }
    }

    func refreshKeyboardStatus() {
        keyboardHasLoaded = AppGroup.defaults.bool(forKey: "keyboardDidLoad")
    }

    func swapLanguages() {
        let old = nativeLanguage
        nativeLanguage = targetLanguage
        targetLanguage = old
    }
}
