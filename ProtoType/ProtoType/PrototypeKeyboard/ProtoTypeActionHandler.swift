import KeyboardKit
import Foundation

final class ProtoTypeActionHandler: StandardKeyboardActionHandler {

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

    override func handle(_ gesture: KeyboardGesture, on action: KeyboardAction) {
        guard gesture == .release || gesture == .press else {
            super.handle(gesture, on: action)
            return
        }

        switch action {
        case .space where gesture == .release:
            handleSpace()

        case .character(let char) where gesture == .release:
            super.handle(gesture, on: action)
            let isLetter = char.count == 1 && (char.first?.isLetter ?? false)
            if isLetter {
                kbState.currentPartial.append(char.lowercased())
                kbState.predictions = predictionEngine.predictions(for: kbState.currentPartial)
            } else {
                kbState.currentPartial = ""
                kbState.predictions = predictionEngine.nextWords(after: lastContextWord())
            }

        case .backspace where gesture == .release:
            super.handle(gesture, on: action)
            if !kbState.currentPartial.isEmpty { kbState.currentPartial.removeLast() }
            kbState.predictions = kbState.currentPartial.isEmpty
                ? predictionEngine.nextWords(after: lastContextWord())
                : predictionEngine.predictions(for: kbState.currentPartial)

        default:
            super.handle(gesture, on: action)
        }
    }

    // MARK: - Space handling

    private func handleSpace() {
        let raw = kbState.currentPartial
        let cleaned = raw.lowercased()
            .trimmingCharacters(in: .punctuationCharacters)

        // Text replacement wins over everything
        if !cleaned.isEmpty,
           let expansion = getLexicon()[cleaned] {
            for _ in 0..<raw.count { keyboardController?.textDocumentProxy.deleteBackward() }
            keyboardController?.textDocumentProxy.insertText(expansion + " ")
            kbState.currentPartial = ""
            kbState.predictions = predictionEngine.nextWords(after: lastContextWord())
            return
        }

        // Autocorrect
        var finalWord = cleaned
        if !cleaned.isEmpty,
           let correction = AutocorrectService.correct(word: cleaned, language: currentNativeLanguage()),
           correction.lowercased() != cleaned {
            for _ in 0..<raw.count { keyboardController?.textDocumentProxy.deleteBackward() }
            keyboardController?.textDocumentProxy.insertText(correction)
            finalWord = correction.lowercased()
        }

        // Let KK insert the space
        super.handle(.release, on: .space)

        kbState.currentPartial = ""

        guard !finalWord.isEmpty else {
            kbState.predictions = predictionEngine.nextWords(after: lastContextWord())
            return
        }

        // Build translation chip
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
        let before = keyboardController?.textDocumentProxy.documentContextBeforeInput ?? ""
        let trimmed = before.trimmingCharacters(in: .whitespacesAndNewlines)
        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        return trimmed.components(separatedBy: separators).filter { !$0.isEmpty }.last ?? ""
    }

    private func freshPredictions(after word: String) -> [Prediction] {
        let before = (keyboardController?.textDocumentProxy.documentContextBeforeInput ?? "").lowercased()
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
