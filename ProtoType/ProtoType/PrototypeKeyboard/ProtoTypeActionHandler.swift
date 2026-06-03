import KeyboardKit
import UIKit

final class ProtoTypeActionHandler: KeyboardAction.StandardActionHandler {

    var kbState: KeyboardState!
    var predictionEngine: PredictionEngine!
    var getLexicon: (() -> [String: String])!

    private var liveTranslateTask: Task<Void, Never>?
    private lazy var haptics = UIImpactFeedbackGenerator(style: .light)

    override func action(
        for gesture: Keyboard.Gesture,
        on action: KeyboardAction
    ) -> KeyboardAction.GestureAction? {
        let standard = super.action(for: gesture, on: action)

        switch (gesture, action) {
        case (.release, .space):
            return { [weak self] _ in
                guard let self else { return }
                self.handleSpace()
                self.resyncKeyboardCase()
                self.triggerHaptic()
            }

        case (.release, .character(let char)):
            return { [weak self] controller in
                standard?(controller)
                guard let self else { return }
                self.triggerHaptic()
                let isLetter = char.count == 1 && (char.first?.isLetter ?? false)
                if isLetter {
                    self.kbState.currentPartial.append(char.lowercased())
                    self.updateLivePredictions()
                } else {
                    self.applySmartPunctuation(for: char)
                    self.kbState.currentPartial = ""
                    self.kbState.predictions = self.predictionEngine.nextWords(after: self.lastContextWord())
                }
                self.resyncKeyboardCase()
            }

        case (.release, .backspace):
            return { [weak self] controller in
                standard?(controller)
                guard let self else { return }
                self.triggerHaptic()
                // Re-derive the current word from the live document so editing back
                // into a previously finished word treats the whole word as current.
                self.kbState.currentPartial = self.partialBeforeCursor()
                self.updateLivePredictions()
                self.resyncKeyboardCase()
            }

        default:
            return standard
        }
    }

    // MARK: - Live (pre-space) predictions + translation

    private func updateLivePredictions() {
        let partial = kbState.currentPartial
        guard !partial.isEmpty else {
            liveTranslateTask?.cancel()
            kbState.predictions = predictionEngine.nextWords(after: lastContextWord())
            return
        }

        let completions = predictionEngine.predictions(for: partial)
        let hasCompletion = completions.contains { !$0.source.isEmpty }

        if hasCompletion {
            setTranslationLayout(partial: partial, completions: completions)
            return
        }

        // No completion: the partial may be a genuine typo -> spelling-takeover layout.
        let lexicon = Set(getLexicon().keys)
        let guesses = AutocorrectService.suggestions(
            word: partial,
            language: currentNativeLanguage(),
            limit: 2,
            lexicon: lexicon
        )
        if !guesses.isEmpty {
            liveTranslateTask?.cancel()
            var chips: [Prediction] = [
                Prediction(
                    source: partial,
                    translation: predictionEngine.translation(for: partial) ?? "",
                    highlighted: false,
                    isLoading: false
                )
            ]
            for (i, guess) in guesses.enumerated() {
                chips.append(Prediction(
                    source: guess,
                    translation: predictionEngine.translation(for: guess) ?? "",
                    highlighted: i == 0,
                    isLoading: false
                ))
            }
            while chips.count < 3 { chips.append(.empty) }
            kbState.predictions = chips
            return
        }

        // Fallback: just the live word chip (no completions, not a typo).
        setTranslationLayout(partial: partial, completions: [])
    }

    private func setTranslationLayout(partial: String, completions: [Prediction]) {
        let localHit = predictionEngine.translation(for: partial) ?? ""
        let chip0 = Prediction(
            source: partial,
            translation: localHit,
            highlighted: true,
            isLoading: localHit.isEmpty
        )
        var combined: [Prediction] = [chip0]
        combined.append(contentsOf: completions.filter { !$0.source.isEmpty }.prefix(2))
        while combined.count < 3 { combined.append(.empty) }
        kbState.predictions = combined

        if localHit.isEmpty {
            startLiveTranslate(for: partial)
        } else {
            liveTranslateTask?.cancel()
        }
    }

