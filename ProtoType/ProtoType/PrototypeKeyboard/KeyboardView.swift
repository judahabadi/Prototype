import SwiftUI
import UIKit

struct KeyboardView: View {
    @Bindable var state: KeyboardState
    weak var proxy: (any KeyboardProxy)?
    let predictionEngine: PredictionEngine

    @State private var pressedKey: String? = nil
    @State private var lastSpaceTapTime: Date? = nil
    @State private var lastShiftTapTime: Date? = nil
    @State private var deleteTimer: Timer? = nil

    private let haptic = UIImpactFeedbackGenerator(style: .light)

    private var isRTL: Bool {
        state.nativeLanguage.isRTL || state.targetLanguage.isRTL
    }

    // Adaptive palette
    private static let board = Color(uiColor: .systemGray5)
    private static let letterKeyColor = Color(uiColor: .systemBackground)
    private static let funcKeyColor = Color(uiColor: .systemGray3)
    private static let keyShadow = Color.black.opacity(0.3)
    private static let keyText = Color(uiColor: .label)

    private static let keyFont = Font.system(size: 23, weight: .regular)
    private static let funcKeyFont = Font.system(size: 16, weight: .regular)
    private static let cornerRadius: CGFloat = 5
    private static let keyHeight: CGFloat = 42
    private static let rowSpacing: CGFloat = 11
    private static let keySpacing: CGFloat = 6

