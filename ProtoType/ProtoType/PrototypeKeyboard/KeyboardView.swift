import SwiftUI
import UIKit
import KeyboardKit

struct ProtoTypeKeyboardView: View {
    /// Fixed height of the QuickType bar, tuned to Apple's native bar. Used both
    /// for the bar frame and each chip's row so content is always centred.
    /// Apple's bar isn't a published value; ~37pt reads close on iPhone. Easy to
    /// nudge here if it still looks off on device.
    static let barHeight: CGFloat = 37

    @Bindable var state: KeyboardState
    weak var proxy: (any KeyboardProxy)?
    let predictionEngine: PredictionEngine
    let kkServices: Keyboard.Services

    // Selection auto-translate (Feature 2)
    @State private var lastHandledSelection: String = ""
    @State private var selectionTranslation: String = ""
    @State private var selectionTranslating: Bool = false
    // On-device "fix" for a highlighted sentence (empty when nothing to fix).
    @State private var selectionFix: String = ""

    private var isRTL: Bool {
        state.nativeLanguage.isRTL || state.targetLanguage.isRTL
    }

    private var isSecureField: Bool {
        proxy?.isSecureTextEntry == true
            || proxy?.textContentType == .password
            || proxy?.textContentType == .newPassword
    }

    private var shouldPredict: Bool {
        guard !isSecureField else { return false }
        if proxy?.textContentType == .oneTimeCode { return false }
        if proxy?.autocorrectionType == .no { return false }
        return true
    }

    private var preferredScheme: ColorScheme? {
        switch proxy?.keyboardAppearance ?? .default {
        case .dark: return .dark
        case .light: return .light
        default: return nil
        }
    }

    var body: some View {
        // Render our QuickType bar OUTSIDE KeyboardKit's toolbar slot. KK reserves
        // a taller toolbar height than ours and re-asserts it when the keyboard is
        // re-shown (e.g. switching keyboards and back), which pinned our short bar
        // low and made it look tall. Owning the bar in our own VStack and giving KK
        // an empty toolbar keeps the height fixed and the words vertically centred.
        VStack(spacing: 0) {
            if shouldPredict {
                predictionBar
                    .frame(height: Self.barHeight)
                Rectangle()
                    .fill(Color(uiColor: .separator))
                    .frame(height: 0.5)
            }
            keyboard
        }
    }

    private var keyboard: some View {
        KeyboardView(
            services: kkServices,
            buttonContent: { $0.view },
            buttonView: { $0.view },
            collapsedView: { $0.view },
            emojiKeyboard: { $0.view },
            toolbar: { _ in EmptyView() }
        )
        .keyboardCalloutActions { params in
            // Long-press accent popups (é, ñ, ü, ç…) for Latin-script languages,
            // falling back to KeyboardKit's standard callouts for everything else.
            if case let .character(char) = params.action,
               char.count == 1, let c = char.first,
               let base = AccentCallouts.variants[Character(c.lowercased())] {
                let chars = c.isUppercase ? base.uppercased() : base
                return chars.map { KeyboardAction.character(String($0)) }
            }
            return params.standardActions()
        }
        .preferredColorScheme(preferredScheme)
        .sheet(isPresented: $state.showLanguagePicker) {
            LanguagePickerView(state: state, predictionEngine: predictionEngine)
        }
        .onChange(of: state.contextSignal) { handleSelectionChange() }
    }

    private func lastContextWord() -> String {
        let before = proxy?.documentContextBeforeInput ?? ""
        let trimmed = before.trimmingCharacters(in: .whitespacesAndNewlines)
        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        return trimmed.components(separatedBy: separators).filter { !$0.isEmpty }.last ?? ""
    }

    // MARK: - Prediction bar

    @ViewBuilder
    private var predictionBar: some View {
        if let selection = proxy?.selectedText, !selection.isEmpty {
            selectionBar(selection: selection)
                .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
        } else {
            // The WHOLE chip row scrolls as one unit when content is too long for
            // three chips; when it fits, leading/trailing spacers centre the row.
            // (One scroll view around the row, not per-chip — per-chip scrolling
            // was the old build's mistake.)
            GeometryReader { geo in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        chipRow
                        Spacer(minLength: 0)
                    }
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
        }
    }

    /// The three suggestion chips with hairline separators, sized to content.
    @ViewBuilder
    private var chipRow: some View {
        let count = visibleChipCount
        ForEach(0..<count, id: \.self) { idx in
            let p = idx < state.predictions.count ? state.predictions[idx] : .empty
            chipContent(p)
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .frame(minWidth: 64)
                .background {
                    // Apple-style rounded "pill" behind the auto-correct default.
                    if p.highlighted {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(uiColor: .systemGray4))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !p.source.isEmpty else { return }
                    pickPrediction(p, useTranslation: false)
                }
                .onLongPressGesture(minimumDuration: 0.35) {
                    guard !p.source.isEmpty, !p.translation.isEmpty else { return }
                    pickPrediction(p, useTranslation: true)
                }
            if idx < count - 1 {
                Rectangle()
                    .fill(Color(uiColor: .separator))
                    .frame(width: 0.33, height: 20)
            }
        }
    }

