import SwiftUI
import UIKit
import KeyboardKit

/// The keyboard view. KeyboardKit owns typing, capitalization, and the
/// autocomplete pipeline; we render a compact custom bar that shows our Norvig
/// suggestions inline as `word (translation)` and a target-language flag button
/// that opens the language picker.
struct ProtoTypeKeyboardView: View {

    @Bindable var state: KeyboardState
    let services: Keyboard.Services
    let autocompleteContext: AutocompleteContext
    let reloadEngines: () -> Void

    private var isRTL: Bool {
        state.nativeLanguage.isRTL || state.targetLanguage.isRTL
    }

    var body: some View {
        KeyboardView(
            services: services,
            buttonContent: { $0.view },
            buttonView: { $0.view },
            collapsedView: { $0.view },
            emojiKeyboard: { $0.view },
            toolbar: { _ in
                ChipToolbar(
                    services: services,
                    autocompleteContext: autocompleteContext,
                    state: state
                )
                .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
            }
        )
        // Control the height KeyboardKit RESERVES for the toolbar slot. Without this
        // KeyboardKit reserves its own (taller) default, so the bar reads tall no
        // matter what height our content uses. This is one device-uniform value
        // (Apple's bar is a fixed height on all iPhones; only the keys scale).
        .autocompleteToolbarStyle(Autocomplete.ToolbarStyle(height: ChipToolbar.barHeight))
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
        .sheet(isPresented: $state.showLanguagePicker) {
            LanguagePickerView(state: state, reloadEngines: reloadEngines)
        }
    }
}

/// Compact QuickType bar. Reads KeyboardKit's autocomplete suggestions (fed by
/// the Norvig service) and renders each inline as `word (translation)`. Tap
/// inserts the word; long-press inserts the translation. A leading flag button
/// (the target language) opens the language picker.
struct ChipToolbar: View {

    let services: Keyboard.Services
    @ObservedObject var autocompleteContext: AutocompleteContext
    @Bindable var state: KeyboardState

    /// The single source of truth for the bar height — drives both KeyboardKit's
    /// reserved toolbar slot (via `.autocompleteToolbarStyle`) and our content.
    /// Apple's bar is a fixed height across iPhones, so one value is uniform.
    /// Measured Apple's QuickType bar at ~49pt (@3x); 46 renders ~49 after the
    /// slot's padding, matching Apple. Content is centered via maxHeight below.
    static let barHeight: CGFloat = 46

    var body: some View {
        HStack(spacing: 0) {
            flagButton
            let suggestions = autocompleteContext.suggestions
            ForEach(Array(suggestions.prefix(3).enumerated()), id: \.offset) { idx, suggestion in
                chip(suggestion)
                if idx < min(suggestions.count, 3) - 1 {
                    Rectangle()
                        .fill(Color(uiColor: .separator))
                        .frame(width: 0.5, height: 18)
                }
            }
        }
        // Fill the slot KeyboardKit reserves (set via .autocompleteToolbarStyle).
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chip(_ suggestion: Autocomplete.Suggestion) -> some View {
        HStack(spacing: 4) {
            Text(suggestion.text)
                .foregroundStyle(.primary)
            if let sub = suggestion.subtitle, !sub.isEmpty {
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
            if suggestion.isAutocorrect {
                RoundedRectangle(cornerRadius: 8).fill(Color(uiColor: .systemGray4))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            services.actionHandler.handle(suggestion)
        }
        .onLongPressGesture(minimumDuration: 0.35) {
            if let sub = suggestion.subtitle, !sub.isEmpty {
                services.actionHandler.handle(Autocomplete.Suggestion(text: sub))
            }
        }
    }

    /// Target-language flag → opens the language picker.
    private var flagButton: some View {
        Button {
            state.showLanguagePicker = true
        } label: {
            Text(state.targetLanguage.flag)
                .font(.system(size: 18))
                .padding(.horizontal, 10)
                .frame(maxHeight: .infinity)
        }
    }
}

/// Long-press accent/diacritic callout data for letter keys. Covers the
/// Latin-script target languages; other keys fall back to KeyboardKit's callouts.
enum AccentCallouts {
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