    var body: some View {
        VStack(spacing: 0) {
            predictionBar
                .frame(height: 36)
                .padding(.all, 0)
                .background(Self.board)
            keyboardArea
                .padding(.top, Self.rowSpacing)
                .padding(.bottom, 6)
                .padding(.horizontal, 3)
        }
        .background(Self.board)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 10,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 10
            )
        )
        .sheet(isPresented: $state.showLanguagePicker) {
            LanguagePickerView(state: state, predictionEngine: predictionEngine)
        }
        .onAppear {
            evaluateAutoCapAtStart()
        }
    }

    // MARK: - Prediction bar

    private var predictionBar: some View {
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
                ProgressView()
                    .scaleEffect(0.6)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        } else if p.translation.isEmpty {
            Text(p.source)
                .font(.system(size: 17, weight: p.highlighted ? .semibold : .regular))
                .foregroundStyle(p.highlighted ? Color.blue : labelColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }

    private func pickPrediction(_ p: Prediction, useTranslation: Bool) {
        let raw = useTranslation ? p.translation : p.source
        guard !raw.isEmpty else { return }

        let n = state.currentPartial.count
        for _ in 0..<n {
            proxy?.deleteBackward()
        }

        let toInsert = useTranslation ? raw : applyCapitalization(raw)
        proxy?.insertText(toInsert)
        proxy?.insertText(" ")
        haptic.impactOccurred()

        state.currentPartial = ""
        state.predictions = predictionEngine.topPredictions()
        evaluateAutoCapAfterContextChange()
    }

    // MARK: - Keyboard rows

    @ViewBuilder
    private var keyboardArea: some View {
        if state.isSymbolMode {
            symbolLayout
        } else {
            letterLayout
        }
    }

    private var keyboardLayout: [[String]] {
        switch state.nativeLanguage {
        case .hebrew:
            return [
                ["ק","ר","א","ט","ו","ן","ם","פ"],
                ["ש","ד","ג","כ","ע","י","ח","ל","ך","ף"],
                ["ז","ס","ב","ה","נ","מ","צ","ת","ץ"]
            ]
        case .arabic:
            return [
                ["ض","ص","ث","ق","ف","غ","ع","ه","خ","ح"],
                ["ش","س","ي","ب","ل","ا","ت","ن","م","ك"],
                ["ئ","ء","ؤ","ر","لا","ى","ة","و","ز","ظ"]
            ]
        case .russian:
            return [
                ["й","ц","у","к","е","н","г","ш","щ","з"],
                ["ф","ы","в","а","п","р","о","л","д"],
                ["я","ч","с","м","и","т","ь","б","ю"]
            ]
        default:
            return [
                ["q","w","e","r","t","y","u","i","o","p"],
                ["a","s","d","f","g","h","j","k","l"],
                ["z","x","c","v","b","n","m"]
            ]
        }
    }

    private var letterLayout: some View {
        let rows = keyboardLayout
        let rtl = state.nativeLanguage.isRTL
        return VStack(spacing: Self.rowSpacing) {
            HStack(spacing: Self.keySpacing) {
                ForEach(rtl ? rows[0].reversed() : rows[0], id: \.self) { letterKey($0) }
            }
            HStack(spacing: Self.keySpacing) {
                Spacer().frame(width: 16)
                ForEach(rtl ? rows[1].reversed() : rows[1], id: \.self) { letterKey($0) }
                Spacer().frame(width: 16)
            }
            HStack(spacing: Self.keySpacing) {
                shiftKey
                ForEach(rtl ? rows[2].reversed() : rows[2], id: \.self) { letterKey($0) }
                deleteKey
            }
            bottomRow
        }
    }

    private var symbolLayout: some View {
        VStack(spacing: Self.rowSpacing) {
            if state.isExtendedSymbols {
                HStack(spacing: Self.keySpacing) {
                    ForEach(["[","]","{","}","#","%","^","*","+","="], id: \.self) { letterKey($0) }
                }
                HStack(spacing: Self.keySpacing) {
                    ForEach(["_","\\","|","~","<",">","€","£","¥","•"], id: \.self) { letterKey($0) }
                }
                HStack(spacing: Self.keySpacing) {
                    altSymbolToggle("123")
                    ForEach([".", ",", "?", "!", "'", "\""], id: \.self) { letterKey($0) }
                    deleteKey
                }
            } else {
                HStack(spacing: Self.keySpacing) {
                    ForEach(["1","2","3","4","5","6","7","8","9","0"], id: \.self) { letterKey($0) }
                }
                HStack(spacing: Self.keySpacing) {
                    ForEach(["-","/",":",";","(",")","$","&","@","\""], id: \.self) { letterKey($0) }
                }
                HStack(spacing: Self.keySpacing) {
                    altSymbolToggle("#+=")
                    ForEach([".", ",", "?", "!", "'"], id: \.self) { letterKey($0) }
                    deleteKey
                }
            }
            bottomRow
        }
    }

    // MARK: - Keys

    private func letterKey(_ ch: String) -> some View {
        let id = "key.\(ch)"
        return Button {
            flashKey(id)
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
            }
        } label: {
            Text(displayChar(ch))
                .font(Self.keyFont)
                .foregroundStyle(Self.keyText)
                .frame(maxWidth: .infinity, minHeight: Self.keyHeight)
                .background(keyShape(filled: Self.letterKeyColor, pressed: pressedKey == id))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(pressedKey == id ? 0.95 : 1.0)
        .frame(minHeight: 44)
    }

    private func displayChar(_ ch: String) -> String {
        guard ch.count == 1, let c = ch.first, c.isLetter else { return ch }
        return (state.capsLock || state.shiftOnce) ? ch.uppercased() : ch
    }

    private var shiftKey: some View {
        let id = "key.shift"
        return Button {
            flashKey(id)
            let now = Date()
            if state.capsLock {
                state.capsLock = false
                state.shiftOnce = false
                lastShiftTapTime = nil
            } else if let last = lastShiftTapTime, now.timeIntervalSince(last) < 0.3 {
                state.capsLock = true
                state.shiftOnce = false
                lastShiftTapTime = nil
            } else {
                state.shiftOnce.toggle()
                lastShiftTapTime = now
            }
            haptic.impactOccurred()
        } label: {
            Image(systemName: state.capsLock ? "capslock.fill" : (state.shiftOnce ? "shift.fill" : "shift"))
                .font(Self.funcKeyFont)
                .foregroundStyle(Self.keyText)
                .frame(width: 42, height: Self.keyHeight)
                .background(keyShape(filled: Self.funcKeyColor, pressed: pressedKey == id))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(pressedKey == id ? 0.95 : 1.0)
        .frame(minHeight: 44)
    }

    private var deleteKey: some View {
        let id = "key.delete"
        return Image(systemName: "delete.left")
            .font(Self.funcKeyFont)
            .foregroundStyle(Self.keyText)
            .frame(width: 42, height: Self.keyHeight)
            .background(keyShape(filled: Self.funcKeyColor, pressed: pressedKey == id))
            .contentShape(Rectangle())
            .scaleEffect(pressedKey == id ? 0.95 : 1.0)
            .frame(minHeight: 44)
            .onTapGesture {
                flashKey(id)
                performDelete()
                haptic.impactOccurred()
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onChanged { value in
                        switch value {
                        case .second(true, _):
                            if deleteTimer == nil {
                                startDeleteRepeating()
                            }
                        default:
                            break
                        }
                    }
                    .onEnded { _ in
                        stopDeleteRepeating()
                    }
            )
    }

    private func performDelete() {
        proxy?.deleteBackward()
        if !state.currentPartial.isEmpty {
            state.currentPartial.removeLast()
        }
        state.predictions = state.currentPartial.isEmpty
            ? predictionEngine.topPredictions()
            : predictionEngine.predictions(for: state.currentPartial)
    }

    private func startDeleteRepeating() {
        deleteTimer?.invalidate()
        haptic.impactOccurred()
        deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
            DispatchQueue.main.async {
                proxy?.deleteBackward()
                if !state.currentPartial.isEmpty {
                    state.currentPartial.removeLast()
                }
            }
        }
    }

    private func stopDeleteRepeating() {
        deleteTimer?.invalidate()
        deleteTimer = nil
        state.predictions = state.currentPartial.isEmpty
            ? predictionEngine.topPredictions()
            : predictionEngine.predictions(for: state.currentPartial)
    }

    private func altSymbolToggle(_ label: String) -> some View {
        let id = "key.alt.\(label)"
        return Button {
            flashKey(id)
            state.isExtendedSymbols.toggle()
            haptic.impactOccurred()
        } label: {
            Text(label)
                .font(Self.funcKeyFont)
                .foregroundStyle(Self.keyText)
                .frame(width: 42, height: Self.keyHeight)
                .background(keyShape(filled: Self.funcKeyColor, pressed: pressedKey == id))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(pressedKey == id ? 0.95 : 1.0)
        .frame(minHeight: 44)
    }

    // MARK: - Bottom row

    private var bottomRow: some View {
        HStack(spacing: Self.keySpacing) {
            modeKey
            if proxy?.needsInputModeSwitchKey ?? false {
                globeKey
            }
            languagePickerKey
            spaceKey
            returnKey
        }
    }

    private var modeKey: some View {
        let id = "key.mode"
        return Button {
            flashKey(id)
            state.isSymbolMode.toggle()
            state.isExtendedSymbols = false
            haptic.impactOccurred()
        } label: {
            Text(state.isSymbolMode ? "ABC" : "123")
                .font(Self.funcKeyFont)
                .foregroundStyle(Self.keyText)
                .frame(width: 42, height: Self.keyHeight)
                .background(keyShape(filled: Self.funcKeyColor, pressed: pressedKey == id))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(pressedKey == id ? 0.95 : 1.0)
        .frame(minHeight: 44)
    }

    private var globeKey: some View {
        let id = "key.globe"
        return Button {
            flashKey(id)
            proxy?.advanceToNextInputMode()
            haptic.impactOccurred()
        } label: {
            Text(state.targetLanguage.flag)
                .font(.system(size: 18))
                .frame(width: 42, height: Self.keyHeight)
                .background(keyShape(filled: Self.funcKeyColor, pressed: pressedKey == id))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(pressedKey == id ? 0.95 : 1.0)
        .frame(minHeight: 44)
    }

    private var languagePickerKey: some View {
        let id = "key.picker"
        return Button {
            flashKey(id)
            state.showLanguagePicker = true
            haptic.impactOccurred()
        } label: {
            Text(state.targetLanguage.flag)
                .font(.system(size: 18))
                .frame(width: 42, height: Self.keyHeight)
                .background(keyShape(filled: Self.funcKeyColor, pressed: pressedKey == id))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(pressedKey == id ? 0.95 : 1.0)
        .frame(minHeight: 44)
    }

    private var spaceKey: some View {
        let id = "key.space"
        return Button {
            flashKey(id)
            handleSpace()
        } label: {
            Text("space")
                .font(Self.funcKeyFont)
                .foregroundStyle(Self.keyText)
                .frame(maxWidth: .infinity, minHeight: Self.keyHeight)
                .background(keyShape(filled: Self.letterKeyColor, pressed: pressedKey == id))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(pressedKey == id ? 0.95 : 1.0)
        .frame(minHeight: 44)
    }

    private var returnKey: some View {
        let id = "key.return"
        return Button {
            flashKey(id)
            proxy?.insertText("\n")
            state.currentPartial = ""
            state.predictions = predictionEngine.topPredictions()
            state.shiftOnce = true
            haptic.impactOccurred()
        } label: {
            Text(returnKeyLabel)
                .font(Self.funcKeyFont)
                .foregroundStyle(Self.keyText)
                .frame(width: 80, height: Self.keyHeight)
                .background(keyShape(filled: Self.funcKeyColor, pressed: pressedKey == id))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(pressedKey == id ? 0.95 : 1.0)
        .frame(minHeight: 44)
    }

    private var returnKeyLabel: String {
        switch proxy?.returnKeyType ?? .default {
        case .search, .google, .yahoo: return "search"
        case .go: return "go"
        case .send, .emergencyCall: return "send"
        case .done: return "done"
        case .next: return "next"
        case .continue: return "continue"
        case .join: return "join"
        case .route: return "route"
        case .default: return "return"
        @unknown default: return "return"
        }
    }

    private func keyShape(filled: Color, pressed: Bool) -> some View {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            .fill(pressed ? filled.opacity(0.7) : filled)
            .shadow(color: Self.keyShadow, radius: 0, x: 0, y: 1)
    }

    // MARK: - Press flash

    private func flashKey(_ id: String) {
        pressedKey = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if pressedKey == id { pressedKey = nil }
        }
    }

    // MARK: - Space (autocorrect + double-tap + translation)

    private func handleSpace() {
        let now = Date()
        let isDoubleTap = (lastSpaceTapTime.map { now.timeIntervalSince($0) < 0.3 } ?? false)

        if isDoubleTap {
            // Replace the previously inserted space with ". "
            proxy?.deleteBackward()
            proxy?.insertText(". ")
            state.shiftOnce = true
            haptic.impactOccurred()
            lastSpaceTapTime = nil
            state.currentPartial = ""
            state.predictions = predictionEngine.topPredictions()
            return
        }
        lastSpaceTapTime = now

        let raw = state.currentPartial
        let cleaned = raw.lowercased().trimmingCharacters(in: .punctuationCharacters)

        var finalWord = cleaned
        if !cleaned.isEmpty {
            if let correction = AutocorrectService.correct(word: cleaned, language: state.nativeLanguage),
               correction.lowercased() != cleaned {
                for _ in 0..<raw.count { proxy?.deleteBackward() }
                proxy?.insertText(correction)
                finalWord = correction.lowercased()
            }
        }

        proxy?.insertText(" ")
        haptic.impactOccurred()
        state.currentPartial = ""

        evaluateAutoCapAfterContextChange()

        guard !finalWord.isEmpty else {
            state.predictions = predictionEngine.topPredictions()
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
        combined.append(contentsOf: predictionEngine.topPredictions(excluding: finalWord, limit: 2))
        while combined.count < 3 { combined.append(.empty) }
        state.predictions = combined

        if localTranslation.isEmpty {
            let from = state.nativeLanguage
            let to = state.targetLanguage
            Task { [weak state] in
                let result = await TranslationService.shared.translate(word: finalWord, from: from, to: to)
                await MainActor.run {
                    guard let state else { return }
                    var current = state.predictions
                    if !current.isEmpty, current[0].source == finalWord {
                        current[0] = Prediction(
                            source: finalWord,
                            translation: result == "—" ? "" : result,
                            highlighted: true,
                            isLoading: false
                        )
                        state.predictions = current
                    }
                }
            }
        }
    }

    // MARK: - Auto-cap

    /// Sets shiftOnce based on the current text context (start of input,
    /// after sentence-ending punctuation + space, or after a newline).
    private func evaluateAutoCapAfterContextChange() {
        let ctx = proxy?.documentContextBeforeInput ?? ""
        if ctx.isEmpty {
            state.shiftOnce = true
            return
        }
        if ctx.hasSuffix(". ") || ctx.hasSuffix("! ") || ctx.hasSuffix("? ")
            || ctx.hasSuffix("\n") {
            state.shiftOnce = true
        }
    }

    private func evaluateAutoCapAtStart() {
        if state.currentPartial.isEmpty {
            let ctx = proxy?.documentContextBeforeInput ?? ""
            if ctx.isEmpty {
                state.shiftOnce = true
            }
        }
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