    /// Always show three chips. Long content scrolls the whole row (see
    /// `predictionBar`) rather than dropping a chip.
    private let visibleChipCount = 3

    // MARK: - Selection auto-translate (Feature 2)

    /// Called whenever the document/selection changes (via `contextSignal`).
    /// Auto-translates a fresh selection; resets when the selection clears.
    private func handleSelectionChange() {
        let selection = proxy?.selectedText ?? ""
        if selection.isEmpty {
            lastHandledSelection = ""
            selectionTranslation = ""
            selectionTranslating = false
            selectionFix = ""
            return
        }
        guard selection != lastHandledSelection else { return }
        lastHandledSelection = selection
        selectionFix = SentenceFix.corrected(selection, languageCode: state.nativeLanguage.isoCode) ?? ""
        requestSelectionTranslation(selection)
    }

    private func requestSelectionTranslation(_ selection: String) {
        let trimmed = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            selectionTranslation = ""
            selectionTranslating = false
            return
        }
        if let local = predictionEngine.translation(for: trimmed.lowercased()), !local.isEmpty {
            selectionTranslation = local
            selectionTranslating = false
            return
        }
        selectionTranslation = ""
        selectionTranslating = true
        let from = state.nativeLanguage
        let to = state.targetLanguage
        Task {
            let result = await TranslationService.shared.translate(word: trimmed, from: from, to: to)
            await MainActor.run {
                // Stale-guard: only apply if this selection is still active.
                guard (proxy?.selectedText ?? "") == selection else { return }
                selectionTranslating = false
                selectionTranslation = (result == "—") ? "" : result
            }
        }
    }

    /// Selection mode: an on-device "fix" chip (when something can be cleaned up)
    /// beside the translate chip. Falls back to just the translate chip.
    @ViewBuilder
    private func selectionBar(selection: String) -> some View {
        HStack(spacing: 0) {
            if !selectionFix.isEmpty {
                fixChip(corrected: selectionFix)
                Rectangle()
                    .fill(Color(uiColor: .separator))
                    .frame(width: 0.33, height: 24)
            }
            selectionTranslateChip(selection: selection)
        }
    }

    /// Tap to replace the highlighted text with its on-device cleaned-up version.
    private func fixChip(corrected: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(uiColor: .label))
                Text(corrected)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color(uiColor: .label))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(height: Self.barHeight)
        }
        .defaultScrollAnchor(.leading)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { replaceSelection(with: corrected) }
    }

    private func selectionTranslateChip(selection: String) -> some View {
        let labelColor = Color(uiColor: .label)
        let centered = selectionTranslation.isEmpty && !selectionTranslating
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if selectionTranslating {
                    Text("Translating \"\(selection)\"…")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(labelColor)
                        .lineLimit(1)
                    ProgressView().scaleEffect(0.7)
                } else if !selectionTranslation.isEmpty {
                    Image(systemName: "character.bubble")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(labelColor)
                    Text("\(selection) → \(selectionTranslation)")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(labelColor)
                        .lineLimit(1)
                } else {
                    Text(selection)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(labelColor)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: Self.barHeight)
        }
        .defaultScrollAnchor(centered ? .center : .leading)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { replaceSelectionWithTranslation() }
    }

    /// Tapping the chip replaces the selection with its translation (Apple-style,
    /// deliberate). Not tapping leaves the original selection untouched.
    private func replaceSelectionWithTranslation() {
        replaceSelection(with: selectionTranslation)
    }

    /// Replace the highlighted text and clear selection-derived state.
    private func replaceSelection(with text: String) {
        guard !text.isEmpty else { return }
        proxy?.insertText(text)
        proxy?.playInputClick()
        lastHandledSelection = ""
        selectionTranslation = ""
        selectionTranslating = false
        selectionFix = ""
    }

    @ViewBuilder
    private func chipContent(_ p: Prediction) -> some View {
        let labelColor = Color(uiColor: .label)
        if p.source.isEmpty {
            Text(" ")
        } else if p.quoted {
            // Apple-style literal: the typed word shown in quotes ("keep my spelling").
            Text("\u{201C}\(p.source)\u{201D}")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(labelColor)
                .lineLimit(1)
        } else if p.isLoading {
            HStack(spacing: 4) {
                Text(p.source)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(labelColor)
                Text("/")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.secondary)
                ProgressView().scaleEffect(0.6)
            }
            .lineLimit(1)
        } else if p.translation.isEmpty {
            Text(p.source)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(labelColor)
                .lineLimit(1)
        } else {
            HStack(spacing: 4) {
                // Book-style gloss: word with its translation in parentheses,
                // e.g. "hola (hello)". The translation is dimmed for hierarchy.
                Text(p.source)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(labelColor)
                Text("(\(p.translation))")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
    }

    private func pickPrediction(_ p: Prediction, useTranslation: Bool) {
        let raw = useTranslation ? p.translation : p.source
        guard !raw.isEmpty else { return }
        // If the user kept their own spelling by tapping the literal chip in
        // spelling-takeover mode (un-highlighted chip whose word == the typed
        // word), learn it so it isn't flagged as a typo again (Feature 7).
        if !useTranslation, !p.highlighted,
           !state.currentPartial.isEmpty,
           p.source.lowercased() == state.currentPartial.lowercased() {
            AutocorrectService.learn(p.source)
        }
        let n = state.currentPartial.count
        for _ in 0..<n { proxy?.deleteBackward() }
        // Re-case a tapped word-suggestion to where it actually lands: capital at a
        // sentence start, lowercase mid-sentence. The chip text itself can be
        // capitalized (e.g. when first shown at a sentence start), so inserting it
        // verbatim was capitalizing mid-sentence words. Translations keep their own
        // casing.
        let toInsert: String
        if useTranslation {
            toInsert = raw
        } else {
            let before = proxy?.documentContextBeforeInput ?? ""
            let upper = Autocap.shouldUppercase(
                contextBefore: before,
                type: proxy?.autocapitalizationType ?? .sentences
            )
            if let f = raw.first {
                toInsert = (upper ? f.uppercased() : f.lowercased()) + raw.dropFirst()
            } else {
                toInsert = raw
            }
        }
        proxy?.insertText(toInsert)
        let after = proxy?.documentContextAfterInput
        if after == nil || !(after?.first?.isLetter ?? false) {
            proxy?.insertText(" ")
        }
        proxy?.playInputClick()
        state.currentPartial = ""
        state.predictions = predictionEngine.nextWords(after: lastContextWord())
    }
}

