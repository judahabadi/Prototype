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

## ⏳ 3. Capitalization (autocap, i→I)
Direction agreed: own rule layer. Not yet locked.

## ⏳ 4. Next-word prediction
Direction agreed: own per-language quantized trigram n-gram (wordfreq data,
mmap'd, marisa-backed). Not yet locked.

## ⏳ 5. Smart punctuation
Direction agreed: own rules (~30 lines). Not yet locked.

## ⏳ 6. Smart/context AI prediction
Direction agreed: n-gram is offline ceiling; cloud LLM only as silent
Full-Access upgrade. Not yet locked.

## ⏳ 7. Revert-on-backspace (undo autocorrect)
Direction agreed: own, critical UX. Not yet locked.

## ⏳ 8. Auto-spacing
Direction agreed: own. Not yet locked.

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
