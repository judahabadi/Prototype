import UIKit
import SwiftUI
import KeyboardKit

/// Native KeyboardKit keyboard. KeyboardKit owns all typing, capitalization, and
/// autocorrect; we only plug in a custom autocomplete service (our word
/// suggestions) so the bar shows our suggestions. Translation glosses come from
/// Apple's Translation framework via `AppleTranslator`, wired up in the SwiftUI
/// view. There is no custom action handler — that's what kept breaking
/// capitalization.
final class KeyboardViewController: KeyboardInputViewController, UIInputViewAudioFeedback {

    var kbState: KeyboardState!
    private var nextWordEngine = NextWordEngine()
    private var didLoadNextWord = false

    override func viewDidLoad() {
        // Initialize state before super, since super may trigger view setup.
        AppGroup.defaults.set(true, forKey: "keyboardDidLoad")
        let langs = storedLanguages()
        kbState = KeyboardState(native: langs.native, target: langs.target)

        super.viewDidLoad()

        state.keyboardContext.locale = Locale(identifier: langs.native.isoCode)

        // Make sure autocomplete + the toolbar are on. These settings persist in
        // UserDefaults, and the previous build wrote `isToolbarEnabled = false`,
        // which kept the QuickType bar hidden even after the rewrite. Force them
        // true so our bar shows and KeyboardKit runs our suggestion service.
        state.autocompleteContext.settings.isAutocompleteEnabled = true
        state.autocompleteContext.settings.isToolbarEnabled = true
        state.autocompleteContext.settings.isAutocorrectEnabled = true

        applyFeedbackSettings()
        loadEngines()
        installAutocompleteService()
    }

    /// Haptics (default on) and key clicks (default off) are user settings in
    /// the host app, shared via the App Group.
    private func applyFeedbackSettings() {
        let defaults = AppGroup.defaults
        let haptics = defaults.object(forKey: AppGroup.hapticsKey) == nil
            ? true
            : defaults.bool(forKey: AppGroup.hapticsKey)
        state.feedbackContext.settings.isHapticFeedbackEnabled = haptics
        state.feedbackContext.settings.isAudioFeedbackEnabled = defaults.bool(forKey: AppGroup.clicksKey)
    }

    /// Load the bundled English next-word set (once). Translation no longer
    /// depends on bundled data — it comes from Apple's on-device model.
    private func loadEngines() {
        if !didLoadNextWord, let english = NextWordEngine.english() {
            nextWordEngine = english
            didLoadNextWord = true
        }
    }

    /// Install our autocomplete service. KeyboardKit calls it on
    /// every text change and applies autocorrect suggestions on space.
    private func installAutocompleteService() {
        services.autocompleteService = SuggestionService(
            locale: Locale(identifier: kbState.nativeLanguage.isoCode),
            nextWord: nextWordEngine,
            language: { [weak self] in self?.kbState.nativeLanguage ?? .english }
        )
    }

    /// Reload engines + locale for the current language pair.
    func reloadForLanguageChange() {
        state.keyboardContext.locale = Locale(identifier: kbState.nativeLanguage.isoCode)
        loadEngines()
        installAutocompleteService()
    }

    /// The language pair the user selected in the app (stored in the App Group).
    private func storedLanguages() -> (native: Language, target: Language) {
        let defaults = AppGroup.defaults
        let native = Language(rawValue: defaults.string(forKey: AppGroup.nativeKey) ?? "") ?? .english
        var target = Language(rawValue: defaults.string(forKey: AppGroup.targetKey) ?? "") ?? .spanish
        if target == native { target = (native == .english) ? .spanish : .english }
        return (native, target)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The user picks the language pair in the app; re-read it each time the
        // keyboard appears and reload if it changed (the extension may stay in
        // memory across appearances).
        let langs = storedLanguages()
        if langs.native != kbState.nativeLanguage || langs.target != kbState.targetLanguage {
            kbState.nativeLanguage = langs.native
            kbState.targetLanguage = langs.target
            reloadForLanguageChange()
        }
        applyFeedbackSettings()
    }

    override func viewWillSetupKeyboardView() {
        setupKeyboardView { controller in
            ProtoTypeKeyboardView(
                state: self.kbState,
                services: controller.services,
                autocompleteContext: controller.state.autocompleteContext
            )
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        AppleTranslator.shared.evict()
    }

    // MARK: - UIInputViewAudioFeedback

    func playInputClick() { UIDevice.current.playInputClick() }
    var enableInputClicksWhenVisible: Bool { AppGroup.defaults.bool(forKey: AppGroup.clicksKey) }
}
