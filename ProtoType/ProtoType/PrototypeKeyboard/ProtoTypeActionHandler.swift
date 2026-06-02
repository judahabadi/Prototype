import KeyboardKit
import UIKit

final class ProtoTypeActionHandler: KeyboardAction.StandardActionHandler {

    private let kbState: KeyboardState
    private let predictionEngine: PredictionEngine
    private let getLexicon: () -> [String: String]

    init(
        controller: KeyboardInputViewController,
        kbState: KeyboardState,
        predictionEngine: PredictionEngine,
        getLexicon: @escaping () -> [String: String]
    ) {
        self.kbState = kbState
        self.predictionEngine = predictionEngine
        self.getLexicon = getLexicon
        super.init(controller: controller)
    }

    override func action(
        for gesture: Keyboard.Gesture,
        on action: KeyboardAction
    ) -> KeyboardAction.GestureAction? {
        let standard = super.action(for: gesture, on: action)

        switch (gesture, action) {
        case (.release, .space):
            return { [weak self] _ in self?.handleSpace() }

        case (.release, .character(let char)):
            return { [weak self] controller in
                standard?(controller)
                guard let self else { return }
                let isLetter = char.count == 1 && (char.first?.isLetter ?? false)
                if isLetter {
                    self.kbState.currentPartial.append(char.lowercased())
                    self.kbState.predictions = self.predictionEngine.predictions(for: self.kbState.currentPartial)
                } else {
                    self.kbState.currentPartial = ""
                    self.kbState.predictions = self.predictionEngine.nextWords(after: self.lastContextWord())
                }
            }

        case (.release, .backspace):
            return { [weak self] controller in
                standard?(controller)
                guard let self else { return }
                if !self.kbState.currentPartial.isEmpty { self.kbState.currentPartial.removeLast() }
                self.kbState.predictions = self.kbState.currentPartial.isEmpty
                    ? self.predictionEngine.nextWords(after: self.lastContextWord())
                    : self.predictionEngine.predictions(for: self.kbState.currentPartial)
            }

        default:
            return standard
        }
    }

    // MARK: - Space handling

    private func handleSpace() {
        let raw = kbState.currentPartial
        let cleaned = raw.lowercased().trimmingCharacters(in: .punctuationCharacters)
        let proxy = keyboardContext.textDocumentProxy

        if !cleaned.isEmpty, let expansion = getLexicon()[cleaned] {
            for _ in 0..<raw.count { proxy.deleteBackward() }
            proxy.insertText(expansion + " ")
            kbState.currentPartial = ""
            kbState.predictions = predictionEngine.nextWords(after: lastContextWord())
            return
        }

        var finalWord = cleaned
        if !cleaned.isEmpty,
           let correction = AutocorrectService.correct(word: cleaned, language: currentNativeLanguage()),
           correction.lowercased() != cleaned {
            for _ in 0..<raw.count { proxy.deleteBackward() }
            proxy.insertText(correction)
            finalWord = correction.lowercased()
        }

        proxy.insertText(" ")
        kbState.currentPartial = ""

        guard !finalWord.isEmpty else {
            kbState.predictions = predictionEngine.nextWords(after: lastContextWord())
            return
        }

        let localTranslation = predictionEngine.translation(for: finalWord) ?? ""
        let chip0 = Prediction(
            source: finalWord,
            translation: localTranslation,
            highlighted: true,
            isLoading: localTranslation.isEmpty
        )
        var combined: [Prediction] = [chip0]
        combined.append(contentsOf: freshPredictions(after: finalWord))
        while combined.count < 3 { combined.append(.empty) }
        kbState.predictions = combined

        if localTranslation.isEmpty {
            let from = currentNativeLanguage()
            let to = currentTargetLanguage()
            Task { [weak self] in
                guard let self else { return }
                let result = await TranslationService.shared.translate(word: finalWord, from: from, to: to)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    var current = kbState.predictions
                    if !current.isEmpty, current[0].source == finalWord {
                        current[0] = Prediction(
                            source: finalWord,
                            translation: result == "—" ? "" : result,
                            highlighted: true,
                            isLoading: false
                        )
                        kbState.predictions = current
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func lastContextWord() -> String {
        let before = keyboardContext.textDocumentProxy.documentContextBeforeInput ?? ""
        let trimmed = before.trimmingCharacters(in: .whitespacesAndNewlines)
        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        return trimmed.components(separatedBy: separators).filter { !$0.isEmpty }.last ?? ""
    }

    private func freshPredictions(after word: String) -> [Prediction] {
        let before = (keyboardContext.textDocumentProxy.documentContextBeforeInput ?? "").lowercased()
        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        let recent = Set(before.components(separatedBy: separators).filter { !$0.isEmpty && $0.count > 1 })
        return predictionEngine.nextWords(after: word, limit: 10)
            .filter { !recent.contains($0.source.lowercased()) }
            .prefix(2)
            .map { $0 }
    }

    private func currentNativeLanguage() -> Language { kbState.nativeLanguage }
    private func currentTargetLanguage() -> Language { kbState.targetLanguage }
}
