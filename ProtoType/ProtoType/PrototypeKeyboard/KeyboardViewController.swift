import UIKit
import SwiftUI
import KeyboardKit

/// Native KeyboardKit keyboard. KeyboardKit owns all typing, capitalization, and
/// autocorrect; we only plug in a custom autocomplete service (Norvig + offline
/// translation) so the bar shows our suggestions. There is no custom action
/// handler — that's what kept breaking capitalization.
final class KeyboardViewController: KeyboardInputViewController, UIInputViewAudioFeedback {

    var kbState: KeyboardState!
    private var nextWordEngine = NextWordEngine()
    private let translationEngine = TranslationEngine()
    private var didLoadNextWord = false

    override func viewDidLoad() {
        // Initialize state before super, since super may trigger view setup.
        let defaults = AppGroup.defaults
        defaults.set(true, forKey: "keyboardDidLoad")
        let native = Language(rawValue: defaults.string(forKey: AppGroup.nativeKey) ?? "") ?? .english
        var target = Language(rawValue: defaults.string(forKey: AppGroup.targetKey) ?? "") ?? .spanish
        if target == native { target = (native == .english) ? .spanish : .english }
        kbState = KeyboardState(native: native, target: target)

        super.viewDidLoad()

        state.keyboardContext.locale = Locale(identifier: native.isoCode)

        // Make sure autocomplete + the toolbar are on. These settings persist in
        // UserDefaults, and the previous build wrote `isToolbarEnabled = false`,
        // which kept the QuickType bar hidden even after the rewrite. Force them
        // true so our bar shows and KeyboardKit runs our suggestion service.
        state.autocompleteContext.settings.isAutocompleteEnabled = true
        state.autocompleteContext.settings.isToolbarEnabled = true
        state.autocompleteContext.settings.isAutocorrectEnabled = true

        loadEngines()
        installAutocompleteService()
    }

    /// (Re)load the suggestion + translation data. Next-word data is the bundled
    /// English Norvig set (loaded once); translation depends on the language pair.
    private func loadEngines() {
        if !didLoadNextWord, let english = NextWordEngine.english() {
            nextWordEngine = english
            didLoadNextWord = true
        }
        translationEngine.load(from: kbState.nativeLanguage, to: kbState.targetLanguage)
    }

    /// Install our Norvig-backed autocomplete service. KeyboardKit calls it on
    /// every text change and applies autocorrect suggestions on space.
    private func installAutocompleteService() {
        services.autocompleteService = NorvigAutocompleteService(
            locale: Locale(identifier: kbState.nativeLanguage.isoCode),
            nextWord: nextWordEngine,
            translation: translationEngine,
            language: { [weak self] in self?.kbState.nativeLanguage ?? .english }
        )
    }

    /// Called from the language picker when the pair changes.
    func reloadForLanguageChange() {
        state.keyboardContext.locale = Locale(identifier: kbState.nativeLanguage.isoCode)
        loadEngines()
        installAutocompleteService()
    }

    override func viewWillSetupKeyboardView() {
        setupKeyboardView { controller in
            ProtoTypeKeyboardView(
                state: self.kbState,
                services: controller.services,
                autocompleteContext: controller.state.autocompleteContext,
                reloadEngines: { [weak self] in self?.reloadForLanguageChange() }
            )
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        translationEngine.evict()
    }

    // MARK: - UIInputViewAudioFeedback

    func playInputClick() { UIDevice.current.playInputClick() }
    var enableInputClicksWhenVisible: Bool { true }
}
