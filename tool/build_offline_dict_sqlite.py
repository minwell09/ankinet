#!/usr/bin/env python3
"""
Builds the standalone SQLite dictionary asset (`assets/nlp/offline_dict.db`)
and compact morphology/irregular-lemma bundle (`assets/nlp/nlp_bundle.json`).

Data Sources & Licenses:
1. Open Dict Data (`open-dict-data/ipa-dict`: en_US.txt + en_UK.txt)
   - American English (125,927 entries) & British English (65,119 entries) IPA pronunciations
   - License: MIT / CC BY-SA 4.0 (https://github.com/open-dict-data/ipa-dict)
2. Wiktionary / MinhQND / WikDict / Skypedia EN-VI Dictionary (104,700+ EN-VI entries)
   - License: Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)
3. CMU Pronouncing Dictionary (CMUdict v0.7b - fallback for any word absent from ipa-dict)
   - License: BSD / Public Domain (Carnegie Mellon University)
4. Princeton WordNet 3.0 Morphological Exception Lists (verb.exc, noun.exc, adj.exc, adv.exc)
   - License: Princeton WordNet License
"""
import json
import os
import re
import shutil
import sqlite3
import sys
import zipfile

sys.path.insert(0, "/home/minwell0309/vocab_nlp_backend")
from app.services.morphology_engine import morphology_engine
from app.services.phonetics_engine import phonetics_engine
from app.services.translator_service import translator_service
from build_offline_bundle import EXTRA_EN_VI_WORDS, generate_offline_data

POS_MAP = {
    "N": "noun",
    "V": "verb",
    "A": "adj",
    "ADJ": "adj",
    "D": "adv",
    "ADV": "adv",
    "P": "prep",
    "C": "conj",
    "I": "interj",
    "IDIOM": "idiom",
    "PHRASE": "phrase",
}

POS_VI_LABEL = {
    "noun": "n.",
    "verb": "v.",
    "adj": "adj.",
    "adv": "adv.",
    "prep": "prep.",
    "conj": "conj.",
    "interj": "interj.",
    "idiom": "idiom",
    "phrase": "phrase",
    "vocab": "vocab",
}


def load_wordnet_exceptions(wordnet_zip_path: str) -> dict:
    irregulars = {}
    if not os.path.exists(wordnet_zip_path):
        return irregulars
    with zipfile.ZipFile(wordnet_zip_path) as zf:
        for fname in ["wordnet/verb.exc", "wordnet/noun.exc", "wordnet/adj.exc", "wordnet/adv.exc"]:
            if fname not in zf.namelist():
                continue
            for line in zf.read(fname).decode("utf-8").splitlines():
                parts = line.strip().split()
                if len(parts) >= 2:
                    surface, lemma = parts[0].lower(), parts[1].lower()
                    if surface.isalpha() and lemma.isalpha() and surface != lemma:
                        irregulars[surface] = lemma
    return irregulars


_VOWEL_NUCLEUS_RE = re.compile(r"[aeiouɑɒæʌəɜɛɪɔʊʉɝɚ]+", re.IGNORECASE)


def normalize_learner_ipa(raw_ipa: str) -> str:
    """Normalizes narrow IPA allophones (ɫ->l, ɹ->r) and removes redundant ˈ on monosyllables."""
    trimmed = (raw_ipa or "").strip()
    if not trimmed:
        return ""
    had_slashes = trimmed.startswith("/") and trimmed.endswith("/")
    inner = trimmed[1:-1].strip() if had_slashes else trimmed
    inner = inner.replace("ɫ", "l").replace("ɹ", "r")
    if " " not in inner and "." not in inner:
        if len(_VOWEL_NUCLEUS_RE.findall(inner)) <= 1 and "ˌ" not in inner:
            inner = inner.replace("ˈ", "").replace("'", "")
    if not inner:
        return ""
    return f"/{inner}/" if had_slashes else inner


