# Features

> **v1 rebuild (current).** The keyboard was rebuilt on free KeyboardKit with a
> permissive engine stack. Key changes from the original build:
> - **Autocapitalization is owned entirely by KeyboardKit** — typed letters
>   delegate to KeyboardKit's standard handler, which recomputes case from the
>   document context (fixes the mid-sentence-capital bug). We no longer drive case.
> - **Translation is offline-only** — local bundled JSON dictionaries; the Apple
>   Translation session and the MyMemory web fallback were removed.
> - **Engines** live in `Shared/Engines/` (used by app, extension, and tests):
>   `AutocorrectEngine` (UITextChecker + keyboard-distance re-ranking, fixes
>   `wint→wont`), `NextWordEngine` (Norvig bigram + backoff), `TranslationEngine`
>   (offline JSON). Public-domain Norvig `count_1w` data ships as `unigrams_en.txt`.
> - **Suggestion chips** show a book-style gloss `word (translation)`; tap inserts
>   the word, long-press inserts the translation; the whole chip row scrolls as one
>   unit when content is long. Slot 0 keeps the committed word after space.
> - **Apple-parity additions:** A1 undo-autocorrect (a backspace right after a
>   correction reverts it), A2 smart spacing (`word ,`→`word,`), A3 double-capital
>   fix (`THe`→`The`).
> - **v1 scope:** English-focused typing; iPhone-style `123` layout (no number row);
>   swipe typing, dictation, custom emoji plane, and predictive emoji are deferred.
>
> Some bullets below describe the original build and may be partly superseded.

## What the keyboard does

### Core

- **Live translation chip** — after typing a word and pressing space, the first prediction chip shows the word with its translation in the target language, looked up from the local bundled dictionary (offline only; no network fallback in the v1 rebuild).
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

- Expand local dictionaries to 3k–10k entries per pair (see `DICTIONARY.md`)
- Dictation handoff button
- In-app haptic on/off toggle
- Long-press alternate characters
