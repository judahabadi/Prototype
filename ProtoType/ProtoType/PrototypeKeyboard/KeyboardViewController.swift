import UIKit
import SwiftUI
import KeyboardKit

final class KeyboardViewController: KeyboardInputViewController, KeyboardProxy, UIInputViewAudioFeedback {

    var kbState: KeyboardState!
    var predictionEngine: PredictionEngine!
    private var lexicon: [String: String] = [:]
    /// Held weakly — `services.actionHandler` owns it. Used to re-sync the
    /// current word to the cursor when the selection moves.
    private weak var protoHandler: ProtoTypeActionHandler?

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

        // Drive the shift/case state ourselves (see `applyAutoCase`). KeyboardKit's
        // own auto-capitalization never sees our custom space/punctuation handling
        // (we replace those actions), so it left the shift capitalized into the next
        // word ("The To Car"). Disabling it makes our deterministic rule the sole
        // authority, so the two can't fight over the case.
        state.keyboardContext.settings.isAutocapitalizationEnabled = false

        let handler = ProtoTypeActionHandler(controller: self)
        handler.kbState = kbState
        handler.predictionEngine = predictionEngine
        handler.getLexicon = { [weak self] in self?.lexicon ?? [:] }
        services.actionHandler = handler
        protoHandler = handler

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
        applyAutoCase()
        kbState?.contextSignal += 1
    }

    /// Set the shift/case for the *next* keystroke from the live document context,
    /// using the same rule that cases the suggestion chips. Capitalised at a
    /// sentence start, lowercase mid-sentence — so a word after a space stays lower
    /// case. Leaves a manual caps-lock alone. This is the sole case authority
    /// (KeyboardKit's own auto-capitalization is disabled in `viewDidLoad`).
    private func applyAutoCase() {
        guard !state.keyboardContext.isCapsLocked else { return }
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let upper = Autocap.shouldUppercase(contextBefore: before, type: autocapitalizationType)
        state.keyboardContext.keyboardCase = upper ? .capitalized : .lowercased
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
        applyAutoCase()
        kbState?.contextSignal += 1
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        kbState?.contextSignal += 1
        // When the cursor moves, re-sync the current word for the new position so
        // the suggestion bar reflects where the cursor actually is, and re-derive
        // the case for wherever the cursor now sits.
        protoHandler?.syncToCursor()
        applyAutoCase()
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

/// Single, shared auto-capitalization rule used by both the view controller
/// (to drive KeyboardKit's shift state) and the action handler (to case
/// suggestion chips), so the two can never disagree about what the case
/// should be for a given document context.
enum Autocap {
    static func shouldUppercase(contextBefore: String, type: UITextAutocapitalizationType) -> Bool {
        switch type {
        case .allCharacters:
            return true
        case .none:
            return false
        case .words:
            return contextBefore.isEmpty || (contextBefore.last?.isWhitespace ?? false)
        case .sentences:
            if contextBefore.isEmpty || contextBefore.hasSuffix("\n") { return true }
            if contextBefore.hasSuffix(" ") {
                let lastNonSpace = contextBefore.reversed().first(where: { $0 != " " })
                return lastNonSpace.map { ".!?".contains($0) } ?? true
            }
            return false
        @unknown default:
            return false
        }
    }
}
