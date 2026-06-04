# Apple Native Keyboard (iOS 26) — behaviour spec

Research notes on how Apple's stock keyboard behaves on iOS 26, written so we
can **clone its logic** and then **add a translation next to the native word**
in the suggestion chip.

> **Confidence note.** Apple does not publish pixel/colour/timing specs for the
> keyboard. Anything in this doc marked _(observed)_ is reverse-engineered from
> on-device behaviour and may drift between point releases. Anything marked
> _(documented)_ comes from Apple Support / developer docs cited at the bottom.
> Treat _(observed)_ numbers as starting values to tune, not as ground truth.

---

## 1. The two surfaces Apple draws into

Apple's keyboard writes feedback in **two different places**, and this
distinction is the single most important thing for the clone:

| Surface | What lives there | Can a 3rd-party keyboard control it? |
|---|---|---|
| **QuickType bar** — the strip directly above the keys | The 3 suggestion chips | **Yes.** It's part of the keyboard's own input view. |
| **The text field itself** (host app's `UITextField`/`UITextView`) | Inline grey prediction, autocorrect underline, red misspelling underline | **No.** Owned by the host app. A keyboard extension cannot draw here. _(documented — see §7)_ |

Everything Apple does inside the text field (grey inline text, coloured
underlines) is **off-limits** to us unless the text field is in *our own app*.
See §7 for what that means for the clone.

---

## 2. QuickType suggestion bar — layout & logic

Three chips, full keyboard width, equal-ish thirds with vertical hairline
separators between them.

### Slot model (iOS 26)

```
┌─────────────────┬─────────────────┬─────────────────┐
│   "helllo"      │     hello       │     Hello       │   ← chips
└─────────────────┴─────────────────┴─────────────────┘
   slot 0 (left)      slot 1 (mid)     slot 2 (right)
   exact typed word   best candidate    next candidate
   in quotes ""
```

- **Slot 0 (leftmost) — the literal you typed, wrapped in quotation marks**
  `"helllo"`. Tapping it **rejects autocorrect** and keeps your raw input
  verbatim. _(documented: "to keep your typing, tap the option in quotation
  marks")_
- **iOS 26 change:** the leftmost slot is now **always** the "keep exactly what
  I typed" option. In earlier iOS it sometimes held a prediction instead; users
  noted the change because muscle-memory taps on the left chip now do something
  different. _(observed, corroborated by user reports)_
- **Slots 1 & 2 — candidates.** Autocorrect's preferred correction and the
  next-most-likely word/completion. The default/highlighted candidate is the one
  that will be applied automatically if you type a space.

### Quotation-mark rule (the behaviour the user specifically called out)

- The quotes are **presentation only** — they are *not* inserted into the text.
  They are a visual signal that "this chip = your raw characters, untouched."
- Shown whenever the current partial word differs from the autocorrect
  candidate, i.e. whenever autocorrect *would* change something. When your typing
  already matches the dictionary, slot 0 may just show the word without quotes.
  _(observed)_

### Acceptance / rejection

- **Tap a chip** → inserts that word + a trailing space.
- **Type a space / punctuation** → auto-applies the *default candidate* (usually
  slot 1), unless you'd just tapped slot 0.
- **Chips are case-aware** — they mirror the field's autocapitalisation, so the
  same suggestion can appear capitalised at sentence start.

### Inline predictive text (the grey ghost text)

Separate from the chips: as you type, iOS can show a **grey completion inline,
after the cursor, inside the text field**. Tap space (or the dedicated arrow on
some layouts) to accept. This is the "inline predictive text" toggle, controllable
independently of QuickType since iOS 18. **This is the text-field surface — not
clonable from an extension** (§7). _(documented)_

---

## 3. Autocorrect — inline feedback

- When iOS silently autocorrects a word, it **temporarily underlines the
  corrected word** in the text field. Tap the underlined word to get a popover
  offering the original back. _(documented, iOS 17+)_
- The underline is **transient**: it fades / disappears as you keep typing, so
  if you type fast you may never see it. _(observed)_
- Colour: a subtle underline beneath the corrected word _(observed — historically
  a thin blue/grey line; exact colour not documented)_.
- Undo paths: tap the underlined word, **or** tap slot 0 quote-chip *before* the
  space commits, **or** delete-back which on iOS reverts the whole autocorrection
  in one keystroke rather than deleting one character. _(observed)_

---

## 4. Misspelling — the red dotted underline

This is distinct from autocorrect. Autocorrect *changes* a word; spell-check
*flags* a word it can't correct.

- A word the spell checker doesn't recognise gets a **red dotted/dashed
  underline** under it in the text field. _(documented behaviour)_
- **Timing:** it appears after you finish the word (space / punctuation), not
  mid-word. _(observed)_
- **It is also transient** — the red underline disappears once you continue
  typing past it, so a fast typist can miss it. _(observed)_
- **Tap the flagged word** → popover of spelling suggestions; tap one to replace.
- **Caveat:** the red underline renders in native UIKit text fields but **does
  not render in Safari/WebKit text inputs** — so on the web you only find out a
  word is wrong by tapping it. _(observed)_
- False positives are common for valid-but-uncommon words (proper nouns, medical
  terms like "comorbid") because the check is dictionary-membership, not grammar.

---

## 5. iOS 26-specific notes

- Autocorrect moved to a more **context-aware, on-device language-model** driven
  engine (system-wide "Apple Intelligence" prediction), trying to infer intent
  rather than just fixing spelling. _(documented direction; reported)_
- Side effect users reported through 26.0–26.3: homophone over-correction
  (`to`/`too`), characters appearing that weren't tapped, and lag — i.e. the
  *prediction* got more aggressive. **26.4** shipped a fix for "improved keyboard
  accuracy when typing quickly" (dropped-character bug). _(documented in release
  notes / press)_
- The leftmost-chip = "keep what I typed" change described in §2. _(observed)_

**Implication for the clone:** match the *layout and interaction model*, but our
autocorrect/prediction quality is our own (`AutocorrectService` +
`PredictionEngine`). We are not reproducing Apple's LM — and given the 26.x
complaints, a calmer, more predictable correction is arguably a feature.

---

## 6. Visual spec to replicate _(observed / approximate — tune on device)_

| Property | Value to start from |
|---|---|
| Bar height | 37 pt (`ProtoTypeKeyboardView.barHeight`; chip content is vertically centred via an explicit per-chip row height) |
| Chips | 3, equal width, thin vertical separators between them |
| Chip font | System font, ~`UIFont.systemFont(ofSize: 17)`, regular weight |
| Default-candidate emphasis | Subtle — Apple shades the auto-apply candidate's pill, not bold text |
| Quote glyphs | Real curly quotes `" "` around slot-0 word, presentation only |
| Tap feedback | Brief highlight pill on touch-down |
| Light/dark | Follow `UIKeyboardAppearance` of the host field, not just system setting |
| Misspell underline | Red, dotted, under the word, transient (text-field surface only) |
| Autocorrect underline | Thin, subtle, under corrected word, transient (text-field surface only) |

---

## 7. What a 3rd-party keyboard extension actually can and can't do

This is the hard boundary. From Apple's *Custom Keyboard* extension docs:

**Can:**
- Draw and fully control the **QuickType bar** (it's our `inputView`).
- Read context around the cursor: `textDocumentProxy.documentContextBeforeInput`
  / `…AfterInput`.
- Insert/delete/replace text: `insertText`, `deleteBackward`,
  `adjustTextPosition(byCharacterOffset:)`.
- Read the user's text replacements via `requestSupplementaryLexicon` (`UILexicon`).
- Spell-check ourselves with `UITextChecker`
  (`rangeOfMisspelledWord…`, `guessesForWordRange…`) and roll our own autocorrect.

**Cannot:**
- Draw the **grey inline prediction** inside the host text field.
- Draw the **red misspelling underline** or the **autocorrect underline** inside
  the host text field — "custom keyboards **cannot offer inline autocorrection
  controls near the insertion point**." That surface belongs to the host app.
- Select text, access the editing menu, or read the full field contents.
- Reach the network at all **without `RequestsOpenAccess = YES`** (we already set
  this for the MyMemory fallback — see `ARCHITECTURE.md`).
- Type into secure / phone-pad fields (system swaps in the stock keyboard).

**Consequence:** §3 and §4's in-field underlines are **only reproducible inside
our own app's text views**, where we own the `UITextView` and can apply
`NSAttributedString` underline attributes driven by `UITextChecker`. In *other*
apps, the host draws (or doesn't draw) those underlines — we can't. So the clone
of "highlight the misspelled word in the typing box" is:

- **In-app demo field:** fully cloneable (attributed-string red dotted underline +
  tap-to-fix popover).
- **System-wide via the extension:** **not possible**; the most we can do is
  surface the misspelling/correction **in the QuickType bar** instead.

---

## 8. Where the translation goes (mapping to this project)

The user's goal — *clone Apple's logic, but show a translation next to the native
word* — lands almost entirely in the **QuickType bar (slot 0)**, which is exactly
the surface we control and the one this project already uses.

Proposed chip model, layered on Apple's:

```
┌──────────────────────────┬───────────────┬───────────────┐
│  "hola" · hello          │   next-word   │   next-word   │
│   native (quoted) + xlat │   prediction  │   prediction  │
└──────────────────────────┴───────────────┴───────────────┘
```

- **Slot 0 = Apple's "keep what I typed" chip, augmented.** Keep the literal
  native word in quotes (preserving Apple's reject-autocorrect semantics), and
  append the translation in the target language with a separator
  (`·`, `–`, or a dimmed second line). Translation source order is already built:
  local JSON → session cache → Apple Translation → MyMemory (see
  `ARCHITECTURE.md` §"Translation pipeline").
- **Slots 1 & 2 = next-word predictions** (current `PredictionEngine` behaviour),
  unchanged — this matches Apple's "candidates on the right" model.
- **Tap slot 0** → insert the **native** word (not the translation), matching
  Apple's "this chip = your raw text" contract. (If we ever want tap-to-insert-
  translation, that should be a *distinct* affordance to avoid breaking the
  learned gesture.)
- This is consistent with what `FEATURES.md` already describes ("first prediction
  chip shows the word with its translation"); this doc is the *why/spec* behind
  that decision.

### Open question to confirm before building further

The native-word chip already exists. The genuinely new asks here vs. today's
behaviour are: (a) explicitly **quote** the native word in slot 0 to mirror
Apple, and (b) decide the **translation separator/layout** (inline `·` vs.
two-line). Both are visual; flagging rather than assuming — happy to implement
either once confirmed.

---

## Sources

- [Use predictive text on iPhone — Apple Support](https://support.apple.com/guide/iphone/use-predictive-text-iphd4ea90231/ios)
- [How to use Auto-Correction and predictive text — Apple Support](https://support.apple.com/en-us/104995)
- [Disable iPhone inline predictive text in iOS 26 — The Mac Observer](https://www.macobserver.com/tips/how-to/disable-iphone-inline-predictive-text-in-ios-26/)
- [iOS 18 and iOS 26 Autocorrect — Michael Tsai](https://mjtsai.com/blog/2025/11/03/ios-18-and-ios-26-autocorrect/)
- [iPhone Keyboard is a Mess in iOS 26 — The Mac Observer](https://www.macobserver.com/news/ios-keyboard-is-a-mess-in-ios-26-and-users-have-had-enough/)
- [iOS 26.4 Fixes iPhone Keyboard Accuracy Bug — MacRumors](https://www.macrumors.com/2026/03/18/ios-26-4-iphone-keyboard-bug-fix/)
- [App Extension Programming Guide: Custom Keyboard — Apple Developer](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html)
- [Limitations of custom iOS keyboards — inFullMobile (Medium)](https://medium.com/@inFullMobile/limitations-of-custom-ios-keyboards-3be88dfb694)
- [ios-uitextchecker-autocorrect — GitHub](https://github.com/ansonl/ios-uitextchecker-autocorrect)
