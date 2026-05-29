import UIKit
import SwiftUI

final class KeyboardViewController: UIInputViewController, KeyboardProxy {
    private var state: KeyboardState!
    private var hosting: UIHostingController<KeyboardView>!
    private var predictionEngine: PredictionEngine!

    override func viewDidLoad() {
        super.viewDidLoad()

        let defaults = AppGroup.defaults
        let nativeRaw = defaults.string(forKey: AppGroup.nativeKey) ?? Language.english.rawValue
        let targetRaw = defaults.string(forKey: AppGroup.targetKey) ?? Language.spanish.rawValue
        let native = Language(rawValue: nativeRaw) ?? .english
        var target = Language(rawValue: targetRaw) ?? .spanish
        if target == native {
            target = native == .english ? .spanish : .english
        }

        state = KeyboardState(native: native, target: target)
        predictionEngine = PredictionEngine()
        predictionEngine.load(from: native, to: target)
        state.predictions = predictionEngine.topPredictions()

        let view = KeyboardView(
            state: state,
            proxy: self,
            predictionEngine: predictionEngine
        )
        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(host)
        self.view.addSubview(host.view)
        host.didMove(toParent: self)
        self.hosting = host

        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: self.view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
    }

    func insertText(_ text: String) {
        textDocumentProxy.insertText(text)
    }

    func deleteBackward() {
        textDocumentProxy.deleteBackward()
    }

    override func advanceToNextInputMode() {
        super.advanceToNextInputMode()
    }

    override func dismissKeyboard() {
        super.dismissKeyboard()
    }

    override var needsInputModeSwitchKey: Bool {
        super.needsInputModeSwitchKey
    }

    var documentContextBeforeInput: String? {
        textDocumentProxy.documentContextBeforeInput
    }

    var returnKeyType: UIReturnKeyType {
        textDocumentProxy.returnKeyType ?? .default
    }
}
