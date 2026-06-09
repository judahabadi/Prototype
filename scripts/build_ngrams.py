#!/usr/bin/env python3
"""
Build next-word prediction tables from the OPUS OpenSubtitles corpus.

OpenSubtitles is movie/TV dialogue, so its bigrams match how people actually
text — unlike web-page text, where "the" is followed by "lord/company". The
corpus is streamed (never fully downloaded) and only the first MAX_LINES per
language are read; that is more than enough for the common-word bigrams that
ever surface as suggestions.

Writes, into the keyboard's Resources/ folder:
  ngrams_{lang}.json   head token -> [top-K next tokens]   (same schema as before)
  unigrams_en.txt      word<TAB>count                       (English fallback list)

Latin / Arabic / Cyrillic / Devanagari languages use whitespace word tokens,
filtered to the language's own script (this removes the English pollution that
was in the old Hindi file). Chinese and Japanese have no word spacing, so they
use character-level bigrams, matching the existing zh/ja files.

Source: OPUS OpenSubtitles v2018, https://opus.nlpl.eu/OpenSubtitles-v2018.php
"""
import json
import re
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path

RES = Path(__file__).resolve().parent.parent / "ProtoType/ProtoType/PrototypeKeyboard/Resources"
URL = "https://object.pouta.csc.fi/OPUS-OpenSubtitles/v2018/mono/{}.txt.gz"

LANGS = ["ar", "de", "en", "es", "fr", "hi", "ja", "pt", "ru", "zh"]
CJK_LANGS = {"zh", "ja"}

# OPUS filenames that differ from our language code (Chinese is split by region).
SOURCE = {"zh": "zh_cn"}

MAX_LINES = 5_000_000   # lines read per language (streamed, then we stop)
TOP_K = 5               # next tokens kept per head
MAX_HEADS = 8000        # cap output size / extension memory
MIN_BIGRAM = 2          # ignore one-off pairs
PRUNE_AT = 6_000_000    # drop singletons when the pair table grows past this

# Per-script token validators for word languages.
SCRIPT_RE = {
    "ar": re.compile(r"^[؀-ۿ]{2,}$"),
    "ru": re.compile(r"^[Ѐ-ӿ]{2,}$"),
    "hi": re.compile(r"^[ऀ-ॿ]{2,}$"),
}
# Latin incl. common accents; allows internal apostrophe/hyphen (won't, l'amie).
LATIN_RE = re.compile(r"^[a-zÀ-ſ]+(?:['’-][a-zÀ-ſ]+)*$")
LATIN_LANGS = {"en", "de", "es", "fr", "pt"}

# CJK code blocks: ideographs + hiragana + katakana.
CJK_RE = re.compile(r"[㐀-䶿一-鿿぀-ゟ゠-ヿ]")

EDGE_PUNCT = " \t\r\n.,;:!?\"'()[]{}<>«»…‚„“”‘’—–-*/\\|@#%^&_=+~`"


def word_tokens(line, lang):
    """Whitespace tokens, lowercased, stripped of edge punctuation, kept only
    if they are entirely in the language's script."""
    valid = SCRIPT_RE.get(lang)
    out = []
    for raw in line.lower().split():
        tok = raw.strip(EDGE_PUNCT)
        if not tok:
            continue
        if valid is not None:
            if valid.match(tok):
                out.append(tok)
        elif LATIN_RE.match(tok):
            out.append(tok)
    return out


def cjk_runs(line):
    """Yield runs of consecutive CJK characters so we only pair adjacent ones."""
    run = []
    for ch in line:
        if CJK_RE.match(ch):
            run.append(ch)
        elif run:
            yield run
            run = []
    if run:
        yield run


def build(lang):
    url = URL.format(SOURCE.get(lang, lang))
    print(f"[{lang}] streaming {url}", flush=True)
    proc = subprocess.Popen(
        f"curl -sL --fail '{url}' | gunzip -c",
        shell=True, stdout=subprocess.PIPE, bufsize=1 << 20,
    )
    pairs = defaultdict(Counter)   # head -> Counter(next)
    unigrams = Counter()
    seen_pairs = 0
    cjk = lang in CJK_LANGS

    for i, raw in enumerate(proc.stdout):
        if i >= MAX_LINES:
            break
        line = raw.decode("utf-8", "ignore")
        if cjk:
            for run in cjk_runs(line):
                for a, b in zip(run, run[1:]):
                    pairs[a][b] += 1
                    seen_pairs += 1
        else:
            toks = word_tokens(line, lang)
            unigrams.update(toks)
            for a, b in zip(toks, toks[1:]):
                pairs[a][b] += 1
                seen_pairs += 1
        if seen_pairs > PRUNE_AT:
            for h in list(pairs):
                c = pairs[h]
                for w in [w for w, n in c.items() if n < 2]:
                    del c[w]
                if not c:
                    del pairs[h]
            seen_pairs = sum(len(c) for c in pairs.values())

    proc.stdout.close()
    proc.wait()

    # Rank heads by total frequency, keep the most common MAX_HEADS.
    ranked = sorted(pairs.items(), key=lambda kv: sum(kv[1].values()), reverse=True)
    table = {}
    for head, c in ranked:
        nexts = [w for w, n in c.most_common() if n >= MIN_BIGRAM][:TOP_K]
        if nexts:
            table[head] = nexts
        if len(table) >= MAX_HEADS:
            break

    out = RES / f"ngrams_{lang}.json"
    out.write_text(json.dumps(table, ensure_ascii=False, sort_keys=True), encoding="utf-8")
    print(f"[{lang}] wrote {len(table)} heads -> {out.name}", flush=True)

    # English drives the engine's unigram fallback / completions.
    if lang == "en":
        top = unigrams.most_common(50000)
        uni = RES / "unigrams_en.txt"
        uni.write_text("".join(f"{w}\t{n}\n" for w, n in top), encoding="utf-8")
        print(f"[en] wrote {len(top)} unigrams -> {uni.name}", flush=True)


if __name__ == "__main__":
    targets = sys.argv[1:] or LANGS
    for lang in targets:
        build(lang)
