import SwiftUI
import UIKit
import KeyboardKit

/// The keyboard view. KeyboardKit owns everything — typing, capitalization, and
/// the autocomplete toolbar — so the bar height matches iOS on every device with
/// no custom sizing (no jump when switching keyboards). We render KeyboardKit's
/// native toolbar (which shows our Norvig suggestions and their translation via
/// the suggestion subtitle) and only add a globe button for the language picker.
struct ProtoTypeKeyboardView: View {

    @Bindable var state: KeyboardState
    let services: Keyboard.Services
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
            toolbar: { params in
                HStack(spacing: 0) {
                    // KeyboardKit's native autocomplete toolbar — device-adaptive
                    // height, renders our suggestions + translation subtitle.
                    params.view
                        .frame(maxWidth: .infinity)
                    languageButton
                }
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

    /// Globe button that opens the native/target language picker. Sized to fill
    /// the toolbar's height so it never forces the bar taller.
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
