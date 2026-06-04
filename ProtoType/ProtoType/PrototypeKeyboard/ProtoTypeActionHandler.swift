import KeyboardKit
import UIKit

final class ProtoTypeActionHandler: KeyboardAction.StandardActionHandler {

    var kbState: KeyboardState!
    var predictionEngine: PredictionEngine!
    var getLexicon: (() -> [String: String])!

    private var liveTranslateTask: Task<Void, Never>?
    private lazy var haptics = UIImpactFeedbackGenerator(style: .light)

    /// Counts backspace repeat ticks while the key is held, so a long hold can
    /// escalate from character deletion to whole-word deletion (Apple-style).
    private var backspaceRepeats = 0

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
                self.triggerHaptic()
            }

        case (.release, .character(let char)):
            return { [weak self] controller in
                guard let self else { standard?(controller); return }
                let proxy = self.keyboardContext.textDocumentProxy
                // Capture context BEFORE the character is inserted so we can decide
                // the correct case ourselves.
                let contextBefore = proxy.documentContextBeforeInput ?? ""
                standard?(controller)
                self.triggerHaptic()
                let isLetter = char.count == 1 && (char.first?.isLetter ?? false)
                if isLetter, let first = char.first {
                    // Enforce auto-capitalization deterministically: fix the just-typed
                    // letter's case if KeyboardKit's shift state produced the wrong one.
                    let shouldUpper = self.shouldCapitalize(contextBefore: contextBefore)
                    var typed = char
                    if shouldUpper != first.isUppercase {
                        proxy.deleteBackward()
                        typed = shouldUpper ? char.uppercased() : char.lowercased()
                        proxy.insertText(typed)
                    }
                    // Re-derive the current word from the live document (rather than
                    // appending) so it always reflects the actual cursor position —
                    // e.g. after the cursor was moved into a previously typed word.
                    // The document already holds the correctly-cased text.
                    self.kbState.currentPartial = self.partialBeforeCursor()
                    self.updateLivePredictions()
                } else {
                    self.applySmartPunctuation(for: char)
                    self.kbState.currentPartial = ""
                    self.kbState.predictions = self.predictionEngine.nextWords(after: self.lastContextWord())
                }
            }

        case (.press, .backspace):
            // Reset the hold counter at the start of every backspace press so the
            // word-deletion escalation only kicks in on a sustained hold.
            return { [weak self] controller in
                self?.backspaceRepeats = 0
                standard?(controller)
            }

        case (.repeatPress, .backspace):
            // While held, delete characters; after a sustained hold, escalate to
            // deleting a whole word per tick (Apple-style accelerated delete).
            return { [weak self] controller in
                guard let self else { standard?(controller); return }
                self.backspaceRepeats += 1
                if self.backspaceRepeats >= 10 {
                    self.deleteWordBackward()
                } else {
                    standard?(controller)
                }
                self.kbState.currentPartial = self.partialBeforeCursor()
                self.updateLivePredictions()
            }

        case (.release, .backspace):
            return { [weak self] controller in
                standard?(controller)
                guard let self else { return }
                self.backspaceRepeats = 0
                self.triggerHaptic()
                // Re-derive the current word from the live document so editing back
                // into a previously finished word treats the whole word as current.
                self.kbState.currentPartial = self.partialBeforeCursor()
                self.updateLivePredictions()
            }

        default:
            return standard
        }
    }

    /// Delete the whitespace and word immediately before the cursor in one step.
    private func deleteWordBackward() {
        let proxy = keyboardContext.textDocumentProxy
        guard var before = proxy.documentContextBeforeInput, !before.isEmpty else { return }
        while let last = before.last, last == " " {
            proxy.deleteBackward()
            before.removeLast()
        }
        while let last = before.last, !last.isWhitespace {
            proxy.deleteBackward()
            before.removeLast()
        }
    }

    // MARK: - Cursor moves

    /// Re-sync the current word and predictions to the live cursor position.
    /// Called when the cursor moves without typing (e.g. tapping into an earlier
    /// word) so the suggestion bar reflects the word at the cursor instead of
    /// staying on the previously typed word. No-op when the word hasn't changed,
    /// so it stays cheap during ordinary typing (which moves the cursor too).
    func syncToCursor() {
        guard kbState != nil else { return }
        let derived = wordAtCursor()
        guard derived != kbState.currentPartial else { return }
        kbState.currentPartial = derived
        updateLivePredictions()
    }

    /// The whole word the cursor sits in — letters before the cursor plus
    /// letters after it. Unlike `partialBeforeCursor()`, this captures the full
    /// word when the cursor lands in the middle of one (e.g. "hel|lo" -> "hello"),
    /// so a cursor move translates the complete word. Empty if not on a word.
    private func wordAtCursor() -> String {
        let proxy = keyboardContext.textDocumentProxy
        let before = proxy.documentContextBeforeInput ?? ""
        let after = proxy.documentContextAfterInput ?? ""
        var head: [Character] = []
        for ch in before.reversed() {
            if ch.isLetter { head.append(ch) } else { break }
        }
        var tail: [Character] = []
        for ch in after {
            if ch.isLetter { tail.append(ch) } else { break }
        }
        return String(head.reversed()) + String(tail)
    }

    // MARK: - Live (pre-space) predictions + translation

    private func updateLivePredictions() {
        let partial = kbState.currentPartial
        guard !partial.isEmpty else {
            liveTranslateTask?.cancel()
            kbState.predictions = predictionEngine.nextWords(after: lastContextWord())
            return
        }

        // Apple QuickType: if the word being typed is misspelled, show the literal
        // in quotes + the auto-correct default (pill-highlighted) + an alternative.
        let lexicon = Set(getLexicon().keys)
        let guesses = partial.count >= 2
            ? AutocorrectService.suggestions(word: partial, language: currentNativeLanguage(), limit: 2, lexicon: lexicon)
            : []
        if !guesses.isEmpty {
            var chips: [Prediction] = [
                // The literal typed word, shown in quotes (tap = keep my spelling).
                Prediction(source: partial, translation: "", highlighted: false, isLoading: false, quoted: true)
            ]
            for (i, guess) in guesses.enumerated() {
                chips.append(Prediction(
                    source: matchedCase(guess, like: partial),
                    translation: predictionEngine.translation(for: guess) ?? "",
                    highlighted: i == 0,   // top correction gets the pill
                    isLoading: false
                ))
            }
            while chips.count < 3 { chips.append(.empty) }
            kbState.predictions = chips
            translateMissingChips(partial: partial)
            return
        }

        // Not misspelled: live word + translation, plus completions. Completions
        // exclude the typed word itself (UITextChecker returns it as its own first
        // completion, which would duplicate the live chip).
        let completions = predictionEngine.predictions(for: partial)
            .filter { !$0.source.isEmpty && $0.source.lowercased() != partial.lowercased() }

        let chip0 = Prediction(
            source: partial,
            translation: predictionEngine.translation(for: partial) ?? "",
            highlighted: false,
            isLoading: false
        )
        var combined: [Prediction] = [chip0]
        combined.append(contentsOf: completions.prefix(2).map {
            Prediction(source: matchedCase($0.source, like: partial), translation: $0.translation, highlighted: false, isLoading: false)
        })
        while combined.count < 3 { combined.append(.empty) }
        kbState.predictions = combined
        translateMissingChips(partial: partial)
    }

    /// Debounced on-device translation for every visible chip that has no local
    /// translation yet (the typed word and the suggestion/completion chips).
    /// Stays on-device (no network) so live typing never spams the web API.
    private func translateMissingChips(partial: String) {
        liveTranslateTask?.cancel()
        let pending: [(Int, String)] = kbState.predictions.enumerated().compactMap { index, chip in
            (!chip.source.isEmpty && chip.translation.isEmpty) ? (index, chip.source) : nil
        }
        guard !pending.isEmpty else { return }
        let from = currentNativeLanguage()
        let to = currentTargetLanguage()
        liveTranslateTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            for (index, word) in pending {
                let result = await TranslationService.shared.translate(word: word, from: from, to: to, allowRemote: false)
                if Task.isCancelled { return }
                let clean = (result == "—") ? "" : result
                guard !clean.isEmpty else { continue }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard self.kbState.currentPartial == partial,
                          self.kbState.predictions.indices.contains(index),
                          self.kbState.predictions[index].source == word,
                          self.kbState.predictions[index].translation.isEmpty else { return }
                    let c = self.kbState.predictions[index]
                    self.kbState.predictions[index] = Prediction(
                        source: c.source,
                        translation: clean,
                        highlighted: c.highlighted,
                        isLoading: false
                    )
                }
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
            isLoading: false
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

    // MARK: - Haptics

    private func triggerHaptic() {
        guard keyboardContext.hasFullAccess else { return }
        haptics.impactOccurred()
    }

    // MARK: - Helpers

    /// The run of letters immediately before the cursor (the word being edited),
    /// derived from the live document rather than accumulated keystrokes. Case is
    /// preserved so the bar matches the text field.
    private func partialBeforeCursor() -> String {
        let before = keyboardContext.textDocumentProxy.documentContextBeforeInput ?? ""
        guard let last = before.last, last.isLetter else { return "" }
        var chars: [Character] = []
        for ch in before.reversed() {
            if ch.isLetter { chars.append(ch) } else { break }
        }
        return String(chars.reversed())
    }

    /// Whether the letter just typed should be uppercase, per the field's
    /// autocapitalization type and the text before it. Deterministic and
    /// independent of KeyboardKit's shift state.
    private func shouldCapitalize(contextBefore: String) -> Bool {
        switch keyboardContext.textDocumentProxy.autocapitalizationType ?? .sentences {
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

    /// Capitalize `word`'s first letter when the typed word is capitalized, so
    /// suggestion/completion chips visually match what's being typed.
    private func matchedCase(_ word: String, like typed: String) -> String {
        guard let t = typed.first, t.isUppercase,
              let w = word.first, w.isLowercase else { return word }
        return w.uppercased() + word.dropFirst()
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
