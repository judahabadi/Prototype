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
    @State private var previewKey: String? = nil
    @State private var previewFrame: CGRect = .zero

    private static let keyboardSpace = "kb"

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
    private static let keyHeight: CGFloat = 46
    private static let rowSpacing: CGFloat = 12
    private static let keySpacing: CGFloat = 6
    private static let horizontalPadding: CGFloat = 3

    var body: some View {
        VStack(spacing: 0) {
            predictionBar
                .frame(height: 44)
                .padding(.all, 0)
                .background(Self.board)
            keyboardArea
                .padding(.top, Self.rowSpacing)
                .padding(.bottom, 8)
                .padding(.horizontal, Self.horizontalPadding)
        }
        .background(Self.board)
        .coordinateSpace(name: Self.keyboardSpace)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 10,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 10
            )
        )
        .overlay(alignment: .topLeading) {
            if let key = previewKey, previewFrame != .zero {
                KeyPreviewBubble(text: key.uppercased())
                    .frame(width: previewFrame.width * 1.5,
                           height: previewFrame.height * 1.8)
                    .position(x: previewFrame.midX,
                              y: previewFrame.minY - previewFrame.height * 0.55)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
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
        proxy?.playInputClick()

        state.currentPartial = ""
        state.predictions = predictionEngine.topPredictions()
        evaluateAutoCapAfterContextChange()
    }

    // MARK: - Keyboard rows

    private static let letterRowCount: CGFloat = 4 // 3 letter rows + bottom
    private static var keyboardAreaHeight: CGFloat {
        keyHeight * letterRowCount + rowSpacing * (letterRowCount - 1)
    }

    @ViewBuilder
    private var keyboardArea: some View {
        GeometryReader { geo in
            let keyWidth = max(
                10,
                (geo.size.width - Self.keySpacing * 9) / 10
            )
            if state.isSymbolMode {
                symbolLayout(keyWidth: keyWidth)
            } else {
                letterLayout(keyWidth: keyWidth)
            }
        }
        .frame(height: Self.keyboardAreaHeight)
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

    private func letterLayout(keyWidth: CGFloat) -> some View {
        let rows = keyboardLayout
        let rtl = state.nativeLanguage.isRTL
        let indent = (keyWidth + Self.keySpacing) / 2
        let funcWidth = keyWidth * 1.5
        return VStack(spacing: Self.rowSpacing) {
            HStack(spacing: Self.keySpacing) {
                ForEach(rtl ? rows[0].reversed() : rows[0], id: \.self) { letterKey($0) }
            }
            HStack(spacing: Self.keySpacing) {
                Spacer().frame(width: indent)
                ForEach(rtl ? rows[1].reversed() : rows[1], id: \.self) { letterKey($0) }
                Spacer().frame(width: indent)
            }
            HStack(spacing: Self.keySpacing) {
                shiftKey(width: funcWidth)
                ForEach(rtl ? rows[2].reversed() : rows[2], id: \.self) { letterKey($0) }
                deleteKey(width: funcWidth)
            }
            bottomRow(keyWidth: keyWidth)
        }
    }

    private func symbolLayout(keyWidth: CGFloat) -> some View {
        let funcWidth = keyWidth * 1.5
        return VStack(spacing: Self.rowSpacing) {
            if state.isExtendedSymbols {
                HStack(spacing: Self.keySpacing) {
                    ForEach(["[","]","{","}","#","%","^","*","+","="], id: \.self) { letterKey($0) }
                }
                HStack(spacing: Self.keySpacing) {
                    ForEach(["_","\\","|","~","<",">","€","£","¥","•"], id: \.self) { letterKey($0) }
                }
                HStack(spacing: Self.keySpacing) {
                    altSymbolToggle("123", width: funcWidth)
                    ForEach([".", ",", "?", "!", "'", "\""], id: \.self) { letterKey($0) }
                    deleteKey(width: funcWidth)
                }
            } else {
                HStack(spacing: Self.keySpacing) {
                    ForEach(["1","2","3","4","5","6","7","8","9","0"], id: \.self) { letterKey($0) }
                }
                HStack(spacing: Self.keySpacing) {
                    ForEach(["-","/",":",";","(",")","$","&","@","\""], id: \.self) { letterKey($0) }
                }
                HStack(spacing: Self.keySpacing) {
                    altSymbolToggle("#+=", width: funcWidth)
                    ForEach([".", ",", "?", "!", "'"], id: \.self) { letterKey($0) }
                    deleteKey(width: funcWidth)
                }
            }
            bottomRow(keyWidth: keyWidth)
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
            proxy?.playInputClick()

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
        .background(
            GeometryReader { g in
                Color.clear
                    .onChange(of: previewKey) { _, newValue in
                        if newValue == ch {
                            previewFrame = g.frame(in: .named(Self.keyboardSpace))
                        }
                    }
            }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if previewKey != ch { previewKey = ch }
                }
                .onEnded { _ in
                    if previewKey == ch { previewKey = nil }
                }
        )
    }

    private func displayChar(_ ch: String) -> String {
        guard ch.count == 1, let c = ch.first, c.isLetter else { return ch }
        return (state.capsLock || state.shiftOnce) ? ch.uppercased() : ch
    }

    private func shiftKey(width: CGFloat) -> some View {
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
            proxy?.playInputClick()
        } label: {
            Image(systemName: state.capsLock ? "capslock.fill" : (state.shiftOnce ? "shift.fill" : "shift"))
                .font(Self.funcKeyFont)
                .foregroundStyle(Self.keyText)
                .frame(width: width, height: Self.keyHeight)
                .background(keyShape(filled: Self.funcKeyColor, pressed: pressedKey == id))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(pressedKey == id ? 0.95 : 1.0)
        .frame(minHeight: 44)
    }

    private func deleteKey(width: CGFloat) -> some View {
        let id = "key.delete"
        return Image(systemName: "delete.left")
            .font(Self.funcKeyFont)
            .foregroundStyle(Self.keyText)
            .frame(width: width, height: Self.keyHeight)
            .background(keyShape(filled: Self.funcKeyColor, pressed: pressedKey == id))
            .contentShape(Rectangle())
            .scaleEffect(pressedKey == id ? 0.95 : 1.0)
            .frame(minHeight: 44)
            .onTapGesture {
                flashKey(id)
                performDelete()
                proxy?.playInputClick()
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
        proxy?.playInputClick()
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

    private func altSymbolToggle(_ label: String, width: CGFloat) -> some View {
        let id = "key.alt.\(label)"
        return Button {
            flashKey(id)
            state.isExtendedSymbols.toggle()
            proxy?.playInputClick()
        } label: {
            Text(label)
                .font(Self.funcKeyFont)
                .foregroundStyle(Self.keyText)
                .frame(width: width, height: Self.keyHeight)
                .background(keyShape(filled: Self.funcKeyColor, pressed: pressedKey == id))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(pressedKey == id ? 0.95 : 1.0)
        .frame(minHeight: 44)
    }

    // MARK: - Bottom row

    private func bottomRow(keyWidth: CGFloat) -> some View {
        HStack(spacing: Self.keySpacing) {
            modeKey(width: keyWidth)
            if proxy?.needsInputModeSwitchKey ?? false {
                globeKey(width: keyWidth)
            }
            languagePickerKey(width: keyWidth)
            spaceKey
            returnKey(width: keyWidth * 2)
        }
    }

    private func modeKey(width: CGFloat) -> some View {
        let id = "key.mode"
        return Button {
            flashKey(id)
            state.isSymbolMode.toggle()
            state.isExtendedSymbols = false
            proxy?.playInputClick()
        } label: {
            Text(state.isSymbolMode ? "ABC" : "123")
                .font(Self.funcKeyFont)
                .foregroundStyle(Self.keyText)
                .frame(width: width, height: Self.keyHeight)
                .background(keyShape(filled: Self.funcKeyColor, pressed: pressedKey == id))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(pressedKey == id ? 0.95 : 1.0)
        .frame(minHeight: 44)
    }

    private func globeKey(width: CGFloat) -> some View {
        let id = "key.globe"
        return Button {
            flashKey(id)
            proxy?.advanceToNextInputMode()
            proxy?.playInputClick()
        } label: {
            Image(systemName: "globe")
                .font(Self.funcKeyFont)
                .foregroundStyle(Self.keyText)
                .frame(width: width, height: Self.keyHeight)
                .background(keyShape(filled: Self.funcKeyColor, pressed: pressedKey == id))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(pressedKey == id ? 0.95 : 1.0)
        .frame(minHeight: 44)
    }

    private func languagePickerKey(width: CGFloat) -> some View {
        let id = "key.picker"
        return Button {
            flashKey(id)
            state.showLanguagePicker = true
            proxy?.playInputClick()
        } label: {
            Text(state.targetLanguage.flag)
                .font(.system(size: 18))
                .frame(width: width, height: Self.keyHeight)
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

    private func returnKey(width: CGFloat) -> some View {
        let id = "key.return"
        return Button {
            flashKey(id)
            proxy?.insertText("\n")
            state.currentPartial = ""
            state.predictions = predictionEngine.topPredictions()
            state.shiftOnce = true
            proxy?.playInputClick()
        } label: {
            Text(returnKeyLabel)
                .font(Self.funcKeyFont)
                .foregroundStyle(Self.keyText)
                .frame(width: width, height: Self.keyHeight)
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
            proxy?.playInputClick()
            lastSpaceTapTime = nil
            state.currentPartial = ""
            state.predictions = predictionEngine.topPredictions()
            return
        }
        lastSpaceTapTime = now

        let raw = state.currentPartial
        let cleaned = raw.lowercased().trimmingCharacters(in: .punctuationCharacters)

        if !cleaned.isEmpty,
           let expansion = proxy?.textReplacement(for: cleaned) {
            for _ in 0..<raw.count { proxy?.deleteBackward() }
            proxy?.insertText(expansion)
            proxy?.insertText(" ")
            proxy?.playInputClick()
            state.currentPartial = ""
            state.predictions = predictionEngine.topPredictions()
            evaluateAutoCapAfterContextChange()
            return
        }

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
        proxy?.playInputClick()
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

// MARK: - Key preview bubble

private struct KeyPreviewBubble: View {
    let text: String

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let h = g.size.height
            let bubbleH = h * 0.7
            let tailH = h * 0.3
            ZStack {
                BubbleShape(tailHeight: tailH)
                    .fill(Color(uiColor: .systemBackground))
                    .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
                Text(text)
                    .font(.system(size: bubbleH * 0.6, weight: .regular))
                    .foregroundStyle(Color(uiColor: .label))
                    .frame(width: w, height: bubbleH, alignment: .center)
                    .offset(y: -tailH / 2)
            }
        }
    }
}

private struct BubbleShape: Shape {
    let tailHeight: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let topR: CGFloat = 9
        let bottomR: CGFloat = 5
        let bubbleBottom = rect.maxY - tailHeight

        // Top-left corner
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + topR))
        p.addArc(center: CGPoint(x: rect.minX + topR, y: rect.minY + topR),
                 radius: topR, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        // Top edge to top-right corner
        p.addLine(to: CGPoint(x: rect.maxX - topR, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - topR, y: rect.minY + topR),
                 radius: topR, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        // Right edge to bubble bottom
        p.addLine(to: CGPoint(x: rect.maxX, y: bubbleBottom - bottomR))
        p.addArc(center: CGPoint(x: rect.maxX - bottomR, y: bubbleBottom - bottomR),
                 radius: bottomR, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        // Bottom edge with tail dip in center
        let tailWidth = rect.width * 0.6
        let tailLeftX = rect.midX - tailWidth / 2
        let tailRightX = rect.midX + tailWidth / 2
        p.addLine(to: CGPoint(x: tailRightX, y: bubbleBottom))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY),
                       control: CGPoint(x: tailRightX - tailWidth * 0.15, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: tailLeftX, y: bubbleBottom),
                       control: CGPoint(x: tailLeftX + tailWidth * 0.15, y: rect.maxY))
        // Left edge
        p.addLine(to: CGPoint(x: rect.minX + bottomR, y: bubbleBottom))
        p.addArc(center: CGPoint(x: rect.minX + bottomR, y: bubbleBottom - bottomR),
                 radius: bottomR, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.closeSubpath()
        return p
    }
}
