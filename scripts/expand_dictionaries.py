#!/usr/bin/env python3
"""
expand_dictionaries.py

Downloads FreeDict bilingual dictionaries and merges new entries into the
existing translation JSON files under PrototypeKeyboard/Resources/.

Existing entries are treated as hand-verified seeds and are never overwritten.

Run from the repo root:
    python3 scripts/expand_dictionaries.py
"""

import json
import tarfile
import tempfile
import urllib.request
import urllib.error
import xml.etree.ElementTree as ET
from pathlib import Path

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

OUT_DIR = (
    Path(__file__).resolve().parent.parent
    / "ProtoType"
    / "ProtoType"
    / "PrototypeKeyboard"
    / "Resources"
)

# ---------------------------------------------------------------------------
# Language-pair definitions
# Each tuple: (json_src, json_dst, fd_src, fd_dst)
# ---------------------------------------------------------------------------

PAIRS = [
    ("en", "es", "eng", "spa"),
    ("es", "en", "spa", "eng"),
    ("en", "fr", "eng", "fra"),
    ("fr", "en", "fra", "eng"),
    ("en", "de", "eng", "deu"),
    ("de", "en", "deu", "eng"),
    ("en", "pt", "eng", "por"),
    ("pt", "en", "por", "eng"),
    ("en", "ru", "eng", "rus"),
    ("ru", "en", "rus", "eng"),
    ("en", "he", "eng", "heb"),
    ("he", "en", "heb", "eng"),
    ("en", "ar", "eng", "ara"),
    ("ar", "en", "ara", "eng"),
    ("en", "zh", "eng", "zho"),
    ("zh", "en", "zho", "eng"),
    ("en", "hi", "eng", "hin"),
    ("hi", "en", "hin", "eng"),
    ("en", "ja", "eng", "jpn"),
    ("ja", "en", "jpn", "eng"),
    ("en", "bn", "eng", "ben"),
    ("bn", "en", "ben", "eng"),
    ("he", "ar", "heb", "ara"),
    ("ar", "he", "ara", "heb"),
]

FREEDICT_URL = (
    "https://github.com/freedict/fd-dictionaries/releases/latest/download/"
    "freedict-{fd_src}-{fd_dst}.tar.xz"
)

TEI_NS = "http://www.tei-c.org/ns/1.0"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def download_tarball(url: str, dest: Path) -> bool:
    """Download *url* to *dest*. Return True on success, False if not found."""
    try:
        urllib.request.urlretrieve(url, dest)
        return True
    except urllib.error.HTTPError as exc:
        if exc.code in (404, 403):
            return False
        raise
    except urllib.error.URLError:
        return False


def find_tei_member(tf: tarfile.TarFile):
    """Return the first .tei member inside the tarball, or None."""
    for member in tf.getmembers():
        if member.name.endswith(".tei"):
            return member
    return None


def parse_tei(tei_bytes: bytes) -> dict:
    """
    Parse a FreeDict TEI file and return a dict mapping lowercase <orth> text
    to the text of the first <quote> inside a <cit type="trans">.
    """
    entries = {}
    root = ET.fromstring(tei_bytes)
    ns = TEI_NS

    for entry in root.iter(f"{{{ns}}}entry"):
        orth_el = entry.find(f".//{{{ns}}}orth")
        if orth_el is None or not (orth_el.text or "").strip():
            continue
        key = orth_el.text.strip().lower()

        value = None
        for cit in entry.iter(f"{{{ns}}}cit"):
            if cit.get("type") == "trans":
                quote_el = cit.find(f"{{{ns}}}quote")
                if quote_el is not None and (quote_el.text or "").strip():
                    value = quote_el.text.strip()
                    break

        if value:
            entries[key] = value

    return entries


def load_existing(json_path: Path) -> dict:
    """Load an existing JSON translation file, or return {} if missing."""
    if json_path.exists():
        with open(json_path, encoding="utf-8") as fh:
            return json.load(fh)
    return {}


def write_json(json_path: Path, data: dict) -> None:
    """Write *data* as sorted, minified JSON with full Unicode."""
    with open(json_path, "w", encoding="utf-8") as fh:
        json.dump(dict(sorted(data.items())), fh, ensure_ascii=False, separators=(",", ":"))
        fh.write("\n")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    for json_src, json_dst, fd_src, fd_dst in PAIRS:
        json_filename = f"translations_{json_src}_{json_dst}.json"
        json_path = OUT_DIR / json_filename
        url = FREEDICT_URL.format(fd_src=fd_src, fd_dst=fd_dst)

        with tempfile.TemporaryDirectory() as tmp:
            tarball = Path(tmp) / f"freedict-{fd_src}-{fd_dst}.tar.xz"

            if not download_tarball(url, tarball):
                existing = load_existing(json_path)
                print(f"{json_filename}: not available (kept {len(existing)} existing entries)")
                continue

            try:
                with tarfile.open(tarball, "r:xz") as tf:
                    member = find_tei_member(tf)
                    if member is None:
                        existing = load_existing(json_path)
                        print(
                            f"{json_filename}: no .tei file in tarball "
                            f"(kept {len(existing)} existing entries)"
                        )
                        continue
                    tei_bytes = tf.extractfile(member).read()
            except (tarfile.TarError, EOFError) as exc:
                existing = load_existing(json_path)
                print(
                    f"{json_filename}: tarball error — {exc} "
                    f"(kept {len(existing)} existing entries)"
                )
                continue

        try:
            new_entries = parse_tei(tei_bytes)
        except ET.ParseError as exc:
            existing = load_existing(json_path)
            print(
                f"{json_filename}: XML parse error — {exc} "
                f"(kept {len(existing)} existing entries)"
            )
            continue

        existing = load_existing(json_path)
        merged = {**new_entries, **existing}
        added = len(merged) - len(existing)

        write_json(json_path, merged)
        print(f"{json_filename}: {len(merged)} entries total (+{added} from FreeDict)")


if __name__ == "__main__":
    main()
