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

        // KeyboardKit fully owns auto-capitalization and the typed-letter case.
        // The action handler always delegates `.character`/`.space` to KeyboardKit's
        // standard handler (it never inserts letters itself), so KeyboardKit's
        // "capitalize at a sentence start, lowercase after a mid-sentence space"
        // logic runs correctly. We do NOT disable it and we do NOT drive the case
        // ourselves — that two-writer setup was the old mid-sentence-capital bug.

        // Hide KeyboardKit's own autocomplete toolbar entirely. We render our own
        // QuickType bar above the keyboard, and KK's toolbar reserved a height that
        // changed across keyboard re-entry (small on first load, tall after swapping
        // to another keyboard and back). With it disabled, KK reserves nothing and
        // our bar is the sole, fixed-height bar.
        state.autocompleteContext.settings.isToolbarEnabled = false

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
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        kbState?.contextSignal += 1
        // When the cursor moves, re-sync the current word for the new position so
        // the suggestion bar reflects where the cursor actually is. KeyboardKit
        // owns the shift/case for the new position.
        protoHandler?.syncToCursor()
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