    private func startLiveTranslate(for partial: String) {
        liveTranslateTask?.cancel()
        let from = currentNativeLanguage()
        let to = currentTargetLanguage()
        liveTranslateTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            // Live lookups stay on-device (local dict + Apple); no network on fragments.
            let result = await TranslationService.shared.translate(word: partial, from: from, to: to, allowRemote: false)
            if Task.isCancelled { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard self.kbState.currentPartial == partial,
                      !self.kbState.predictions.isEmpty,
                      self.kbState.predictions[0].source == partial else { return }
                let clean = (result == "—") ? "" : result
                guard !clean.isEmpty else { return }
                self.kbState.predictions[0] = Prediction(
                    source: partial,
                    translation: clean,
                    highlighted: self.kbState.predictions[0].highlighted,
                    isLoading: false
                )
            }
        }
    }

    // MARK: - Space handling

    private func handleSpace() {
        liveTranslateTask?.cancel()
        let raw = kbState.currentPartial
        let cleaned = raw.lowercased().trimmingCharacters(in: .punctuationCharacters)
        let proxy = keyboardContext.textDocumentProxy

        if cleaned.isEmpty {
            let before = proxy.documentContextBeforeInput ?? ""
            // Double-space -> ". " (only when the text ends in a single space after a word char).
            if before.hasSuffix(" "), !before.hasSuffix("  "),
               let prev = before.dropLast().last, prev.isLetter || prev.isNumber {
                proxy.deleteBackward()
                proxy.insertText(". ")
                kbState.currentPartial = ""
                kbState.predictions = predictionEngine.nextWords(after: lastContextWord())
                return
            }
            // Avoid stacking duplicate spaces.
            if before.hasSuffix(" ") {
                kbState.currentPartial = ""
                return
            }
        }

        if !cleaned.isEmpty, let expansion = getLexicon()[cleaned] {
            for _ in 0..<raw.count { proxy.deleteBackward() }
            proxy.insertText(expansion + " ")
            kbState.currentPartial = ""
            kbState.predictions = predictionEngine.nextWords(after: lastContextWord())
            return
        }

        var finalWord = cleaned
        if !cleaned.isEmpty,
           let correction = AutocorrectService.correct(word: cleaned, language: currentNativeLanguage(), lexicon: Set(getLexicon().keys)),
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
            highlighted: false,
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
                            highlighted: false,
                            isLoading: false
                        )
                        kbState.predictions = current
                    }
                }
            }
        }
    }

    // MARK: - Smart punctuation (quotes & dashes)

    private func applySmartPunctuation(for char: String) {
        guard char.count == 1, let c = char.first else { return }
        let proxy = keyboardContext.textDocumentProxy
        let before = proxy.documentContextBeforeInput ?? ""

        if c == "'" || c == "\"" {
            guard proxy.smartQuotesType != .no else { return }
            let preceding = before.dropLast().last
            let opensQuote = preceding == nil
                || (preceding?.isWhitespace ?? false)
                || (preceding.map { "([{".contains($0) } ?? false)
            let replacement: String
            if c == "'" {
                replacement = opensQuote ? "\u{2018}" : "\u{2019}"
            } else {
                replacement = opensQuote ? "\u{201C}" : "\u{201D}"
            }
            proxy.deleteBackward()
            proxy.insertText(replacement)
            return
        }

        if c == "-" {
            guard proxy.smartDashesType != .no else { return }
            if before.hasSuffix("--") {
                proxy.deleteBackward()
                proxy.deleteBackward()
                proxy.insertText("\u{2014}")
            }
        }
    }

    // MARK: - Capitalization

    /// Force the keyboard case back to the autocapitalization-correct value after
    /// our custom actions, so sentence-start caps are preserved but no stale
    /// "capitalized" shift lingers. Dispatched async so it runs after KeyboardKit's
    /// own post-action case handling and therefore wins for the next keystroke.
    private func resyncKeyboardCase() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let before = self.keyboardContext.textDocumentProxy.documentContextBeforeInput ?? ""
            let atSentenceStart: Bool
            if before.isEmpty || before.hasSuffix("\n") {
                atSentenceStart = true
            } else if before.hasSuffix(" ") {
                let lastNonSpace = before.reversed().first(where: { $0 != " " })
                atSentenceStart = lastNonSpace.map { ".!?".contains($0) } ?? true
            } else {
                atSentenceStart = false
            }
            // .uppercased = shift engaged for the next letter; resync after every
            // keystroke means it releases to .lowercased once past the sentence start.
            self.keyboardContext.keyboardCase = atSentenceStart ? .uppercased : .lowercased
        }
    }

    // MARK: - Haptics

    private func triggerHaptic() {
        guard keyboardContext.hasFullAccess else { return }
        haptics.impactOccurred()
    }

    // MARK: - Helpers

    /// The run of letters immediately before the cursor (the word being edited),
    /// derived from the live document rather than accumulated keystrokes.
    private func partialBeforeCursor() -> String {
        let before = keyboardContext.textDocumentProxy.documentContextBeforeInput ?? ""
        guard let last = before.last, last.isLetter else { return "" }
        var chars: [Character] = []
        for ch in before.reversed() {
            if ch.isLetter { chars.append(ch) } else { break }
        }
        return String(chars.reversed()).lowercased()
    }

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
