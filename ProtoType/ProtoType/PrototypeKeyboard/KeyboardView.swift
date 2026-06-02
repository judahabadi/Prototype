import SwiftUI
import UIKit
import Translation
import KeyboardKit

struct ProtoTypeKeyboardView: View {
    @Bindable var state: KeyboardState
    weak var proxy: (any KeyboardProxy)?
    let predictionEngine: PredictionEngine
    let kkServices: Keyboard.Services

    @State private var pasteAvailable: Bool = false
    @State private var translationConfig: TranslationSession.Configuration?

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
            refreshPasteAvailable()
            updateTranslationConfig()
        }
        .onChange(of: state.contextSignal) { refreshPasteAvailable() }
        .onChange(of: state.nativeLanguage) { updateTranslationConfig() }
        .onChange(of: state.targetLanguage) { updateTranslationConfig() }
        .translationTask(translationConfig) { session in
            TranslationService.shared.setSession(session)
        }
    }

    private func refreshPasteAvailable() {
        guard proxy?.hasFullAccess == true else {
            pasteAvailable = false
            return
        }
        pasteAvailable = UIPasteboard.general.hasStrings
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
                let showPaste = pasteAvailable && state.currentPartial.isEmpty
                if showPaste {
                    pasteChip
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Rectangle()
                        .fill(Color(uiColor: .separator))
                        .frame(width: 0.33, height: 20)
                }
                let chipCount = showPaste ? 2 : 3
                ForEach(0..<chipCount, id: \.self) { idx in
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
                    if idx < chipCount - 1 {
                        Rectangle()
                            .fill(Color(uiColor: .separator))
                            .frame(width: 0.33, height: 20)
                    }
                }
            }
            .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
        }
    }

    private var pasteChip: some View {
        HStack(spacing: 5) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 13, weight: .medium))
            Text("Paste")
                .font(.system(size: 16, weight: .semibold))
        }
        .foregroundStyle(Color.blue)
        .contentShape(Rectangle())
        .onTapGesture {
            performPaste()
        }
    }

    private func performPaste() {
        guard proxy?.hasFullAccess == true,
              let s = UIPasteboard.general.string, !s.isEmpty else {
            pasteAvailable = false
            return
        }
        proxy?.insertText(s)
        proxy?.playInputClick()
        state.currentPartial = ""
        pasteAvailable = false
        state.predictions = predictionEngine.nextWords(after: lastContextWord())
    }

    private func selectionTranslateChip(selection: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "character.bubble")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.blue)
            Text("Translate \"\(selection)\"")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.blue)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { translateSelection(selection) }
    }

    private func translateSelection(_ selection: String) {
        let trimmed = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let local = predictionEngine.translation(for: trimmed.lowercased())
        if let local, !local.isEmpty {
            proxy?.insertText(local)
            proxy?.playInputClick()
            return
        }
        let from = state.nativeLanguage
        let to = state.targetLanguage
        Task { [weak proxy] in
            let result = await TranslationService.shared.translate(word: trimmed, from: from, to: to)
            await MainActor.run {
                guard result != "—", !result.isEmpty else { return }
                proxy?.insertText(result)
                proxy?.playInputClick()
            }
        }
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
