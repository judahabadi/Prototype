import SwiftUI
import UIKit

struct KeyboardView: View {
    @Bindable var state: KeyboardState
    weak var proxy: (any KeyboardProxy)?
    let predictionEngine: PredictionEngine

    private let haptic = UIImpactFeedbackGenerator(style: .light)

    private var isRTL: Bool {
        state.nativeLanguage.isRTL || state.targetLanguage.isRTL
    }

    var body: some View {
        VStack(spacing: 0) {
            parallelBar
                .frame(height: 44)
                .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
            Divider().background(Color.white.opacity(0.1))
            predictionBar
                .frame(height: 44)
            Divider().background(Color.white.opacity(0.1))
            keyboardArea
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
        }
        .background(Color(uiColor: .systemBackground))
        .sheet(isPresented: $state.showLanguagePicker) {
            LanguagePickerView(state: state, predictionEngine: predictionEngine)
        }
    }

    // MARK: Parallel bar

    private var parallelBar: some View {
        HStack(spacing: 8) {
            Text(state.sourceWord.isEmpty ? " " : state.sourceWord)
                .font(.system(size: 15, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            if !state.sourceWord.isEmpty {
                Text("→")
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Group {
                if state.isLoadingTranslation {
                    ShimmerView()
                        .frame(width: 80, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Text(state.currentTranslation.isEmpty ? " " : state.currentTranslation)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 4)

            Button {
                state.showLanguagePicker = true
            } label: {
                Image(systemName: "globe")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .environment(\.layoutDirection, .leftToRight)
        }
        .padding(.horizontal, 12)
    }

    // MARK: Prediction bar

    private var predictionBar: some View {
        HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { idx in
                let word = idx < state.predictions.count ? state.predictions[idx] : ""
                Button {
                    guard !word.isEmpty else { return }
                    let formatted = applyCapitalization(word)
                    proxy?.insertText(formatted)
                    haptic.impactOccurred()
                    state.currentPartial = ""
                } label: {
                    Text(word.isEmpty ? "—" : word)
                        .font(.system(size: 15, weight: idx == 0 && state.correctionApplied != nil ? .semibold : .regular, design: .monospaced))
                        .foregroundStyle(word.isEmpty ? .tertiary : .primary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .background(
                            (idx == 0 && state.correctionApplied != nil)
                                ? Color.accentColor.opacity(0.15) : Color.clear
                        )
                }
                if idx < 2 {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 0.5, height: 24)
                }
            }
        }
    }

    // MARK: Keyboard area

    @ViewBuilder
    private var keyboardArea: some View {
        if state.isSymbolMode {
            symbolLayout
        } else {
            letterLayout
        }
    }

    private var letterLayout: some View {
        VStack(spacing: 6) {
            keyRow(["q","w","e","r","t","y","u","i","o","p"])
            HStack(spacing: 0) {
                Spacer(minLength: 0).frame(maxWidth: 18)
                keyRow(["a","s","d","f","g","h","j","k","l"])
                Spacer(minLength: 0).frame(maxWidth: 18)
            }
            HStack(spacing: 6) {
                shiftKey
                keyRow(["z","x","c","v","b","n","m"])
                deleteKey
            }
            bottomRow
        }
    }

    private var symbolLayout: some View {
        VStack(spacing: 6) {
            if state.isExtendedSymbols {
                keyRow(["[","]","{","}","#","%","^","*","+","="])
                keyRow(["_","\\","|","~","<",">","€","£","¥","•"])
                HStack(spacing: 6) {
                    altSymbolToggle("123")
                    keyRow([".",",","?","!","'","\""])
                    deleteKey
                }
            } else {
                keyRow(["1","2","3","4","5","6","7","8","9","0"])
                keyRow(["-","/",":",";","(",")","$","&","@","\""])
                HStack(spacing: 6) {
                    altSymbolToggle("#+=")
                    keyRow([".",",","?","!","'"])
                    deleteKey
                }
            }
            bottomRow
        }
    }

    private func keyRow(_ chars: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(chars, id: \.self) { c in
                letterKey(c)
            }
        }
    }

    private func letterKey(_ ch: String) -> some View {
        Button {
            let isLetter = ch.count == 1 && (ch.first?.isLetter ?? false)
            let toInsert: String
            if isLetter {
                if state.capsLock || state.shiftOnce {
                    toInsert = ch.uppercased()
                } else {
                    toInsert = ch
                }
                if state.shiftOnce { state.shiftOnce = false }
                state.currentPartial.append(toInsert.lowercased())
            } else {
                toInsert = ch
            }
            proxy?.insertText(toInsert)
            haptic.impactOccurred()

            if isLetter {
                state.predictions = predictionEngine.predictions(for: state.currentPartial)
                state.correctionApplied = nil
            }
        } label: {
            Text(displayChar(ch))
                .font(.system(size: 18, weight: .regular, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                        .shadow(color: .black.opacity(0.2), radius: 0, y: 1)
                )
                .contentShape(Rectangle())
        }
        .frame(minHeight: 44)
    }

    private func displayChar(_ ch: String) -> String {
        guard ch.count == 1, let c = ch.first, c.isLetter else { return ch }
        return (state.capsLock || state.shiftOnce) ? ch.uppercased() : ch
    }

    private var shiftKey: some View {
        Button {
            if state.capsLock {
                state.capsLock = false
                state.shiftOnce = false
            } else if state.shiftOnce {
                state.capsLock = true
                state.shiftOnce = false
            } else {
                state.shiftOnce = true
            }
            haptic.impactOccurred()
        } label: {
            Image(systemName: state.capsLock ? "capslock.fill" : (state.shiftOnce ? "shift.fill" : "shift"))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemBackground))
                )
                .contentShape(Rectangle())
        }
        .frame(minHeight: 44)
    }

    private var deleteKey: some View {
        Button {
            proxy?.deleteBackward()
            if !state.currentPartial.isEmpty {
                state.currentPartial.removeLast()
            }
            state.predictions = predictionEngine.predictions(for: state.currentPartial)
            state.correctionApplied = nil
            haptic.impactOccurred()
        } label: {
            Image(systemName: "delete.left")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemBackground))
                )
                .contentShape(Rectangle())
        }
        .frame(minHeight: 44)
    }

    private func altSymbolToggle(_ label: String) -> some View {
        Button {
            state.isExtendedSymbols.toggle()
            haptic.impactOccurred()
        } label: {
            Text(label)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .frame(width: 44, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemBackground))
                )
                .contentShape(Rectangle())
        }
        .frame(minHeight: 44)
    }

    private var bottomRow: some View {
        HStack(spacing: 6) {
            Button {
                state.isSymbolMode.toggle()
                state.isExtendedSymbols = false
                haptic.impactOccurred()
            } label: {
                Text(state.isSymbolMode ? "ABC" : "123")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .frame(width: 44, height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemBackground))
                    )
                    .contentShape(Rectangle())
            }
            .frame(minHeight: 44)

            if proxy?.needsInputModeSwitchKey ?? false {
                Button {
                    proxy?.advanceToNextInputMode()
                    haptic.impactOccurred()
                } label: {
                    Image(systemName: "globe")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 44, height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color(uiColor: .tertiarySystemBackground))
                        )
                        .contentShape(Rectangle())
                }
                .frame(minHeight: 44)
            }

            Button {
                handleSpace()
            } label: {
                Text("space")
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                            .shadow(color: .black.opacity(0.2), radius: 0, y: 1)
                    )
                    .contentShape(Rectangle())
            }
            .frame(minHeight: 44)

            Button {
                proxy?.insertText("\n")
                haptic.impactOccurred()
                finalizeAfterTerminator()
            } label: {
                Text("return")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .frame(width: 70, height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemBackground))
                    )
                    .contentShape(Rectangle())
            }
            .frame(minHeight: 44)

            Button {
                proxy?.dismissKeyboard()
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 44, height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemBackground))
                    )
                    .contentShape(Rectangle())
            }
            .frame(minHeight: 44)
        }
    }

    // MARK: Logic helpers

    private func handleSpace() {
        let raw = state.currentPartial
        let cleaned = raw.lowercased().trimmingCharacters(in: .punctuationCharacters)

        if !cleaned.isEmpty {
            if let correction = AutocorrectService.correct(word: cleaned, language: state.nativeLanguage),
               correction.lowercased() != cleaned {
                for _ in 0..<raw.count {
                    proxy?.deleteBackward()
                }
                proxy?.insertText(correction)
                state.correctionApplied = correction
                state.predictions = [correction] + Array(state.predictions.prefix(2))
                state.sourceWord = correction.lowercased()
            } else {
                state.sourceWord = cleaned
                state.correctionApplied = nil
            }

            state.currentPartial = ""
            state.isLoadingTranslation = true
            let word = state.sourceWord
            let from = state.nativeLanguage
            let to = state.targetLanguage
            Task { [weak state] in
                let result = await TranslationService.shared.translate(word: word, from: from, to: to)
                await MainActor.run {
                    state?.currentTranslation = result
                    state?.isLoadingTranslation = false
                }
            }
        }

        proxy?.insertText(" ")
        haptic.impactOccurred()
        if !cleaned.isEmpty {
            state.predictions = []
        }
    }

    private func finalizeAfterTerminator() {
        state.currentPartial = ""
        state.predictions = []
        state.correctionApplied = nil
    }

    private func applyCapitalization(_ word: String) -> String {
        let context = proxy?.documentContextBeforeInput ?? ""
        let trimmed = context.reversed().drop(while: { $0 == " " })
        let last = trimmed.first
        let shouldCap: Bool = {
            if context.isEmpty { return true }
            if let last, ".!?".contains(last) { return true }
            return false
        }()
        if shouldCap {
            return word.prefix(1).uppercased() + word.dropFirst()
        }
        return word
    }
}

// MARK: - Shimmer

private struct ShimmerView: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        LinearGradient(
            colors: [
                Color.white.opacity(0.05),
                Color.white.opacity(0.18),
                Color.white.opacity(0.05)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .mask(Rectangle())
        .overlay(
            GeometryReader { geo in
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.3), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * 0.5)
                    .offset(x: phase * geo.size.width)
            }
        )
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = 1.5
            }
        }
    }
}
