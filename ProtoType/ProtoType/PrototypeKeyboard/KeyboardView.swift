import SwiftUI
import UIKit
import Translation
import KeyboardKit

struct ProtoTypeKeyboardView: View {
    @Bindable var state: KeyboardState
    weak var proxy: (any KeyboardProxy)?
    let predictionEngine: PredictionEngine
    let kkServices: Keyboard.Services

    @State private var translationConfig: TranslationSession.Configuration?

    // Selection auto-translate (Feature 2)
    @State private var lastHandledSelection: String = ""
    @State private var selectionTranslation: String = ""
    @State private var selectionTranslating: Bool = false

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
        KeyboardView(
            services: kkServices,
            buttonContent: { $0.view },
            buttonView: { $0.view },
            collapsedView: { $0.view },
            emojiKeyboard: { $0.view },
            toolbar: { [self] _ in
                if shouldPredict {
                    VStack(spacing: 0) {
                        predictionBar
                            .frame(height: 44)
                        Rectangle()
                            .fill(Color(uiColor: .separator))
                            .frame(height: 0.5)
                    }
                } else {
                    EmptyView()
                }
            }
        )
        .preferredColorScheme(preferredScheme)
        .sheet(isPresented: $state.showLanguagePicker) {
            LanguagePickerView(state: state, predictionEngine: predictionEngine)
        }
        .onAppear {
            updateTranslationConfig()
        }
        .onChange(of: state.contextSignal) { handleSelectionChange() }
        .onChange(of: state.nativeLanguage) { updateTranslationConfig() }
        .onChange(of: state.targetLanguage) { updateTranslationConfig() }
        .translationTask(translationConfig) { session in
            TranslationService.shared.setSession(session)
        }
    }

    private func updateTranslationConfig() {
        let source = Locale.Language(identifier: state.nativeLanguage.appleTranslationLocale)
        let target = Locale.Language(identifier: state.targetLanguage.appleTranslationLocale)
        Task {
            let status = await LanguageAvailability().status(from: source, to: target)
            switch status {
            case .installed, .supported:
                translationConfig = TranslationSession.Configuration(source: source, target: target)
            case .unsupported:
                translationConfig = nil
                TranslationService.shared.clearAppleSession()
            @unknown default:
                translationConfig = nil
            }
        }
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
            selectionTranslateChip(selection: selection)
                .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
        } else {
            HStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { idx in
                    let p = idx < state.predictions.count ? state.predictions[idx] : .empty
                    chipContent(p)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !p.source.isEmpty else { return }
                            pickPrediction(p, useTranslation: false)
                        }
                        .onLongPressGesture(minimumDuration: 0.35) {
                            guard !p.source.isEmpty, !p.translation.isEmpty else { return }
                            pickPrediction(p, useTranslation: true)
                        }
                    if idx < 2 {
                        Rectangle()
                            .fill(Color(uiColor: .separator))
                            .frame(width: 0.33, height: 20)
                    }
                }
            }
            .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
        }
    }

    // MARK: - Selection auto-translate (Feature 2)

    /// Called whenever the document/selection changes (via `contextSignal`).
    /// Auto-translates a fresh selection; resets when the selection clears.
    private func handleSelectionChange() {
        let selection = proxy?.selectedText ?? ""
        if selection.isEmpty {
            lastHandledSelection = ""
            selectionTranslation = ""
            selectionTranslating = false
            return
        }
        guard selection != lastHandledSelection else { return }
        lastHandledSelection = selection
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

    private func selectionTranslateChip(selection: String) -> some View {
        HStack(spacing: 6) {
            if selectionTranslating {
                Text("Translating \"\(selection)\"…")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.blue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                ProgressView().scaleEffect(0.7)
            } else if !selectionTranslation.isEmpty {
                Image(systemName: "character.bubble")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.blue)
                Text("\(selection) → \(selectionTranslation)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.blue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else {
                Text(selection)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color(uiColor: .label))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { replaceSelectionWithTranslation() }
    }

    /// Tapping the chip replaces the selection with its translation (Apple-style,
    /// deliberate). Not tapping leaves the original selection untouched.
    private func replaceSelectionWithTranslation() {
        guard !selectionTranslation.isEmpty else { return }
        proxy?.insertText(selectionTranslation)
        proxy?.playInputClick()
        lastHandledSelection = ""
        selectionTranslation = ""
        selectionTranslating = false
    }

    @ViewBuilder
    private func chipContent(_ p: Prediction) -> some View {
        let labelColor = Color(uiColor: .label)
        if p.source.isEmpty {
            Text(" ")
        } else if p.isLoading {
            HStack(spacing: 4) {
                Text(p.source)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.blue)
                Text("/")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                ProgressView().scaleEffect(0.6)
            }
            .lineLimit(1).minimumScaleFactor(0.7)
        } else if p.translation.isEmpty {
            Text(p.source)
                .font(.system(size: 17, weight: p.highlighted ? .semibold : .regular))
                .foregroundStyle(p.highlighted ? Color.blue : labelColor)
                .lineLimit(1).minimumScaleFactor(0.7)
        } else {
            HStack(spacing: 4) {
                Text(p.source)
                    .font(.system(size: 17, weight: p.highlighted ? .semibold : .regular))
                Text("/")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                Text(p.translation)
                    .font(.system(size: 17, weight: p.highlighted ? .semibold : .regular))
            }
            .foregroundStyle(p.highlighted ? Color.blue : labelColor)
            .lineLimit(1).minimumScaleFactor(0.7)
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
        proxy?.insertText(raw)
        let after = proxy?.documentContextAfterInput
        if after == nil || !(after?.first?.isLetter ?? false) {
            proxy?.insertText(" ")
        }
        proxy?.playInputClick()
        state.currentPartial = ""
        state.predictions = predictionEngine.nextWords(after: lastContextWord())
    }
}
