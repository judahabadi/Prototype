import SwiftUI
import UIKit
import KeyboardKit
import Translation

/// The keyboard view. KeyboardKit owns typing, capitalization, and the
/// autocomplete pipeline; we map its suggestions into `ChipToolbar` (a pure,
/// snapshot-testable bar in Shared/) and reserve the toolbar slot height to match
/// Apple's bar across devices.
struct ProtoTypeKeyboardView: View {

    @Bindable var state: KeyboardState
    let services: Keyboard.Services
    @ObservedObject var autocompleteContext: AutocompleteContext

    /// Live Apple-Translation glosses for the bar (shared so the controller can
    /// evict the cache on a memory warning). Accessed lazily so the singleton is
    /// only touched from the main-actor view body/handlers.
    private var translator: AppleTranslator { .shared }

    private var isRTL: Bool {
        state.nativeLanguage.isRTL || state.targetLanguage.isRTL
    }

    /// The words currently in the bar — used to request glosses and as the
    /// `.onChange` key (Apple Translation is async; glosses fill in after).
    private var currentWords: [String] {
        autocompleteContext.suggestions.prefix(3).map(\.text)
    }

    private var barSuggestions: [BarSuggestion] {
        autocompleteContext.suggestions.prefix(3).map {
            BarSuggestion(text: $0.text,
                          subtitle: translator.translation(for: $0.text),
                          isAutocorrect: $0.isAutocorrect)
        }
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
                    suggestions: barSuggestions,
                    pick: { apply($0, translation: false) },
                    pickTranslation: { apply($0, translation: true) }
                )
                // Force the bar's height. A custom toolbar is sized by its content
                // (so it rendered short, sitting on the keys); .autocompleteToolbarStyle
                // only sizes KeyboardKit's own toolbar, not ours.
                .frame(height: ChipToolbar.barHeight)
                .frame(maxWidth: .infinity)
                .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
            }
        )
        // Reserve the toolbar slot height so the bar matches Apple's height across
        // devices (KeyboardKit's default slot is taller). See ChipToolbar.barHeight.
        .autocompleteToolbarStyle(Autocomplete.ToolbarStyle(height: ChipToolbar.barHeight))
        .keyboardCalloutActions { params in
            // Long-press accent popups (é, ñ, ü, ç…) for Latin-script languages.
            if case let .character(char) = params.action,
               char.count == 1, let c = char.first,
               let base = AccentCallouts.variants[Character(c.lowercased())] {
                let chars = c.isUppercase ? base.uppercased() : base
                return chars.map { KeyboardAction.character(String($0)) }
            }
            return params.standardActions()
        }
        // Apple Translation: keep a live session for the current language pair and
        // translate the words shown in the bar. Glosses land asynchronously.
        .translationTask(translator.configuration) { session in
            await translator.run(session: session, initial: currentWords)
        }
        .onChange(of: currentWords) { _, words in
            translator.request(words)
        }
        .onChange(of: [state.nativeLanguage, state.targetLanguage]) { _, _ in
            translator.configure(from: state.nativeLanguage, to: state.targetLanguage)
        }
        .onAppear {
            translator.configure(from: state.nativeLanguage, to: state.targetLanguage)
        }
    }

    /// Apply the suggestion at `index`: tap inserts the word, long-press inserts
    /// the translation. Uses the real KeyboardKit suggestion so it replaces the
    /// current word correctly.
    private func apply(_ index: Int, translation: Bool) {
        let suggestions = autocompleteContext.suggestions
        guard index < suggestions.count else { return }
        let suggestion = suggestions[index]
        if translation {
            if let gloss = translator.translation(for: suggestion.text), !gloss.isEmpty {
                services.actionHandler.handle(Autocomplete.Suggestion(text: gloss))
            }
        } else {
            services.actionHandler.handle(suggestion)
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