/// Long-press accent/diacritic callout data for letter keys. Covers the
/// Latin-script target languages (Spanish, French, German, Portuguese, etc.);
/// other keys and non-Latin scripts fall back to KeyboardKit's standard callouts.
enum AccentCallouts {

    /// Base lowercase letter → the characters shown in its long-press callout.
    /// The base letter is listed first so it stays the default on a quick tap.
    static let variants: [Character: String] = [
        "a": "aàáâäæãåā",
        "c": "cçćč",
        "e": "eèéêëēėę",
        "i": "iîïíīįì",
        "l": "lł",
        "n": "nñń",
        "o": "oôöòóœøōõ",
        "s": "sßśš",
        "u": "uûüùúū",
        "y": "yÿý",
        "z": "zžźż",
        "g": "gğ"
    ]
}

/// On-device clean-up for a highlighted sentence — no network. Combines
/// UITextChecker spelling correction with light tidy-up (collapse runs of
/// spaces, capitalize the first letter, and add a terminating period to a
/// multi-word sentence that lacks end punctuation). Returns nil when the
/// result is identical to the input, i.e. there is nothing to fix.
enum SentenceFix {

    static func corrected(_ text: String, languageCode: String) -> String? {
        let tidied = tidy(spellCorrected(text, languageCode: languageCode))
        return tidied == text ? nil : tidied
    }

    private static func spellCorrected(_ text: String, languageCode: String) -> String {
        let checker = UITextChecker()
        guard let language = resolveLanguage(languageCode, checker: checker) else { return text }
        let mutable = NSMutableString(string: text)
        var location = 0
        while location < mutable.length {
            let range = NSRange(location: location, length: mutable.length - location)
            let misspelled = checker.rangeOfMisspelledWord(
                in: mutable as String, range: range,
                startingAt: location, wrap: false, language: language)
            if misspelled.location == NSNotFound { break }
            let original = mutable.substring(with: misspelled)
            // Take the top guess only when it's a real correction. UITextChecker
            // often returns the Capitalized same word as the first guess for short
            // words (e.g. "car" -> "Car"); accepting that would spuriously
            // capitalize correctly-spelled words, so skip case-only changes.
            if let top = checker.guesses(
                forWordRange: misspelled, in: mutable as String, language: language)?.first,
               !top.isEmpty, top.lowercased() != original.lowercased() {
                mutable.replaceCharacters(in: misspelled, with: top)
                location = misspelled.location + (top as NSString).length
            } else {
                location = misspelled.location + misspelled.length
            }
        }
        return mutable as String
    }

    /// UITextChecker wants codes like "en"/"en_US"; fall back to any available
    /// language sharing the ISO prefix, else nil (skip spelling correction).
    private static func resolveLanguage(_ code: String, checker: UITextChecker) -> String? {
        let available = UITextChecker.availableLanguages
        if available.contains(code) { return code }
        return available.first { $0.hasPrefix(code) }
    }

    private static func tidy(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return s }
        if let first = s.firstIndex(where: { $0.isLetter }) {
            s.replaceSubrange(first...first, with: s[first].uppercased())
        }
        let wordCount = s.split(whereSeparator: { $0.isWhitespace }).count
        if wordCount >= 3, let last = s.last, last.isLetter || last.isNumber {
            s.append(".")
        }
        return s
    }
}