def load_ipa_dict_file(path: str) -> dict:
    """Loads an open-dict-data/ipa-dict TSV file (word<TAB>/ipa1/, /ipa2/) -> {word: '/ipa1/'}."""
    ipa_map = {}
    if not os.path.exists(path):
        raise FileNotFoundError(f"Missing open-dict-data/ipa-dict file: {path}")
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or "\t" not in line:
                continue
            raw_word, raw_ipa = line.split("\t", 1)
            word = raw_word.strip().lower()
            if not word or len(word) > 45:
                continue
            # Keep primary pronunciation (first entry before comma) normalized for learners
            primary_ipa = normalize_learner_ipa(raw_ipa.split(",")[0].strip())
            if primary_ipa and word not in ipa_map:
                ipa_map[word] = primary_ipa
    return ipa_map


def build_sqlite_dictionary(
    en_vi_source_db: str,
    wordnet_zip_path: str,
    ipa_us_path: str,
    ipa_uk_path: str,
    out_sqlite_path: str,
    out_json_bundle_path: str,
) -> None:
    phonetics_engine.ensure_loaded()
    base_bundle = generate_offline_data()

    # 1. Load Open Dict Data (open-dict-data/ipa-dict) for American (en_US) & British (en_UK) IPA
    ipa_us_map = load_ipa_dict_file(ipa_us_path)
    ipa_uk_map = load_ipa_dict_file(ipa_uk_path)
    print(f"Loaded open-dict-data/ipa-dict: en_US={len(ipa_us_map):,}, en_UK={len(ipa_uk_map):,}")

    # 2. Merge irregular lemmas from WordNet + curated irregulars
    irregulars = load_wordnet_exceptions(wordnet_zip_path)
    irregulars.update(base_bundle["irregular_lemmas"])

    # 3. Load EN-VI definitions from raw source DB OR existing offline_dict.db (preserving 104k+ EN-VI definitions)
    # entries: word -> [ipa_fallback, pos, vi]
    entries = {}
    if os.path.exists(en_vi_source_db):
        src = sqlite3.connect(en_vi_source_db)
        cur = src.cursor()

        ipa_by_id = {}
        for word_id, ipa in cur.execute("SELECT word_id, ipa FROM pronunciations"):
            if word_id not in ipa_by_id and ipa:
                ipa_by_id[word_id] = ipa.strip()

        defs_by_id = {}
        pos_by_id = {}
        query = """
            SELECT wd.word_id, d.pos, d.definition
            FROM word_definitions wd
            INNER JOIN definitions d ON d.id = wd.definition_id
        """
        for word_id, raw_pos, definition in cur.execute(query):
            clean_def = (definition or "").strip().rstrip(".")
            if not clean_def:
                continue
            norm_pos = POS_MAP.get((raw_pos or "").strip().upper(), "vocab")
            if word_id not in pos_by_id and norm_pos != "vocab":
                pos_by_id[word_id] = norm_pos
            lst = defs_by_id.setdefault(word_id, [])
            if len(lst) < 3 and clean_def not in lst:
                lst.append(clean_def)

        for word_id, word in cur.execute("SELECT id, word FROM words"):
            w = (word or "").strip().lower()
            if not w or len(w) > 45:
                continue
            defs = defs_by_id.get(word_id, [])
            vi_str = "; ".join(defs)
            if len(vi_str) > 180:
                vi_str = vi_str[:177] + "..."
            pos_code = pos_by_id.get(word_id, "vocab")
            pos_label = POS_VI_LABEL.get(pos_code, pos_code)
            formatted_vi = f"({pos_label}) {vi_str}" if vi_str else ""
            ipa = ipa_by_id.get(word_id, "")
            entries[w] = [ipa, pos_code, formatted_vi]
        src.close()
    elif os.path.exists(out_sqlite_path):
        # Preserve existing 104k+ EN-VI definitions & irregulars from current offline_dict.db
        backup_existing = out_sqlite_path + ".prev"
        shutil.copy2(out_sqlite_path, backup_existing)
        src = sqlite3.connect(backup_existing)
        cur = src.cursor()
        for word, ipa, pos, vi in cur.execute("SELECT word, ipa, pos, vi FROM dictionary"):
            w = (word or "").strip().lower()
            if w and len(w) <= 45:
                entries[w] = [ipa or "", pos or "vocab", vi or ""]
        try:
            for surf, lem in cur.execute("SELECT surface, lemma FROM irregular_lemmas"):
                if surf and lem and surf not in irregulars:
                    irregulars[surf] = lem
        except sqlite3.OperationalError:
            pass
        src.close()
        os.remove(backup_existing)
        print(f"Preserved {len(entries):,} existing entries from {out_sqlite_path}")

    # 4. Overlay curated high-priority core EN-VI vocabulary (516 words)
    merged_core = dict(translator_service.CORE_EN_VI_LEXICON)
    merged_core.update(EXTRA_EN_VI_WORDS)
    for word, (vi_meaning, pos_code) in merged_core.items():
        w = word.lower().strip()
        fallback_ipa = ipa_us_map.get(w) or phonetics_engine.to_ipa(w, lemma=w)
        pos_label = POS_VI_LABEL.get(pos_code, pos_code)
        entries[w] = [fallback_ipa, pos_code, f"({pos_label}) {vi_meaning}"]

    # 5. Ensure ALL words in open-dict-data/ipa-dict (en_US + en_UK) are indexed in SQLite
    all_ipa_words = set(ipa_us_map.keys()) | set(ipa_uk_map.keys())
    for w in all_ipa_words:
        if w not in entries:
            entries[w] = ["", "vocab", ""]

    # 6. Backfill any remaining CMUdict words not yet in entries
    for w, pron_list in phonetics_engine._cmudict.items():
        w_clean = w.lower().strip()
        if not w_clean.isalpha() or len(w_clean) < 2:
            continue
        if w_clean not in entries:
            cmu_ipa = phonetics_engine._arpabet_to_ipa(pron_list[0])
            entries[w_clean] = [cmu_ipa, "vocab", ""]

    # 7. Assemble final rows: (word, ipa, ipa_us, ipa_uk, pos, vi)
    final_rows = []
    vi_count = 0
    ipa_count = 0
    ipa_us_count = 0
    ipa_uk_count = 0
    both_us_uk_count = 0

    for w in sorted(entries.keys()):
        fallback_ipa, pos, vi = entries[w]
        ipa_us = ipa_us_map.get(w, "")
        ipa_uk = ipa_uk_map.get(w, "")

        # Primary IPA prefers American English from ipa-dict, then British English, then fallback
        primary_ipa = ipa_us or ipa_uk or fallback_ipa
        if not ipa_us and fallback_ipa:
            ipa_us = fallback_ipa

        if vi:
            vi_count += 1
        if primary_ipa:
            ipa_count += 1
        if ipa_us:
            ipa_us_count += 1
        if ipa_uk:
            ipa_uk_count += 1
        if ipa_us and ipa_uk:
            both_us_uk_count += 1

        final_rows.append((w, primary_ipa, ipa_us, ipa_uk, pos, vi))

    # 8. Write optimized SQLite database asset (`assets/nlp/offline_dict.db`)
    if os.path.exists(out_sqlite_path):
        os.remove(out_sqlite_path)

    os.makedirs(os.path.dirname(out_sqlite_path), exist_ok=True)
    db = sqlite3.connect(out_sqlite_path)
    db.execute("PRAGMA journal_mode = OFF")
    db.execute("PRAGMA synchronous = OFF")
    db.execute("PRAGMA page_size = 4096")

    db.execute("""
        CREATE TABLE dictionary (
            word TEXT PRIMARY KEY,
            ipa TEXT NOT NULL,
            ipa_us TEXT NOT NULL,
            ipa_uk TEXT NOT NULL,
            pos TEXT NOT NULL,
            vi TEXT NOT NULL
        ) WITHOUT ROWID
    """)

    db.execute("""
        CREATE TABLE irregular_lemmas (
            surface TEXT PRIMARY KEY,
            lemma TEXT NOT NULL
        ) WITHOUT ROWID
    """)

    db.execute("""
        CREATE TABLE meta_info (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        ) WITHOUT ROWID
    """)

    db.executemany(
        "INSERT OR REPLACE INTO dictionary (word, ipa, ipa_us, ipa_uk, pos, vi) VALUES (?, ?, ?, ?, ?, ?)",
        final_rows,
    )

    db.executemany(
        "INSERT OR REPLACE INTO irregular_lemmas (surface, lemma) VALUES (?, ?)",
        sorted(irregulars.items()),
    )

    meta_rows = [
        ("schema_version", "2"),
        ("total_entries", str(len(final_rows))),
        ("vi_entries", str(vi_count)),
        ("ipa_entries", str(ipa_count)),
        ("ipa_us_entries", str(ipa_us_count)),
        ("ipa_uk_entries", str(ipa_uk_count)),
        ("ipa_both_us_uk_entries", str(both_us_uk_count)),
        ("irregular_lemmas", str(len(irregulars))),
        ("ipa_source", "open-dict-data/ipa-dict (en_US + en_UK)"),
        (
            "license",
            "CC BY-SA 4.0 (Wiktionary / MinhQND / WikDict / Skypedia EN-VI) + Open Dict Data ipa-dict (en_US & en_UK) + CMUdict (BSD/Public Domain) + Princeton WordNet 3.0",
        ),
        (
            "attribution_url",
            "https://github.com/open-dict-data/ipa-dict | https://github.com/skypediacode/english-vietnamese-dictionary",
        ),
    ]
    db.executemany("INSERT INTO meta_info (key, value) VALUES (?, ?)", meta_rows)
    db.commit()
    db.execute("ANALYZE")
    db.execute("VACUUM")
    db.close()

    # 9. Enrich compact JSON bundle (`assets/nlp/nlp_bundle.json`) with US & UK IPA for core words
    enriched_core_dict = {}
    for w, item in base_bundle["offline_dict"].items():
        w_l = w.lower()
        us = ipa_us_map.get(w_l, item.get("ipa", ""))
        uk = ipa_uk_map.get(w_l, "")
        enriched_core_dict[w] = {
            "ipa": us or uk or item.get("ipa", ""),
            "ipa_us": us,
            "ipa_uk": uk,
            "pos": item.get("pos", "vocab"),
            "vi": item.get("vi", ""),
        }

    compact_bundle = {
        "license": "Open Dict Data ipa-dict (en_US + en_UK) + CC BY-SA 4.0 + CMUdict BSD + WordNet",
        "offline_dict": enriched_core_dict,
        "irregular_lemmas": irregulars,
        "prefixes": morphology_engine.PREFIXES,
        "roots": morphology_engine.ROOTS,
        "suffixes": morphology_engine.SUFFIXES,
    }
    with open(out_json_bundle_path, "w", encoding="utf-8") as f:
        json.dump(compact_bundle, f, ensure_ascii=False, separators=(",", ":"))

    sqlite_mb = os.path.getsize(out_sqlite_path) / (1024 * 1024)
    json_kb = os.path.getsize(out_json_bundle_path) / 1024
    print(f"Built {out_sqlite_path}: {sqlite_mb:.2f} MB")
    print(
        f"  Total words: {len(final_rows):,} | EN-VI: {vi_count:,} | "
        f"IPA US: {ipa_us_count:,} | IPA UK: {ipa_uk_count:,} | Both US+UK: {both_us_uk_count:,}"
    )
    print(f"Built {out_json_bundle_path}: {json_kb:.1f} KB")


if __name__ == "__main__":
    build_sqlite_dictionary(
        en_vi_source_db="/tmp/dictionary_en_vi.db",
        wordnet_zip_path="/home/minwell0309/vocab_nlp_backend/nltk_data/corpora/wordnet.zip",
        ipa_us_path="/home/minwell0309/vocab_anki/tool/data/en_US.txt",
        ipa_uk_path="/home/minwell0309/vocab_anki/tool/data/en_UK.txt",
        out_sqlite_path="/home/minwell0309/vocab_anki/assets/nlp/offline_dict.db",
        out_json_bundle_path="/home/minwell0309/vocab_anki/assets/nlp/nlp_bundle.json",
    )
