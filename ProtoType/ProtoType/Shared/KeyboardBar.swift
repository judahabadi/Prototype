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

/// The QuickType bar content: a leading target-language flag and up to three
/// suggestions rendered inline as `word (translation)`. Pure SwiftUI over plain
/// data (no KeyboardKit), so it renders in snapshot tests. The owning view maps
/// KeyboardKit's suggestions into `[BarSuggestion]` and wires the index closures.
struct ChipToolbar: View {
    let suggestions: [BarSuggestion]
    let targetFlag: String
    var pick: (Int) -> Void = { _ in }
    var pickTranslation: (Int) -> Void = { _ in }
    var onFlag: () -> Void = {}

    /// Single source of truth for the bar height. Apple's QuickType bar measures
    /// ~49pt (@3x); 46 here renders ~49 after KeyboardKit's reserved-slot padding.
    static let barHeight: CGFloat = 46

    var body: some View {
        HStack(spacing: 0) {
            flagButton
            ForEach(Array(suggestions.prefix(3).enumerated()), id: \.offset) { idx, s in
                chip(s, index: idx)
                if idx < min(suggestions.count, 3) - 1 {
                    Rectangle()
                        .fill(Color(uiColor: .separator))
                        .frame(width: 0.5, height: 18)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if s.isAutocorrect {
                RoundedRectangle(cornerRadius: 8).fill(Color(uiColor: .systemGray4))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { pick(index) }
        .onLongPressGesture(minimumDuration: 0.35) { pickTranslation(index) }
    }

    private var flagButton: some View {
        Button(action: onFlag) {
            Text(targetFlag)
                .font(.system(size: 18))
                .padding(.horizontal, 10)
                .frame(maxHeight: .infinity)
        }
    }
}
