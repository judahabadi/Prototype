# Features

## What the keyboard does

### Core

- **Live translation chip** — after typing a word and pressing space, the first prediction chip shows the word with its translation in the target language. Translation is looked up immediately from the local dictionary, then updated asynchronously via Apple Translation or MyMemory if not found locally.
- **Next-word predictions** — slots 1 and 2 show the most likely next words based on bigram/trigram statistics, filtered to exclude words already used nearby in the current document.
- **Autocorrect** — `AutocorrectService` corrects typos before the word is committed. Applied on space, after lexicon expansion, before translation.
- **iOS text replacements** — checks `UIInputViewController.requestSupplementaryLexicon` on load and appearance. User's text replacements (e.g. `omw` → `On my way!`) are expanded on space, taking priority over autocorrect.

### Input behavior

- **Character preview popup** — pressing a letter key shows a native-style popup bubble with the uppercase letter; releasing inserts the character and dismisses the popup.
- **Autocap** — respects `autocapitalizationType` from the host field (none / words / sentences / all characters).
- **Field-aware layout** — reads `keyboardType` from the host field and switches layout:
  - `.numberPad`, `.decimalPad`, `.phonePad` → numeric-only layout
  - `.URL` → adds `.com` and `/` keys to space row
  - `.emailAddress` → adds `@` and `.` keys to space row
- **Secure entry / one-time code** — when `isSecureTextEntry == true` or `textContentType == .oneTimeCode`, predictions are hidden and autocorrect/lexicon expansion are skipped.
- **Return key auto-dim** — when the host requests `enablesReturnKeyAutomatically`, the return key is dimmed and non-interactive until text is present.
- **Space-bar cursor slide** — dragging horizontally on the space bar moves the cursor left/right via `adjustTextPosition(byCharacterOffset:)`.
- **Selected text translation** — when text is selected, the prediction bar collapses to a single full-width chip showing the translation of the selection; tapping replaces the selection with the translation.
- **Globe long-press** — tap advances to next keyboard; long-press shows the native iOS input-mode popup.

### System integration

- **Sound** — `UIDevice.current.playInputClick()` + `UIInputViewAudioFeedback` conformance. Automatically respects Settings → Sounds & Haptics → Keyboard Clicks.
- **Haptics** — deliberately removed. iOS has no public API to read the "Keyboard Feedback › Haptic" system toggle, so haptics are suppressed entirely rather than ignoring the user's preference.
- **Open Access** — declared in the extension Info.plist (`RequestsOpenAccess: true`). Required for the MyMemory API fallback.
- **Paste chip** — when the pasteboard has a string, a "Paste" chip appears in the prediction bar (iOS 16+).
- **Dark mode** — when the host app requests `.dark` keyboard appearance, the keyboard overrides to a dark color scheme regardless of system setting.
- **Memory pressure** — `didReceiveMemoryWarning()` evicts the `TranslationService` word cache and the `PredictionEngine` in-memory data to avoid the OS killing the extension.

---

## Deliberately not implemented

| Feature | Reason |
|---|---|
| Swipe-to-type (glide) | Complex; not in scope |
| Long-press alternate characters (é, ñ, ü) | Not in scope |
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
