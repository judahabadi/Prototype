# The 14 Issues — Execution Plan

Status: 🔒 locked = decided, ready to build. ⏳ = not yet locked.
When all 14 are locked → execute in priority order.

---

## 🔒 1. Typos (autocorrect)

**Decision: SymSpell primary + own weighted-Levenshtein ranker. UITextChecker as safety net.**

Pipeline:
```
input word
  → SymSpell delete-lookup (candidate generation, maxEditDistance=2)
  → QWERTY-proximity-weighted Levenshtein re-rank (KEEP existing)
  → frequency tie-break (KEEP existing)
  → top suggestion
```

Per-language split:
- **en, es, fr, pt, ru, de** → SymSpell + own ranker (strong free data)
- **hi, bn, pa, ar** → SymSpell on freq-derived wordlists + UITextChecker fill-in
  when `UITextChecker.availableLanguages` has the language (device-dependent)
- **zh, ja** → NOT this pipeline (issue #11, segmentation)

Components:
- SymSpell: port gdetari/SymSpellSwift (MIT) or reimplement Symmetric Delete in-house
- Delete: existing brute-force candidate *search* loop
- Keep: weighted-Levenshtein *scoring fn*, lemmatizer, frequency ranker, trie

Constraints/gates:
- [ ] **GATE: on-device memory benchmark first** — SymSpell delete index per
      language, target device, design budget ~40MB total (not 70MB).
      Tune `prefixLength` / `maxEditDistance=1` for long words if over.
- [ ] Decide: ship precomputed delete index (bigger bundle, instant load)
      vs build on first launch (smaller bundle, slow cold start). → benchmark decides.
- One language loaded at a time (existing rule).

Out of scope for #1 (handled elsewhere): contractions (#2), caps (#3),
phrase caps (Wikidata), CJK (#11).

---

## 🔒 2. Contractions (wont → won't)

**Decision: own curated replacement map.**

- Per-language map, ~50 entries (en: wont→won't, cant→can't, im→I'm,
  dont→don't, its→it's …; fr: elisions; es/pt/de/ru: small or empty)
- Runs BEFORE/independent of SymSpell — these are real words, edit distance
  can't catch them (wont = valid word, distance 0)
- Ambiguous ones (its/it's, well/we'll) gated by n-gram context (#4) once it
  exists; until then suggest-don't-replace for those
- Plain data file per language, ships in bundle. ~30 lines of code.
- Not applicable: zh/ja/hi/bn/pa/ar (no apostrophe contractions)

## 🔒 3. Capitalization (autocap, i→I, World Cup)

**Decision: own rule layer, Apple supplies the trigger, MIT code as reference.**

- Trigger: respect the field's `autocapitalizationType` via
  `textDocumentProxy.documentContextBeforeInput` traits
  (sentences/words/allCharacters/none) — Apple gives the signal free
- Logic: own ~20 lines — sentence start, standalone i→I, after ". "
- Reference code: KeyboardKit open-source base (MIT) autocap logic — copy,
  don't depend
- Edge cases: small per-language abbreviation list ("Dr.", "e.g.", "z.B.")
  so they don't trigger sentence-caps
- Proper nouns + phrases (paris→Paris, world cup→World Cup): phrase dict
  built from Wikidata labels (CC0), last 2–3 words lookup
- German noun capitalization: NOT rule-feasible; rely on dictionary casing
  in suggestions, don't auto-force
- Applies to: en, es, fr, pt, de, ru only. Skip: zh, ja, ar, hi, bn, pa
  (no capitals)

## 🔒 4. Next-word prediction

**Decision: own n-gram now. Cloud LLM deferred until ~10k users.**

Phase 1 (now — offline core):
- Per-language quantized trigram n-gram model, built from wordfreq data
  (CC-BY-SA ⚠️ one-time legal glance)
- Stored compact (marisa-trie or own binary format — NOT KenLM-linked, LGPL),
  mmap'd, one language resident at a time
- Same model answers prefix completion ranking with the trie (#12)
- Context gate for contractions (#2) ambiguous cases (its/it's)

Phase 2 (at ~10k users — online upgrade layer):
- Cloud LLM (Haiku-class, e.g. claude-haiku-4-5: $1/M in, $5/M out)
- ONLY for big moments: sentence completion (ghost text), whole-message
  fix-up, learn-English hints. Debounced, ~50 calls/user/day ≈ $0.15/user/mo
- NEVER per keystroke (200–500ms latency + cost kills it)
- Requires network + Full Access; silent upgrade, n-gram remains the floor

Ruled out: Keyman (WebView lock-in, no context model), KeyboardKit Gold
($500/mo), Fleksy Core SDK ($269+/mo to ship — revisit only if n-gram quality
disappoints AND subscriber math supports it; free tier exists for testing),
Apple (blocked for 3rd-party keyboards), offline neural (won't fit ~40MB).

## 🔒 5. Smart punctuation

**Decision: own rule layer + per-language punctuation table.**

- Rules: double-space → ". ", straight → curly quotes, "--" → "—",
  auto-space cleanup around punctuation
- Per-language quote/punct table (crib from KeyboardKit open-source, MIT):
  en "…", de „…", fr « … » (spaces inside), ja 「…」, ar «…»
- Arabic native marks: ، ؟ ؛ + RTL behavior (part of the RTL requirement)
- Respect the field's smartQuotesType/smartDashesType when the app disables
  them (never curl quotes in code editors)
- User off-switch in settings
- Field traits auto-applying from custom keyboards is unreliable — do the
  substitution ourselves, verify no double-transformation on device

## 🔒 6. Smart/context AI prediction

**Decision: merged into #4.** N-gram is the offline ceiling; the cloud LLM
phase-2 layer in #4 IS the smart prediction. No separate work item.

## 🔒 7. Revert-on-backspace (undo autocorrect)

**Decision: Style A — backspace immediately after a correction restores the
user's original word.** (Gboard/SwiftKey behavior.)

- State: remember last correction `{typed, replaced, range}` — one struct
- Backspace right after autocorrect → restore the original typed word exactly
- Invalidate the moment the user types anything else, taps elsewhere, or moves
  the cursor (cursor-move bug otherwise undoes wrong text)
- One level only — no undo history stack
- Re-learn signal: a revert feeds personalization (#9) — revert same word
  twice → add to user dictionary so we stop correcting it
- No vendor; own build, critical UX. ~30 lines + the invalidation guards

## 🔒 8. Auto-spacing

**Decision: prediction tap inserts word + trailing space.**

- Accepting a prediction/correction from the bar → insert word + one space,
  user keeps typing immediately (Gboard/Apple behavior)
- Backspace right after accepting → remove word + its added space together
  (reuses the #7 last-action struct)
- Collapse accidental double spaces from the insertion (typing "," after an
  auto-space → "word, " not "word , ")
- Double-space → ". " lives in #5 (punctuation), not here
- CJK exception: NO auto-space for zh/ja (no spaces between words)
- Own build, no vendor

## 🔒 9. Personalization

**Decision: MINIMAL — "don't-correct" list only. No typing-history learning.**

- Revert same word twice (#7 signal) → add to don't-correct list; autocorrect
  never touches that word again
- One small wordlist in the App Group container, on-device only, never
  uploaded. No frequency learning, no habit tracking
- "Clear list" button in settings
- Privacy claim stays: "we collect nothing — everything stays on your device"
- Explicitly skipped: frequency boosting of user's repeated words (revisit
  only if autocorrect quality complaints demand it)

## 🔒 10. Complex-script input (hi/bn/pa/ar)

**Decision: DIY static key→codepoint maps; copy Keyman's MIT layout tables
(data only — zero Keyman code ships).**

- InScript layouts for Hindi/Bengali/Punjabi, standard Arabic 101/102
- Emit codepoints in logical order; CoreText/OS does ALL shaping (conjuncts,
  matras, Arabic joining, lam-alef) — verified
- MIT sources to copy: keymanapp/keyboards basic_kbdinhin / basic_kbdinben /
  basic_kbdinpun / basic_kbda1
- Gotchas: codepoint-wise backspace (use unicodeScalars, not grapheme
  clusters), dotted-circle ◌ base for matra keycaps, AltGr layer for rare
  chars, ZWJ/ZWNJ keys optional
- Revisit Keyman (JS-in-JSC hack) ONLY if phonetic input (namaste→नमस्ते)
  becomes a requirement

## 🔒 11. CJK input (zh/ja)

**Decision: own pipeline — jieba dict (MIT) for Mandarin pinyin, IPADIC/
UniDic-BSD for Japanese, + existing frequency ranker.**

- Separate subsystem from the Latin pipeline; SymSpell/edit-distance does not
  apply
- Mandarin: pinyin input → candidate characters/words ranked by frequency
- Japanese: romaji→kana mapping + kana→kanji candidates (IPADIC data)
- Phase: built AFTER Latin + Indic/Arabic languages ship (execution order #5)

## 🔒 12. Word completion (prefix)

**Decision: keep existing trie logic, move storage to marisa-trie.**

- Keep: prefix-lookup logic, frequency ranking (existing in-house)
- Change: storage → marisa-trie (s-yata/marisa-trie, BSD-2 leg), 50–100×
  smaller than in-RAM sorted array — frees budget for SymSpell (#1) and
  n-gram (#4) under the ~40MB cap
- C++ lib, small Swift bridging layer
- Later: n-gram (#4) re-ranks completions by context
- zh/ja excluded (no prefix completion in the Latin sense — #11 pipeline)

## 🔒 13. Learn-English: English → native hint (Mode A)

**Decision: own bilingual word dictionary, word-level only, all 12 langs.**

- Type English → see meaning in user's language above the word
- Data: CC-CEDICT for zh (CC-BY-SA ⚠️ same legal glance as wordfreq);
  Wiktionary dumps as candidate source for ar/Indic (needs sourcing pass)
- Word-level only — NOT sentence translation (doesn't fit offline/40MB);
  sentence-level arrives via the #4 cloud layer at 10k users
- Ships per-language as data files, loaded with the active language

## 🔒 14. Learn-English: native → English (Mode B)

**Decision: phased. Pinyin→English (zh) = phase 2; Arabizi→English (ar) =
phase 3.**

- Type your way (pingguo / tuffaha) → English word suggested
- zh first: pinyin→English via CC-CEDICT (well-trodden path)
- ar later: Arabizi data is thin — needs sourcing before commitment
- Other languages: only if A-mode usage proves demand

## 🔒 15. Keyboard key grids (per-language layouts)

**Decision: one SwiftUI grid engine + per-language layout files. 6 grids
cover all 12 languages.**

- Apple provides NO keys to custom keyboards — we draw every key
- Grids: QWERTY+accents (en/es/pt + zh/ja input), AZERTY (fr), QWERTZ (de),
  ЙЦУКЕН (ru), Arabic RTL (ar), InScript (hi/bn/pa — 1 layout, 3 char sets)
- zh/ja have NO native grid: pinyin/romaji typed on QWERTY → candidate bar
  (#11) shows characters
- One reusable grid component: rows, key sizing, shift/space/globe/return,
  symbol layer, long-press accent popups
- Layout data: KeyboardKit open-source (MIT, iOS-style layouts) + Keyman MIT
  tables (#10) + published standards (InScript/ЙЦУКЕН/Arabic 101)
- Globe key cycles user's enabled languages; grid swaps with dictionary

---

## Cross-cutting (apply to all)
- Real memory budget: **~40MB** (jetsam reality), not 70MB. One language resident.
- Language auto-switch: NLLanguageRecognizer constrained to user's picked 2–3
  languages; flip only after ~2–3 words confidence; globe key manual override.
- Licensing: MIT/BSD/MPL/CC0 only in-bundle. No GPL dicts (de/ar/hi/bn/pa
  Hunspell blocked). CC-BY-SA (wordfreq, CC-CEDICT) needs one-time legal glance.
- **Open gaps:** Punjabi data sourcing; ar/Indic bilingual dicts; swipe-typing
  go/no-go decision.

## Execution order (once all locked)
1. SymSpell memory benchmark (gate for #1)
2. English end-to-end (#1–9, 12)
3. es/fr/de/pt/ru (same machinery)
4. ar + Indic (#10 + thin data)
5. zh/ja (#11)
6. pa (once data solved)
7. Learn-English modes (#13, #14)
