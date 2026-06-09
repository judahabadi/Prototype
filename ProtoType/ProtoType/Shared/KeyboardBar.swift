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

/// The QuickType bar: up to three suggestions laid out Apple-style — each in its
/// own equal-width segment, centered, separated by short vertical hairlines (not
/// packed together in the middle). Adaptive — shows as many *full* chips as fit
/// their equal share (3, then 2, then 1) rather than truncating, so a long
/// `word (translation)` pair drops a chip instead of getting cut off. Tap inserts
/// the word; long-press inserts the translation. Pure SwiftUI over plain data so
/// it renders in snapshot tests.
struct ChipToolbar: View {
    let suggestions: [BarSuggestion]
    var pick: (Int) -> Void = { _ in }
    var pickTranslation: (Int) -> Void = { _ in }

    /// Single source of truth for the bar height (the toolbar view is framed to
    /// this in the keyboard). Apple's QuickType bar measures ~49pt (@3x).
    static let barHeight: CGFloat = 50

    private static let font = UIFont.systemFont(ofSize: 16)
    private static let chipHorizontalPadding: CGFloat = 24   // 12pt each side
    private static let separatorWidth: CGFloat = 0.5         // hairline between segments

    var body: some View {
        GeometryReader { geo in
            let shown = fittingChips(in: geo.size.width)
            HStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.index) { offset, item in
                    if offset > 0 {
                        Rectangle()
                            .fill(Color(uiColor: .separator))
                            .frame(width: Self.separatorWidth, height: 18)
                    }
                    chip(item.suggestion, index: item.index)
                        .frame(maxWidth: .infinity)   // equal segment, chip centered within
                }
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
                    .foregroundStyle(.primary)
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

    /// Pick the largest count N (≤3, highest priority first) such that every
    /// chosen chip fits its equal-width segment without truncating. Falls back to
    /// the first chip alone so the bar is never empty.
    private func fittingChips(in width: CGFloat) -> [(index: Int, suggestion: BarSuggestion)] {
        let all = Array(suggestions.prefix(3).enumerated())
        for n in stride(from: min(3, all.count), through: 1, by: -1) {
            let segment = (width - CGFloat(n - 1) * Self.separatorWidth) / CGFloat(n)
            let chosen = all.prefix(n)
            if chosen.allSatisfy({ chipWidth($0.element) <= segment }) {
                return chosen.map { (index: $0.offset, suggestion: $0.element) }
            }
        }
        return all.prefix(1).map { (index: $0.offset, suggestion: $0.element) }
    }
}
