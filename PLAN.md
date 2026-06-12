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

## ⏳ 9. Personalization (learn user words)
Direction agreed: own — writable user dict in App Group + frequency ranker.
Not yet locked.

## ⏳ 10. Complex-script input (hi/bn/pa/ar)
Direction agreed: DIY static key→codepoint maps; copy Keyman's MIT layout
tables (data only, no Keyman code). OS does shaping. Not yet locked.

## ⏳ 11. CJK input (zh/ja)
Direction agreed: jieba (MIT) / IPADIC (BSD) segmentation + frequency.
Not yet locked.

## ⏳ 12. Word completion (prefix)
Direction agreed: keep existing trie, store in marisa-trie (BSD leg).
Not yet locked.

## ⏳ 13. Learn-English: English → native hint (Mode A)
Direction agreed: own bilingual word dict; CC-CEDICT for zh (CC-BY-SA ⚠️);
ar/Indic data needs sourcing. Word-level only. Not yet locked.

## ⏳ 14. Learn-English: native → English (Mode B)
Direction agreed: pinyin→English phase 2; Arabizi→English phase 3 (data weak).
Not yet locked.

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
