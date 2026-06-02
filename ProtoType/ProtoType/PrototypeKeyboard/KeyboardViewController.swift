import UIKit
import SwiftUI

final class KeyboardViewController: UIInputViewController, KeyboardProxy, UIInputViewAudioFeedback {

    private var kbState: KeyboardState!
    private var predictionEngine: PredictionEngine!
    private var hosting: UIHostingController<ProtoTypeKeyboardView>?
    private var lexicon: [String: String] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()

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

        let keyboardView = ProtoTypeKeyboardView(
            state: kbState,
            proxy: self,
            predictionEngine: predictionEngine
        )
        let host = UIHostingController(rootView: keyboardView)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        self.view.addSubview(host.view)
        host.didMove(toParent: self)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: self.view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])
        hosting = host

        reloadLexicon()
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

    func insertText(_ text: String) {
        textDocumentProxy.insertText(text)
    }

    func deleteBackward() {
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

    override var needsInputModeSwitchKey: Bool { super.needsInputModeSwitchKey }

    var documentContextBeforeInput: String? { textDocumentProxy.documentContextBeforeInput }
    var documentContextAfterInput: String? { textDocumentProxy.documentContextAfterInput }
    var selectedText: String? { textDocumentProxy.selectedText }
    var returnKeyType: UIReturnKeyType { textDocumentProxy.returnKeyType ?? .default }
    var keyboardType: UIKeyboardType { textDocumentProxy.keyboardType ?? .default }
    var autocapitalizationType: UITextAutocapitalizationType { textDocumentProxy.autocapitalizationType ?? .sentences }
    var autocorrectionType: UITextAutocorrectionType { textDocumentProxy.autocorrectionType ?? .default }
    var spellCheckingType: UITextSpellCheckingType { textDocumentProxy.spellCheckingType ?? .default }
    var isSecureTextEntry: Bool { textDocumentProxy.isSecureTextEntry ?? false }
    var textContentType: UITextContentType? { textDocumentProxy.textContentType }
    var enablesReturnKeyAutomatically: Bool { textDocumentProxy.enablesReturnKeyAutomatically ?? false }
    var keyboardAppearance: UIKeyboardAppearance { textDocumentProxy.keyboardAppearance ?? .default }

    var enableInputClicksWhenVisible: Bool { true }
}
