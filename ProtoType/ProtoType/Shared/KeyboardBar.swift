import SwiftUI
import UIKit

/// Plain model for one suggestion shown in the bar. Decoupled from KeyboardKit so
/// the bar view is pure SwiftUI and can be rendered in snapshot tests.
struct BarSuggestion: Identifiable {
    let id = UUID()
    let text: String
    let subtitle: String?
    let isAutocorrect: Bool

    init(text: String, subtitle: String? = nil, isAutocorrect: Bool = false) {
        self.text = text
        self.subtitle = subtitle
        self.isAutocorrect = isAutocorrect
    }
}

/// The QuickType bar: up to three suggestions rendered inline as
/// `word (translation)`. Adaptive — shows as many *full* chips as fit the width
/// (3, then 2, then 1) rather than truncating, so a long `word (translation)`
/// pair drops a chip instead of getting cut off. Tap inserts the word;
/// long-press inserts the translation. Pure SwiftUI over plain data so it renders
/// in snapshot tests.
struct ChipToolbar: View {
    let suggestions: [BarSuggestion]
    var pick: (Int) -> Void = { _ in }
    var pickTranslation: (Int) -> Void = { _ in }

    /// Single source of truth for the bar height. Apple's QuickType bar measures
    /// ~49pt (@3x); 46 renders ~49 after KeyboardKit's reserved-slot padding.
    static let barHeight: CGFloat = 46

    private static let font = UIFont.systemFont(ofSize: 16)
    private static let chipHorizontalPadding: CGFloat = 24   // 12pt each side
    private static let separatorWidth: CGFloat = 9

    var body: some View {
        GeometryReader { geo in
            let shown = fittingChips(in: geo.size.width)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                ForEach(Array(shown.enumerated()), id: \.element.index) { offset, item in
                    if offset > 0 {
                        Rectangle()
                            .fill(Color(uiColor: .separator))
                            .frame(width: 0.5, height: 18)
                    }
                    chip(item.suggestion, index: item.index)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func chip(_ s: BarSuggestion, index: Int) -> some View {
        HStack(spacing: 4) {
            Text(s.text)
                .foregroundStyle(.primary)
            if let sub = s.subtitle, !sub.isEmpty {
                Text("(\(sub))")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 16, weight: .regular))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)   // show full text, never truncate
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .background {
            if s.isAutocorrect {
                RoundedRectangle(cornerRadius: 8).fill(Color(uiColor: .systemGray4))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { pick(index) }
        .onLongPressGesture(minimumDuration: 0.35) { pickTranslation(index) }
    }

    // MARK: - Adaptive fitting

    private func label(_ s: BarSuggestion) -> String {
        if let sub = s.subtitle, !sub.isEmpty { return "\(s.text) (\(sub))" }
        return s.text
    }

    private func chipWidth(_ s: BarSuggestion) -> CGFloat {
        let textW = (label(s) as NSString).size(withAttributes: [.font: Self.font]).width
        return ceil(textW) + Self.chipHorizontalPadding
    }

    /// Greedily include suggestions (highest priority first) while they fit at
    /// their full width; always show at least one.
    private func fittingChips(in width: CGFloat) -> [(index: Int, suggestion: BarSuggestion)] {
        var available = width - 8   // small edge margin
        var out: [(index: Int, suggestion: BarSuggestion)] = []
        for (i, s) in suggestions.prefix(3).enumerated() {
            let need = chipWidth(s) + (out.isEmpty ? 0 : Self.separatorWidth)
            if out.isEmpty || need <= available {
                out.append((index: i, suggestion: s))
                available -= need
            } else {
                break
            }
        }
        return out
    }
}
