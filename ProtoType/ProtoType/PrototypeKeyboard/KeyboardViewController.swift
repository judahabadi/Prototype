import UIKit
import SwiftUI
import KeyboardKit

final class KeyboardViewController: KeyboardInputViewController, KeyboardProxy, UIInputViewAudioFeedback {

    // Renamed from 'state' to avoid conflict with KeyboardInputViewController.state
    var kbState: KeyboardState!
    var predictionEngine: PredictionEngine!
    private var lexicon: [String: String] = [:]

    override func viewDidLoad() {
        // Initialize our state BEFORE super — KK calls viewWillSetupKeyboardView() from super.viewDidLoad()
        let defaults = AppGroup.defaults
        defaults.set(true, forKey: "keyboardDidLoad")
        let nativeRaw = defaults.string(forKey: AppGroup.nativeKey) ?? Language.english.rawValue
        let targetRaw = defaults.string(forKey: AppGroup.targetKey) ?? Language.spanish.rawValue
        let native = Language(rawValue: nativeRaw) ?? .english
        var target = Language(rawValue: targetRaw) ?? .spanish
        if target == native {
            target = native == .english ? .spanish : .english
        }

        kbState = KeyboardState(native: native, target: target)
        predictionEngine = PredictionEngine()
        predictionEngine.load(from: native, to: target)
        kbState.predictions = predictionEngine.topPredictions()

        super.viewDidLoad()

        // KK's state is ready after super
        state.keyboardContext.locale = Locale(identifier: native.appleTranslationLocale)

        reloadLexicon()
    }

    override func viewWillSetupKeyboardView() {
        super.viewWillSetupKeyboardView()
        setupKeyboardView { [self] _ in
            ProtoTypeKeyboardView(
                state: kbState,
                proxy: self,
                predictionEngine: predictionEngine
            )
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadLexicon()
        kbState.contextSignal += 1
    }

    private func reloadLexicon() {
        requestSupplementaryLexicon { [weak self] lex in
            var map: [String: String] = [:]
            for entry in lex.entries {
                map[entry.userInput.lowercased()] = entry.documentText
            }
            self?.lexicon = map
        }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        kbState.contextSignal += 1
    }

    // MARK: - KeyboardProxy

    override func insertText(_ text: String) {
        textDocumentProxy.insertText(text)
    }

    override func deleteBackward() {
        textDocumentProxy.deleteBackward()
    }

    func playInputClick() {
        UIDevice.current.playInputClick()
    }

    func textReplacement(for input: String) -> String? {
        lexicon[input.lowercased()]
    }

    override func advanceToNextInputMode() {
        super.advanceToNextInputMode()
    }

    override func dismissKeyboard() {
        super.dismissKeyboard()
    }

    func adjustTextPosition(byCharacterOffset offset: Int) {
        textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
    }

    func showInputModeList() {
        handleInputModeList(from: view, with: UIEvent())
    }

    func requestExpandedContext(completion: @escaping (String, String) -> Void) {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let after = textDocumentProxy.documentContextAfterInput ?? ""
        completion(before, after)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        Task { await TranslationService.shared.evict() }
        predictionEngine?.evict()
    }

    override var needsInputModeSwitchKey: Bool {
        super.needsInputModeSwitchKey
    }

    var documentContextBeforeInput: String? {
        textDocumentProxy.documentContextBeforeInput
    }

    var documentContextAfterInput: String? {
        textDocumentProxy.documentContextAfterInput
    }

    var selectedText: String? {
        textDocumentProxy.selectedText
    }

    var returnKeyType: UIReturnKeyType {
        textDocumentProxy.returnKeyType ?? .default
    }

    var keyboardType: UIKeyboardType {
        textDocumentProxy.keyboardType ?? .default
    }

    var autocapitalizationType: UITextAutocapitalizationType {
        textDocumentProxy.autocapitalizationType ?? .sentences
    }

    var autocorrectionType: UITextAutocorrectionType {
        textDocumentProxy.autocorrectionType ?? .default
    }

    var spellCheckingType: UITextSpellCheckingType {
        textDocumentProxy.spellCheckingType ?? .default
    }

    var isSecureTextEntry: Bool {
        textDocumentProxy.isSecureTextEntry ?? false
    }

    var textContentType: UITextContentType? {
        textDocumentProxy.textContentType
    }

    var enablesReturnKeyAutomatically: Bool {
        textDocumentProxy.enablesReturnKeyAutomatically ?? false
    }

    var keyboardAppearance: UIKeyboardAppearance {
        textDocumentProxy.keyboardAppearance ?? .default
    }

    var enableInputClicksWhenVisible: Bool { true }
}
