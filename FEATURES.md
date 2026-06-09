# Features

> **v1 rebuild (current).** The keyboard was rebuilt on free KeyboardKit with a
> permissive engine stack. Key changes from the original build:
> - **Autocapitalization is owned entirely by KeyboardKit** — typed letters
>   delegate to KeyboardKit's standard handler, which recomputes case from the
>   document context (fixes the mid-sentence-capital bug). We no longer drive case.
> - **Translation is Apple Translation only** — on-device via Apple's Translation
>   framework (`Shared/Engines/AppleTranslator.swift`). The pack for the selected
>   language pair is downloaded from the app (`LanguagePackManager`); the keyboard
>   then glosses words from that model. The bundled JSON dictionaries and the
>   MyMemory web fallback are no longer used. Because Apple Translation is async,
>   glosses appear a beat after the word and only once the pack is downloaded.
> - **Engines** live in `Shared/Engines/` (used by app, extension, and tests):
>   `AutocorrectEngine` (UITextChecker + keyboard-distance re-ranking, fixes
>   `wint→wont`), `NextWordEngine` (OpenSubtitles bigram + backoff), `AppleTranslator`
>   (Apple Translation session + cache). Word-frequency data ships
>   as `unigrams_en.txt`. `TranslationEngine` (offline JSON) is now unused by the
>   keyboard — the `translations_*.json` resources are dead and can be removed.
> - **Suggestion chips** sit in Apple-style equal segments separated by short
>   hairlines and show a book-style gloss `word (translation)`; tap inserts the
>   word, long-press inserts the translation. Slot 0 keeps the committed word after
>   space.
> - **Apple-parity additions:** A1 undo-autocorrect (a backspace right after a
>   correction reverts it), A2 smart spacing (`word ,`→`word,`), A3 double-capital
>   fix (`THe`→`The`).
> - **v1 scope:** English-focused typing; iPhone-style `123` layout (no number row);
>   swipe typing, dictation, custom emoji plane, and predictive emoji are deferred.
>
> Some bullets below describe the original build and may be partly superseded.

## What the keyboard does

### Core

- **Live translation chip** — prediction chips show the word with its translation in the target language, translated on-device by Apple's Translation framework (gloss appears asynchronously once the language pack is downloaded; no gloss before that, and predictions/autocorrect still work).
- **Next-word predictions** — slots 1 and 2 show the most likely next words based on bigram/trigram statistics, filtered to exclude words already used nearby in the current document.
- **Autocorrect** — `AutocorrectService` corrects typos before the word is committed. Applied on space, after lexicon expansion, before translation.
- **iOS text replacements** — checks `UIInputViewController.requestSupplementaryLexicon` on load and appearance. User's text replacements (e.g. `omw` → `On my way!`) are expanded on space, taking priority over autocorrect.

### Input behavior

