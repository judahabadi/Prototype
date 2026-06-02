# Translation Dictionaries

## Location

```
ProtoType/ProtoType/PrototypeKeyboard/Resources/
```

Two types of files:

| File pattern | Purpose |
|---|---|
| `translations_{src}_{dst}.json` | Word-level translation dictionary |
| `ngrams_{lang}.json` | Bigram/trigram statistics for next-word prediction |

---

## Translation dictionary format

Flat JSON object, all keys lowercase:

```json
{
  "hello": "hola",
  "world": "mundo",
  "the": "el"
}
```

File name encodes the language pair using ISO 639-1 codes, e.g.:
- `translations_en_es.json` — English → Spanish
- `translations_ar_en.json` — Arabic → English

Lookup at runtime: `TranslationService.loadDictionary(pairKey:)` looks for `translations_{src}_{dst}.json` in the main bundle, lowercases all keys on load, and caches the result until the language pair changes.

---

## Shipped pairs (18 files)

| File | Direction |
|---|---|
| `translations_en_es.json` | English → Spanish |
| `translations_en_fr.json` | English → French |
| `translations_en_de.json` | English → German |
| `translations_en_pt.json` | English → Portuguese |
| `translations_en_ru.json` | English → Russian |
| `translations_en_hi.json` | English → Hindi |
| `translations_en_zh.json` | English → Mandarin |
| `translations_en_ja.json` | English → Japanese |
| `translations_en_ar.json` | English → Arabic |
| `translations_es_en.json` | Spanish → English |
| `translations_fr_en.json` | French → English |
| `translations_de_en.json` | German → English |
| `translations_pt_en.json` | Portuguese → English |
| `translations_ru_en.json` | Russian → English |
| `translations_hi_en.json` | Hindi → English |
| `translations_zh_en.json` | Mandarin → English |
| `translations_ja_en.json` | Japanese → English |
| `translations_ar_en.json` | Arabic → English |

---

## Scripts

All scripts live in `scripts/` and write to `ProtoType/ProtoType/PrototypeKeyboard/Resources/`.

### `build_dictionaries.py`

Embeds all vocabulary directly in the script as Python dicts and writes the JSON files. Fastest way to add or correct hand-verified entries — edit the Python dict, re-run.

```bash
python3 scripts/build_dictionaries.py
```

### `build_seed_dictionaries.py`

Generates ~150 common-word translations per pair from a shared ROWS table (one row = one English word + translations across all 10 languages). Useful for bootstrapping a new language pair. Writes the same output files.

```bash
python3 scripts/build_seed_dictionaries.py
```

### `expand_dictionaries.py`

Downloads FreeDict bilingual dictionaries (TEI XML format) and merges new entries into the existing JSON files. Existing seed entries are **never overwritten** — seeds are treated as hand-verified ground truth. Good for expanding from ~150 entries to a few thousand without losing manual corrections.

```bash
python3 scripts/expand_dictionaries.py
```

Requires network access. FreeDict files are fetched from `ftp.gnu.org`. If a language pair isn't covered by FreeDict, the script skips it silently.

---

## Expanding dictionaries for App Store quality

Current seed files have ~150–180 entries each. For a better user experience, each file should have 3k–10k entries. Recommended sources (all permissively licensed):

| Source | License | How to use |
|---|---|---|
| **Wiktionary** (CC BY-SA) | CC BY-SA 3.0 | Use [`wiktextract`](https://github.com/tatuylonen/wiktextract) to parse Wiktionary dumps into word/translation pairs |
| **FreeDict** | GPL | `expand_dictionaries.py` already handles this |
| **OPUS parallel corpora** ([opus.nlpl.eu](https://opus.nlpl.eu/)) | Mixed (CC0/BY) | Download aligned sentence pairs, extract word frequencies, take top N |
| **Tatoeba** (CC BY) | CC BY 2.0 | Download sentence pairs, extract aligned content words |

After expanding, drop files into `PrototypeKeyboard/Resources/` with the same flat `{ "word": "translation" }` schema and rebuild. No code changes needed.

---

## Ngram files

`ngrams_{lang}.json` powers the next-word prediction engine (`PredictionEngine`). Format is a JSON object mapping a preceding word (or bigram key) to an array of likely next words with frequency scores. The engine binary-searches sorted keys for O(log n) prefix lookups.

These files are generated separately from translation dictionaries — see `PredictionEngine.swift` for the expected schema. Do not confuse them with translation files.

---

## Adding a new language pair

1. Add the language to the `Language` enum in `Shared/LanguageConfig.swift` with its ISO code, Apple Translation locale, display name, native name, flag, and RTL flag.
2. Create `translations_{src}_{dst}.json` and `translations_{dst}_{src}.json` in `Resources/` using one of the scripts above.
3. Create `ngrams_{lang}.json` for next-word prediction (if not already present).
4. Add the new JSON files to the Xcode project (drag into `Resources/` group, check PrototypeKeyboard target).
5. Apple Translation may not support the new pair — `TranslationService` will fall back to MyMemory automatically.
