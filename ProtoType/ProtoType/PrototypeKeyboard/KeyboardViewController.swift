import UIKit
import SwiftUI
import KeyboardKit

final class KeyboardViewController: KeyboardInputViewController, KeyboardProxy, UIInputViewAudioFeedback {

    var kbState: KeyboardState!
    var predictionEngine: PredictionEngine!
    private var lexicon: [String: String] = [:]

    override func viewDidLoad() {
        // Initialize our state before calling super — KK may call viewWillSetupKeyboardView
        // from within super.viewDidLoad(), so kbState/predictionEngine must be ready first.
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

        state.keyboardContext.locale = Locale(identifier: native.isoCode)

        let handler = ProtoTypeActionHandler(controller: self)
        handler.kbState = kbState
        handler.predictionEngine = predictionEngine
        handler.getLexicon = { [weak self] in self?.lexicon ?? [:] }
        services.actionHandler = handler

        reloadLexicon()
    }

    override func viewWillSetupKeyboardView() {
        setupKeyboardView { controller in
            ProtoTypeKeyboardView(
                state: self.kbState,
                proxy: self,
                predictionEngine: self.predictionEngine,
                kkServices: controller.services
            )
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadLexicon()
        syncKeyboardType()
        kbState?.contextSignal += 1
    }

    /// Adapt the layout to numeric field types so number/decimal/phone fields get
    /// the numeric keyboard. Non-numeric types are left to KeyboardKit. Done on
    /// appear only (not per-keystroke) so it never fights the symbols/numbers plane.
    private func syncKeyboardType() {
        switch textDocumentProxy.keyboardType {
        case .numberPad?, .asciiCapableNumberPad?, .decimalPad?, .phonePad?:
            state.keyboardContext.keyboardType = .numberPad
        default:
            break
        }
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
        kbState?.contextSignal += 1
        resyncKeyboardCase()
        // Re-apply on the next runloop tick so it wins even if KeyboardKit adjusts
        // the case later in its own action pipeline.
        DispatchQueue.main.async { [weak self] in self?.resyncKeyboardCase() }
    }

    /// Authoritative auto-capitalization: runs after KeyboardKit's own case sync
    /// (super.textDidChange) so it wins, fixing the erratic mid-stream capitals
    /// while honoring the field's autocapitalization type.
    private func resyncKeyboardCase() {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        switch textDocumentProxy.autocapitalizationType ?? .sentences {
        case .allCharacters:
            state.keyboardContext.keyboardCase = .uppercased
        case .none:
            state.keyboardContext.keyboardCase = .lowercased
        case .words:
            let atWordStart = before.isEmpty || (before.last?.isWhitespace ?? false)
            state.keyboardContext.keyboardCase = atWordStart ? .uppercased : .lowercased
        case .sentences:
            let atSentenceStart: Bool
            if before.isEmpty || before.hasSuffix("\n") {
                atSentenceStart = true
            } else if before.hasSuffix(" ") {
                let lastNonSpace = before.reversed().first(where: { $0 != " " })
                atSentenceStart = lastNonSpace.map { ".!?".contains($0) } ?? true
            } else {
                atSentenceStart = false
            }
            state.keyboardContext.keyboardCase = atSentenceStart ? .uppercased : .lowercased
        @unknown default:
            break
        }
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        kbState?.contextSignal += 1
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
