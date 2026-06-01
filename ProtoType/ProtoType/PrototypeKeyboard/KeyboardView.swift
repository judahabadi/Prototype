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
    @State private var pasteAvailable: Bool = false

    private static let keyboardSpace = "kb"

    private var isRTL: Bool {
        state.nativeLanguage.isRTL || state.targetLanguage.isRTL
    }

    // MARK: - Field-aware policy

    private enum KeyboardVariant {
        case standard, numeric, url, email
    }

    private var keyboardVariant: KeyboardVariant {
        if proxy?.textContentType == .oneTimeCode { return .numeric }
        if proxy?.textContentType == .emailAddress { return .email }
        switch proxy?.keyboardType ?? .default {
        case .numberPad, .decimalPad, .phonePad, .numbersAndPunctuation, .asciiCapableNumberPad:
            return .numeric
        case .URL:
            return .url
        case .emailAddress:
            return .email
        default:
            return .standard
        }
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

    private var shouldAutocorrect: Bool {
        guard shouldPredict else { return false }
        if proxy?.spellCheckingType == .no { return false }
        if proxy?.autocorrectionType == .no { return false }
        return true
    }

    private var shouldExpandReplacement: Bool { shouldPredict }

    private var preferredScheme: ColorScheme? {
        switch proxy?.keyboardAppearance ?? .default {
        case .dark: return .dark
        case .light: return .light
        default: return nil
        }
    }

    private var returnIsDisabled: Bool {
        guard proxy?.enablesReturnKeyAutomatically == true else { return false }
        let before = proxy?.documentContextBeforeInput ?? ""
        let selection = proxy?.selectedText ?? ""
        return before.isEmpty && selection.isEmpty
    }

    private enum AutocapPolicy { case none, words, sentences, all }
    private var autocapPolicy: AutocapPolicy {
        switch proxy?.autocapitalizationType ?? .sentences {
        case .none: return .none
        case .words: return .words
        case .allCharacters: return .all
        case .sentences: return .sentences
        @unknown default: return .sentences
        }
    }

    // Native iOS keyboard palette (matches the stock keyboard in light + dark).
    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
    private static let board = dynamic(
        light: UIColor(red: 209/255, green: 211/255, blue: 217/255, alpha: 1),
        dark: UIColor(red: 43/255, green: 43/255, blue: 43/255, alpha: 1)
    )
    private static let letterKeyColor = dynamic(
        light: .white,
        dark: UIColor(red: 106/255, green: 106/255, blue: 106/255, alpha: 1)
    )
    private static let funcKeyColor = dynamic(
        light: UIColor(red: 174/255, green: 179/255, blue: 190/255, alpha: 1),
        dark: UIColor(red: 67/255, green: 67/255, blue: 67/255, alpha: 1)
    )
    private static let keyShadow = Color.black.opacity(0.3)
    private static let keyText = Color(uiColor: .label)

    private static let keyFont = Font.system(size: 22, weight: .regular)
    private static let funcKeyFont = Font.system(size: 15, weight: .regular)
    private static let cornerRadius: CGFloat = 5
    private static let keyHeight: CGFloat = 42
    private static let rowSpacing: CGFloat = 12
    private static let keySpacing: CGFloat = 6
    private static let horizontalPadding: CGFloat = 3

    var body: some View {
        VStack(spacing: 0) {
            if shouldPredict {
                predictionBar
                    .frame(height: 44)
                    .background(Self.board)
                Rectangle()
                    .fill(Color(uiColor: .separator))
                    .frame(height: 0.5)
            }
            keyboardArea
                .padding(.top, Self.rowSpacing)
                .padding(.bottom, 8)
                .padding(.horizontal, Self.horizontalPadding)
        }
        .background(Self.board)
        .preferredColorScheme(preferredScheme)
        .coordinateSpace(name: Self.keyboardSpace)
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
            evaluateAutoCap()
            refreshPasteAvailable()
        }
        .onChange(of: state.contextSignal) {
            evaluateAutoCap()
        }
    }

    private func refreshPasteAvailable() {
        pasteAvailable = UIPasteboard.general.hasStrings
    }

    private func recentlyTypedWords() -> Set<String> {
        let before = (proxy?.documentContextBeforeInput ?? "").lowercased()
        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        return Set(
            before
                .components(separatedBy: separators)
                .filter { !$0.isEmpty && $0.count > 1 }
        )
    }

    private func freshPredictions(after committedWord: String) -> [Prediction] {
        let recent = recentlyTypedWords()
        let pool = predictionEngine.topPredictions(excluding: committedWord, limit: 10)
        return pool
            .filter { !recent.contains($0.source.lowercased()) }
            .prefix(2)
            .map { $0 }
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
        guard let s = UIPasteboard.general.string, !s.isEmpty else {
            pasteAvailable = false
            return
        }
        proxy?.insertText(s)
        proxy?.playInputClick()
        state.currentPartial = ""
        pasteAvailable = false
        if shouldPredict {
            state.predictions = predictionEngine.topPredictions()
        }
        evaluateAutoCap()
    }

    private func selectionTranslateChip(selection: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "character.bubble")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.blue)
            Text("Translate “\(selection)”")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.blue)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            translateSelection(selection)
        }
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
        if !isCursorMidWord {
            proxy?.insertText(" ")
        }
        proxy?.playInputClick()

        state.currentPartial = ""
        state.predictions = predictionEngine.topPredictions()
        evaluateAutoCap()
    }

    private var isCursorMidWord: Bool {
        guard let after = proxy?.documentContextAfterInput, let first = after.first else {
            return false
        }
        return first.isLetter || first.isNumber
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
            if keyboardVariant == .numeric || state.isSymbolMode {
                symbolLayout(keyWidth: keyWidth)
            } else {
                letterLayout(keyWidth: keyWidth)
            }
        }
        .frame(height: Self.keyboardAreaHeight)
    }

    private var variantAccessory: String? {
        switch keyboardVariant {
        case .url: return ".com"
        case .email: return "@"
        default: return nil
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

    private func letterLayout(keyWidth: CGFloat) -> some View {
        let rows = keyboardLayout
        let rtl = state.nativeLanguage.isRTL
        let indent = (keyWidth + Self.keySpacing) / 2
        let funcWidth = keyWidth * 1.5 + Self.keySpacing / 2
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
                let upper = state.capsLock || state.shiftOnce || autocapPolicy == .all
                if upper {
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

            if isLetter && shouldPredict {
                state.predictions = predictionEngine.predictions(for: state.currentPartial)
            }
        } label: {
            Text(displayChar(ch))
                .font(Self.keyFont)
                .foregroundStyle(Self.keyText)
                .frame(maxWidth: .infinity, minHeight: Self.keyHeight, maxHeight: Self.keyHeight)
                .background(keyShape(filled: Self.letterKeyColor, pressed: pressedKey == id))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(pressedKey == id ? 0.95 : 1.0)
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
        let upper = state.capsLock || state.shiftOnce || autocapPolicy == .all
        return upper ? ch.uppercased() : ch
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
    }

    // MARK: - Bottom row

    private func bottomRow(keyWidth: CGFloat) -> some View {
        HStack(spacing: Self.keySpacing) {
            modeKey(width: keyWidth)
            if proxy?.needsInputModeSwitchKey ?? false {
                globeKey(width: keyWidth)
            }
            languagePickerKey(width: keyWidth)
            if let accessory = variantAccessory {
                accessoryKey(text: accessory, width: keyWidth * 1.3)
            }
            spaceKey
            returnKey(width: keyWidth * 2)
        }
    }

    private func accessoryKey(text: String, width: CGFloat) -> some View {
        let id = "key.accessory.\(text)"
        return Button {
            flashKey(id)
            proxy?.insertText(text)
            proxy?.playInputClick()
            state.currentPartial = ""
            if shouldPredict {
                state.predictions = predictionEngine.topPredictions()
            }
        } label: {
            Text(text)
                .font(Self.funcKeyFont)
                .foregroundStyle(Self.keyText)
                .frame(width: width, height: Self.keyHeight)
                .background(keyShape(filled: Self.funcKeyColor, pressed: pressedKey == id))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(pressedKey == id ? 0.95 : 1.0)
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
    }

    private func globeKey(width: CGFloat) -> some View {
        let id = "key.globe"
        return Image(systemName: "globe")
            .font(Self.funcKeyFont)
            .foregroundStyle(Self.keyText)
            .frame(width: width, height: Self.keyHeight)
            .background(keyShape(filled: Self.funcKeyColor, pressed: pressedKey == id))
            .contentShape(Rectangle())
            .scaleEffect(pressedKey == id ? 0.95 : 1.0)
            .onTapGesture {
                flashKey(id)
                proxy?.advanceToNextInputMode()
                proxy?.playInputClick()
            }
            .onLongPressGesture(minimumDuration: 0.4) {
                flashKey(id)
                proxy?.showInputModeList()
                proxy?.playInputClick()
            }
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
    }

    @State private var spaceDragStartX: CGFloat? = nil
    @State private var spaceDragLastX: CGFloat? = nil
    @State private var spaceDidDrag: Bool = false

    private var spaceKey: some View {
        let id = "key.space"
        return Text("")
            .font(Self.funcKeyFont)
            .foregroundStyle(Self.keyText)
            .frame(maxWidth: .infinity, minHeight: Self.keyHeight, maxHeight: Self.keyHeight)
            .background(keyShape(filled: Self.letterKeyColor, pressed: pressedKey == id))
            .contentShape(Rectangle())
            .scaleEffect(pressedKey == id ? 0.95 : 1.0)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if spaceDragStartX == nil {
                            spaceDragStartX = value.location.x
                            spaceDragLastX = value.location.x
                            spaceDidDrag = false
                            pressedKey = id
                            return
                        }
                        guard let last = spaceDragLastX else { return }
                        let dx = value.location.x - last
                        if !spaceDidDrag && abs(value.location.x - (spaceDragStartX ?? 0)) > 10 {
                            spaceDidDrag = true
                        }
                        if spaceDidDrag, abs(dx) >= 8 {
                            let chars = Int(dx / 8)
                            if chars != 0 {
                                proxy?.adjustTextPosition(byCharacterOffset: chars)
                                spaceDragLastX = value.location.x
                            }
                        }
                    }
                    .onEnded { _ in
                        if !spaceDidDrag {
                            flashKey(id)
                            handleSpace()
                        }
                        pressedKey = nil
                        spaceDragStartX = nil
                        spaceDragLastX = nil
                        spaceDidDrag = false
                    }
            )
    }

    private func returnKey(width: CGFloat) -> some View {
        let id = "key.return"
        let disabled = returnIsDisabled
        return Button {
            guard !disabled else { return }
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
        .opacity(disabled ? 0.4 : 1.0)
        .allowsHitTesting(!disabled)
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
           shouldExpandReplacement,
           let expansion = proxy?.textReplacement(for: cleaned) {
            for _ in 0..<raw.count { proxy?.deleteBackward() }
            proxy?.insertText(expansion)
            proxy?.insertText(" ")
            proxy?.playInputClick()
            state.currentPartial = ""
            if shouldPredict {
                state.predictions = predictionEngine.topPredictions()
            }
            evaluateAutoCap()
            return
        }

        var finalWord = cleaned
        if !cleaned.isEmpty && shouldAutocorrect {
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

        evaluateAutoCap()

        guard !finalWord.isEmpty, shouldPredict else {
            if shouldPredict {
                state.predictions = predictionEngine.topPredictions()
            }
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
        combined.append(contentsOf: freshPredictions(after: finalWord))
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

    /// Sets shiftOnce based on the current text context, respecting the
    /// host field's autocapitalizationType.
    private func evaluateAutoCap() {
        guard state.currentPartial.isEmpty else { return }
        let ctx = proxy?.documentContextBeforeInput ?? ""
        switch autocapPolicy {
        case .none:
            state.shiftOnce = false
        case .all:
            state.capsLock = true
        case .words:
            state.shiftOnce = true
        case .sentences:
            if ctx.isEmpty
                || ctx.hasSuffix(". ")
                || ctx.hasSuffix("! ")
                || ctx.hasSuffix("? ")
                || ctx.hasSuffix("\n") {
                state.shiftOnce = true
            }
        }
    }

    private func applyCapitalization(_ word: String) -> String {
        switch autocapPolicy {
        case .none:
            return word
        case .all:
            return word.uppercased()
        case .words:
            return word.prefix(1).uppercased() + word.dropFirst()
        case .sentences:
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
