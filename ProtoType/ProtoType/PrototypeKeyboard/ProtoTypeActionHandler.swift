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
                // Let KeyboardKit insert the character and apply its own native
                // auto-capitalization — we don't override the typed letter's case.
                standard?(controller)
                self.triggerHaptic()
                let isLetter = char.count == 1 && (char.first?.isLetter ?? false)
                if isLetter {
                    // Re-derive the current word from the live document so it always
                    // reflects the actual cursor position (e.g. after moving the
                    // cursor into a previously typed word).
                    self.kbState.currentPartial = self.partialBeforeCursor()
                    self.updateLivePredictions()
                } else {
                    self.applySmartPunctuation(for: char)
                    self.kbState.currentPartial = ""
                    self.refreshNextWordPredictions()
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
            refreshNextWordPredictions()
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
                let src = matchedCase(guess, like: partial)
                let trans = predictionEngine.translation(for: guess) ?? ""
                chips.append(Prediction(
                    source: src,
                    translation: trans.isEmpty ? "" : matchTranslationCase(trans, toSource: src),
                    highlighted: i == 0,   // top correction gets the pill
                    isLoading: false
                ))
            }
            kbState.predictions = carryOverTranslations(padToThree(chips, upper: partial.first?.isUppercase ?? false))
            translateMissingChips(partial: partial)
            return
        }

        // Not misspelled: live word + translation, plus completions. Completions
        // exclude the typed word itself (UITextChecker returns it as its own first
        // completion, which would duplicate the live chip).
        let completions = predictionEngine.predictions(for: partial)
            .filter { !$0.source.isEmpty && $0.source.lowercased() != partial.lowercased() }

        let chip0Trans = predictionEngine.translation(for: partial) ?? ""
        let chip0 = Prediction(
            source: partial,
            translation: chip0Trans.isEmpty ? "" : matchTranslationCase(chip0Trans, toSource: partial),
            highlighted: false,
            isLoading: false
        )
        var combined: [Prediction] = [chip0]
        combined.append(contentsOf: completions.prefix(2).map {
            let src = matchedCase($0.source, like: partial)
            return Prediction(source: src, translation: $0.translation.isEmpty ? "" : matchTranslationCase($0.translation, toSource: src), highlighted: false, isLoading: false)
        })
        kbState.predictions = carryOverTranslations(padToThree(combined, upper: partial.first?.isUppercase ?? false))
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
                        translation: self.machineCased(clean, toSource: c.source),
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
                refreshNextWordPredictions()
                return
            }
            // Avoid stacking duplicate spaces.
            if before.hasSuffix(" ") {
                kbState.currentPartial = ""
                refreshNextWordPredictions()
                return
            }
        }

        if !cleaned.isEmpty, let expansion = getLexicon()[cleaned] {
            for _ in 0..<raw.count { proxy.deleteBackward() }
            proxy.insertText(expansion + " ")
            kbState.currentPartial = ""
            refreshNextWordPredictions()
            return
        }

        // Whether this word sits at a sentence start, judged from the text before
        // the word itself — used to keep an autocorrection's case in line with the
        // sentence (UITextChecker often returns a Capitalized guess that would
        // otherwise capitalize a mid-sentence word).
        let wantUpper = shouldCapitalize(contextBefore: String((proxy.documentContextBeforeInput ?? "").dropLast(raw.count)))

        var finalWord = cleaned
        var insertedWord = raw            // the word as it now reads in the document
        if currentNativeLanguage().isoCode == "en", let contraction = Self.englishContractions[cleaned] {
            // Apple-style contraction fix: ill -> I'll, dont -> don't, youre -> you're.
            // "I" contractions stay capital-I; the rest follow the sentence position.
            let apostrophe = proxy.smartQuotesType == .no ? "'" : "\u{2019}"
            let cased = contraction.hasPrefix("I'") ? contraction : firstLetterCased(contraction, uppercase: wantUpper)
            insertedWord = cased.replacingOccurrences(of: "'", with: apostrophe)
            for _ in 0..<raw.count { proxy.deleteBackward() }
            proxy.insertText(insertedWord)
            finalWord = contraction.lowercased()
        } else if !cleaned.isEmpty,
           let correction = AutocorrectService.correct(word: cleaned, language: currentNativeLanguage(), lexicon: Set(getLexicon().keys)),
           correction.lowercased() != cleaned {
            insertedWord = firstLetterCased(correction, uppercase: wantUpper)
            for _ in 0..<raw.count { proxy.deleteBackward() }
            proxy.insertText(insertedWord)
            finalWord = correction.lowercased()
        } else if currentNativeLanguage().isoCode == "en", isEnglishI(cleaned),
                  let f = raw.first, f.isLowercase {
            // Auto-capitalize the English pronoun "I" and its contractions ("i'm").
            insertedWord = f.uppercased() + raw.dropFirst()
            for _ in 0..<raw.count { proxy.deleteBackward() }
            proxy.insertText(insertedWord)
        }

        proxy.insertText(" ")
        kbState.currentPartial = ""

        guard !finalWord.isEmpty else {
            refreshNextWordPredictions()
            return
        }

        // Learn words the user types often so they stop being autocorrected.
        AutocorrectService.note(typedWord: insertedWord)

        let localTranslation = predictionEngine.translation(for: finalWord) ?? ""
        let chip0 = Prediction(
            source: insertedWord,
            translation: localTranslation.isEmpty ? "" : matchTranslationCase(localTranslation, toSource: insertedWord),
            highlighted: false,
            isLoading: false
        )
        var combined: [Prediction] = [chip0]
        combined.append(contentsOf: casedForCursor(freshPredictions(after: finalWord)))
        let nextUpper = shouldCapitalize(contextBefore: proxy.documentContextBeforeInput ?? "")
        kbState.predictions = carryOverTranslations(padToThree(combined, upper: nextUpper))

        // Fill missing translations on-device so next-word chips don't show bare
        // native words with no translation.
        translateMissingChips(partial: "")

        if localTranslation.isEmpty {
            let from = currentNativeLanguage()
            let to = currentTargetLanguage()
            Task { [weak self] in
                guard let self else { return }
                let result = await TranslationService.shared.translate(word: finalWord, from: from, to: to)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    var current = kbState.predictions
                    if !current.isEmpty, current[0].source == insertedWord {
                        current[0] = Prediction(
                            source: insertedWord,
                            translation: result == "—" ? "" : self.machineCased(result, toSource: insertedWord),
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

    /// Whether a word at the given context should be capitalized, per the field's
    /// autocapitalization type. Shares the exact rule that drives the shift state
    /// (`Autocap`) so chip casing and the keyboard case never disagree.
    private func shouldCapitalize(contextBefore: String) -> Bool {
        Autocap.shouldUppercase(
            contextBefore: contextBefore,
            type: keyboardContext.textDocumentProxy.autocapitalizationType ?? .sentences
        )
    }

    /// Rebuild the bar with next-word suggestions for the current cursor: cased
    /// for sentence position, padded to three chips, and translated on-device.
    /// Used by every "word just finished" path so the bar is consistent however
    /// you got there (space, punctuation, double-space, text expansion).
    private func refreshNextWordPredictions() {
        let upper = shouldCapitalize(contextBefore: keyboardContext.textDocumentProxy.documentContextBeforeInput ?? "")
        kbState.predictions = padToThree(
            casedForCursor(predictionEngine.nextWords(after: lastContextWord())),
            upper: upper
        )
        translateMissingChips(partial: "")
    }

    /// Carry a translation already shown for the same word over to the rebuilt
    /// chips, so a known translation doesn't flicker off and back on with each
    /// keystroke while the (debounced) lookup re-runs.
    private func carryOverTranslations(_ chips: [Prediction]) -> [Prediction] {
        let prev = Dictionary(
            kbState.predictions.compactMap { p -> (String, String)? in
                (!p.source.isEmpty && !p.translation.isEmpty) ? (p.source.lowercased(), p.translation) : nil
            },
            uniquingKeysWith: { first, _ in first }
        )
        return chips.map { c in
            guard c.translation.isEmpty, !c.source.isEmpty,
                  let t = prev[c.source.lowercased()] else { return c }
            return Prediction(source: c.source, translation: t, highlighted: c.highlighted, isLoading: c.isLoading, quoted: c.quoted)
        }
    }

    /// Capitalize `word`'s first letter when the typed word is capitalized, so
    /// suggestion/completion chips visually match what's being typed.
    private func matchedCase(_ word: String, like typed: String) -> String {
        guard let t = typed.first, t.isUppercase,
              let w = word.first, w.isLowercase else { return word }
        return w.uppercased() + word.dropFirst()
    }

    /// Force the first letter of `s` to the given case; the rest is untouched.
    private func firstLetterCased(_ s: String, uppercase: Bool) -> String {
        guard let first = s.first else { return s }
        if uppercase {
            return first.isUppercase ? s : first.uppercased() + s.dropFirst()
        }
        return first.isLowercase ? s : first.lowercased() + s.dropFirst()
    }

    /// Force a machine (Apple/MyMemory) translation's leading case to match its
    /// source word. Those results are sentence-cased (capital first letter) even
    /// mid-sentence; the local dictionary is all lowercase, so anything fetched
    /// at runtime is machine output and should follow the source word's case.
    private func machineCased(_ translation: String, toSource source: String) -> String {
        let upper = source.first(where: { $0.isLetter })?.isUppercase ?? false
        return firstLetterCased(translation, uppercase: upper)
    }

    /// Case a translation for where it will appear: capitalized at a sentence
    /// start (where the source word is capitalized) and otherwise left exactly as
    /// the dictionary provides — so legitimately capitalized nouns (e.g. German)
    /// keep their capital mid-sentence.
    private func matchTranslationCase(_ translation: String, toSource source: String) -> String {
        guard let f = source.first(where: { $0.isLetter }), f.isUppercase else { return translation }
        return firstLetterCased(translation, uppercase: true)
    }

    /// Case next-word suggestion chips for where they'll be inserted: the source
    /// word is capitalized at a sentence start and lowercase mid-sentence, while
    /// the translation keeps the dictionary's own casing except at a sentence
    /// start. The quoted "keep my spelling" chip is left untouched.
    private func casedForCursor(_ preds: [Prediction]) -> [Prediction] {
        let upper = shouldCapitalize(contextBefore: keyboardContext.textDocumentProxy.documentContextBeforeInput ?? "")
        return preds.map { p in
            guard !p.source.isEmpty, !p.quoted else { return p }
            let src = firstLetterCased(p.source, uppercase: upper)
            return Prediction(
                source: src,
                translation: p.translation.isEmpty ? "" : matchTranslationCase(p.translation, toSource: src),
                highlighted: p.highlighted,
                isLoading: p.isLoading,
                quoted: p.quoted
            )
        }
    }

    /// Always present three chips: keep the supplied (non-empty) chips and fill
    /// any remaining slots with sensible next-word guesses, so the bar never
    /// shows blank slots while typing. `upper` cases the filler words.
    private func padToThree(_ chips: [Prediction], upper: Bool) -> [Prediction] {
        var out = chips.filter { !$0.source.isEmpty }
        var seen = Set(out.map { $0.source.lowercased() })
        if out.count < 3 {
            for e in predictionEngine.nextWords(after: lastContextWord(), limit: 12) where out.count < 3 {
                let key = e.source.lowercased()
                guard !e.source.isEmpty, !seen.contains(key) else { continue }
                seen.insert(key)
                let src = firstLetterCased(e.source, uppercase: upper)
                out.append(Prediction(
                    source: src,
                    translation: e.translation.isEmpty ? "" : matchTranslationCase(e.translation, toSource: src),
                    highlighted: false,
                    isLoading: false
                ))
            }
        }
        while out.count < 3 { out.append(.empty) }
        return Array(out.prefix(3))
    }

    /// The English pronoun "I" and its contractions ("i'm", "i'll", "i've"…).
    private func isEnglishI(_ word: String) -> Bool {
        word == "i" || word.hasPrefix("i'") || word.hasPrefix("i\u{2019}")
    }

    /// Apostrophe-less words that Apple's keyboard auto-fixes into contractions.
    /// Values use a plain apostrophe; it's swapped for a curly one on insert when
    /// smart quotes are on. Ambiguous-with-a-real-word forms (its, were, well,
    /// wed, lets, hell, shell) are deliberately omitted to avoid wrong fixes.
    private static let englishContractions: [String: String] = [
        "im": "I'm", "ive": "I've", "ill": "I'll", "id": "I'd",
        "dont": "don't", "doesnt": "doesn't", "didnt": "didn't",
        "cant": "can't", "couldnt": "couldn't", "wouldnt": "wouldn't",
        "shouldnt": "shouldn't", "wont": "won't", "wasnt": "wasn't",
        "werent": "weren't", "isnt": "isn't", "arent": "aren't",
        "havent": "haven't", "hasnt": "hasn't", "hadnt": "hadn't",
        "mustnt": "mustn't", "neednt": "needn't", "aint": "ain't",
        "youre": "you're", "youve": "you've", "youll": "you'll", "youd": "you'd",
        "theyre": "they're", "theyve": "they've", "theyll": "they'll", "theyd": "they'd",
        "weve": "we've", "thats": "that's", "whats": "what's",
        "theres": "there's", "hes": "he's", "shes": "she's"
    ]

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