- **Character preview popup** — pressing a letter key shows a native-style popup bubble with the uppercase letter; releasing inserts the character and dismisses the popup.
- **Autocap** — owned by KeyboardKit (it respects the field's `autocapitalizationType` and recomputes case from context). The v1 rebuild no longer drives case itself.
- **Field-aware layout** — reads `keyboardType` from the host field and switches layout:
  - `.numberPad`, `.decimalPad`, `.phonePad` → numeric-only layout
  - `.URL` → adds `.com` and `/` keys to space row
  - `.emailAddress` → adds `@` and `.` keys to space row
- **Secure entry / one-time code** — when `isSecureTextEntry == true` or `textContentType == .oneTimeCode`, predictions are hidden and autocorrect/lexicon expansion are skipped.
- **Return key auto-dim** — when the host requests `enablesReturnKeyAutomatically`, the return key is dimmed and non-interactive until text is present.
- **Space-bar cursor slide** — dragging horizontally on the space bar moves the cursor left/right via `adjustTextPosition(byCharacterOffset:)`.
- **Long-press accents** — holding a letter key shows a callout of its diacritic variants (é, ñ, ü, ç…) for Latin-script languages, via `AccentCallouts` wired through KeyboardKit's `.keyboardCalloutActions` modifier. Non-mapped keys fall back to KeyboardKit's standard callouts.
- **Accelerated delete** — holding backspace deletes character-by-character, then escalates to whole-word deletion after a sustained hold (`backspaceRepeats` counter in `ProtoTypeActionHandler`).
- **Selected text translation** — when text is selected, the prediction bar shows a chip with the translation of the selection (wrapping to two lines so long sentences stay readable); tapping replaces the selection with the translation.
- **Selected text fix** — alongside the translation, an on-device "fix" chip offers a cleaned-up version of the highlighted sentence (UITextChecker spelling correction plus tidy casing/spacing/end punctuation via `SentenceFix`); tapping replaces the selection. No network.
- **Globe long-press** — tap advances to next keyboard; long-press shows the native iOS input-mode popup.

### System integration

- **Sound** — `UIDevice.current.playInputClick()` + `UIInputViewAudioFeedback` conformance. Automatically respects Settings → Sounds & Haptics → Keyboard Clicks.
- **Haptics** — deliberately removed. iOS has no public API to read the "Keyboard Feedback › Haptic" system toggle, so haptics are suppressed entirely rather than ignoring the user's preference.
- **Open Access** — declared in the extension Info.plist (`RequestsOpenAccess: true`). No longer required for translation (offline-only in the v1 rebuild); still enables haptics/full-access behaviours.
- **Paste chip** — when the pasteboard has a string, a "Paste" chip appears in the prediction bar (iOS 16+).
- **Dark mode** — when the host app requests `.dark` keyboard appearance, the keyboard overrides to a dark color scheme regardless of system setting.
- **Memory pressure** — `didReceiveMemoryWarning()` evicts the `TranslationService` word cache and the `PredictionEngine` in-memory data to avoid the OS killing the extension.

---

## Deliberately not implemented

| Feature | Reason |
|---|---|
| Swipe-to-type (glide) | Complex; not in scope (not in free KeyboardKit) |
| Custom themes / color picker | Not in scope |
| In-app haptic toggle | Can add later behind an App Group bool |
| Dictation button | Needs Open Access; architecture ready, UI not built |
| Hardware keyboard pass-through | Optional; skeleton in plan, not implemented |

---

## Supported languages

10 languages. Any pair where native ≠ target is valid. Pairs with English on one side have the richest local dictionaries.

| Language | ISO | RTL |
|---|---|---|
| English | `en` | No |
| Spanish | `es` | No |
| French | `fr` | No |
| German | `de` | No |
| Portuguese | `pt` | No |
| Russian | `ru` | No |
| Hindi | `hi` | No |
| Mandarin | `zh` | No |
| Japanese | `ja` | No |
| Arabic | `ar` | Yes |

Apple Translation framework supports most pairs natively. For pairs it doesn't support (e.g. Bengali, Hebrew — removed from the shipped list), the code falls back to MyMemory with a 4-second timeout.

Mandarin uses `zh-Hans` (Simplified) with Apple Translation and `zh` for local dict lookup. Portuguese uses `pt-BR`.

---

## Settings (host app)

- **Native language** — the language the user types in.
- **Target language** — the language translations are shown in.
- Native and target cannot be the same; if they match after load, target is swapped to a default.
- Settings are stored in `AppGroup.defaults` under keys `AppGroup.nativeKey` and `AppGroup.targetKey` and read by the extension at `viewDidLoad`.

---

## Planned / backlog

- Dictation handoff button
- In-app haptic on/off toggle
- Long-press alternate characters

---

## Apple Translation only (shipped — replaces the JSON dictionaries)

**Goal (done):** Apple's on-device Translation framework is the single translation
source. Any word translates on-device once the pair's pack is downloaded.

### App
- `LanguagePackManager` checks `LanguageAvailability().status` for the selected
  pair and, when supported but not installed, sets a `TranslationSession.Configuration`.
- `LanguagePackStatusView` (shown under the language pickers in both onboarding and
  the Home tab) drives a `.translationTask` that calls `prepareTranslation()` —
  **selecting a pair is the trigger**; the row shows checking/downloading/ready/
  unsupported. iOS shows its one-time consent sheet on the first download.

### Keyboard
- `AppleTranslator` (`Shared/Engines/`) holds the live `TranslationSession` handed
  in by a `.translationTask` in `ProtoTypeKeyboardView` and an async word→gloss
  cache the bar reads. Before the pack is downloaded → no gloss (predictions +
  autocorrect still work).

### Unchanged
- Word **prediction** (`NextWordEngine`) and **autocorrect** (`AutocorrectEngine`)
  are not translation — they stay.

### Risks / tradeoffs
1. **Extension memory** — Apple Translation runs inside the keyboard extension; the
   cache is evicted on `didReceiveMemoryWarning`.
2. **Async** — glosses appear a beat after the word (the bar renders the chip first,
   then re-renders when the gloss lands).
3. **Coverage** — Apple supports a fixed set of pairs; unsupported pairs get no gloss.
4. **Gated on download** — no pack = no gloss; the app drives the download.
5. **Unverified on-device** — wiring was written without an Xcode build; needs a
   real build/run to confirm the session works in the extension.

### Dead code to remove (left in place to avoid project-file churn)
- `Resources/translations_*.json` and the JSON-loading path in `TranslationEngine`
  are no longer used by the keyboard. Safe to delete from Xcode when convenient
  (`TranslationEngine`'s in-memory `loadDictionary` path is still unit-tested).
