import SwiftUI
import UIKit
import KeyboardKit

/// The keyboard view. KeyboardKit owns all typing, capitalization, and the
/// autocomplete pipeline; we only render a custom toolbar (`ChipToolbar`) that
/// shows our Norvig + translation suggestions, and wire up accent callouts.
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

/// Our QuickType bar. Reads KeyboardKit's autocomplete suggestions (fed by the
/// Norvig service) and renders each as `word (translation)`. Tap inserts the
/// word; long-press inserts the translation. KeyboardKit applies the autocorrect
/// suggestion on space natively.
struct ChipToolbar: View {

    let services: Keyboard.Services
    @ObservedObject var autocompleteContext: AutocompleteContext
    @Bindable var state: KeyboardState

    var body: some View {
        HStack(spacing: 0) {
            let suggestions = autocompleteContext.suggestions
            ForEach(Array(suggestions.prefix(3).enumerated()), id: \.offset) { idx, suggestion in
                chip(suggestion)
                if idx < min(suggestions.count, 3) - 1 {
                    Rectangle()
                        .fill(Color(uiColor: .separator))
                        .frame(width: 0.5, height: 20)
                }
            }
            languageButton
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
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
        .padding(.horizontal, 10)
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

    private var languageButton: some View {
        Button {
            state.showLanguagePicker = true
        } label: {
            Image(systemName: "globe")
                .font(.system(size: 17))
                .foregroundStyle(.primary)
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
