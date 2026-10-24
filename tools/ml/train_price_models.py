"""Latih model regresi harga wajar WorthBang (Ridge, satu model per kategori).

Jalankan dari root repo setelah aktivasi venv (satu perintah):
    tools/ml/.venv/bin/python tools/ml/train_price_models.py
    tools/ml/.venv/bin/python tools/ml/train_price_models.py --dump-parity

Opsi: --input, --out, --report, --dump-parity. Path default relatif
terhadap root repo (diturunkan dari lokasi file ini).

Port setia ke Dart (benchmark.dart, analysis_engine.dart); penyimpangan
yang disengaja didokumentasikan di bawah fungsi main (lihat NOTES).
"""

import argparse
import hashlib
import json
import math
import random
import re
import sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.linear_model import Ridge
from sklearn.model_selection import GroupKFold, KFold
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

REPO = Path(__file__).resolve().parents[2]
PRICE_MIN = 50_000
PRICE_MAX = 150_000_000
SEED = 42
N_SPLITS = 5
ALPHA = 1.0
MIN_ROWS_TIER2 = 100
TIER2_RATIO = 0.9
CATEGORIES = ["gpu", "cpu", "ram", "storage", "motherboard", "laptop"]
VRAM_VALID = {2, 3, 4, 6, 8, 10, 11, 12, 16, 20, 24}
IGPU_TOKENS = [
    "iris", "uhd", "hd graphics", "vega", "radeon graphics",
    "integrated", "shared", "intel graphics", "intel hd",
    "apple", "m1", "m2", "m3", "m4", "snapdragon", "adreno",
]

GPU_RE = re.compile(r"\b(rtx|gtx|rx|arc)\s*([ab]?\d{3,4})\s*(ti|super|xt)?\b")
GPU_SIG_RE = re.compile(r"\b(rtx|gtx|rx)\s*(\d{3,4})\s*(ti|super|xt)?\b")
CPU_MODEL_RE = re.compile(
    r"\b(ryzen\s*[3579]|core\s*i[3579])\s*-?\s*(\d{4,5})([a-z]{0,2})?\b"
)
CPU_RE = re.compile(
    r"\b(ryzen(?:\s*ai)?\s*[3579]|core\s*i[3579]|ultra\s*[579])"
    r"\s*-?\s*(\d{4,5}[a-z]{0,3})\b"
)
CPU_SIG_RE = re.compile(
    r"\b(ryzen(?:\s*ai)?\s*[3579]|core\s*i[3579]|ultra\s*[579]|i[3579])"
    r"\s*-?\s*(\d{4,5}[a-z]{0,3}|[a-z]{1,4}\d{3}[a-z]{0,3})?\b"
)
# Pola baru CPU laptop (A4, fallback bila CPU_RE lama tidak cocok).
# [1-9] di awal nomor menolak angka semu seperti '000' ('core 5000'
# dari 'octa-core 5000 mAh'); lookbehind menolak 'octa-core'/'dual-core'.
BARE_IX_RE = re.compile(r"\bi([3579])\s*-?\s*([1-9]\d{3,4}[a-z]{0,3})\b")
CORE_NO_I_RE = re.compile(
    r"(?<![a-z-])core\s*([579])\s*-?\s*([1-9]\d{2}[a-z]{0,3})\b")
ULTRA_3_RE = re.compile(
    r"(?<![a-z-])ultra\s*([579])\s*-?\s*([1-9]\d{2}[a-z]{0,3})\b")
APPLE_CHIP_RE = re.compile(r"\bm([1234])\b")
APPLE_BASE_KEYS = {
    "1": "apple m1 8 core 3200 mhz",
    "2": "apple m2 8 core 3500 mhz",
    "3": "apple m3 8 core",
    "4": "apple m4 10 core",
}
APPLE_PRO_KEYS = {
    "1": "apple m1 pro 10 core 3200 mhz",
    "2": "apple m2 pro 10 core 3480 mhz",
    "3": "apple m3 pro 11 core",
    "4": "apple m4 pro 12 core",
}
APPLE_MAX_KEYS = {
    "1": "apple m1 max 10 core 3200 mhz",
    "2": "apple m2 max 12 core 3680 mhz",
    "3": "apple m3 max 14 core",
    "4": "apple m4 max 14 core",
}
CHIPSET_RE = re.compile(r"\b([abxzi]\d{3})[a-z]{0,2}\b")


def sq(text):
    """Port _sq: lowercase, buang semua non-alfanumerik."""
    return re.sub(r"[^a-z0-9]", "", (text or "").lower())


def _score_of(entry, key):
    v = entry.get(key) if isinstance(entry, dict) else None
    if isinstance(v, (int, float)) and not isinstance(v, bool) and v > 0:
        return float(v)
    return None


def lookup_key(query, catalog):
    """Port consensusLookup/passmarkScore (probe + squash). Mengembalikan
    (entri dict, kunci katalog) atau (None, None)."""
    if not catalog:
        return None, None
    text = (query or "").lower()
    for prefix in ("geforce", "radeon", "nvidia", "amd", ""):
        probe = " ".join((prefix + " " + text).split()) if prefix else " ".join(text.split())
        if probe and probe in catalog:
            entry = catalog[probe]
            if isinstance(entry, dict):
                return entry, probe
    qsq = sq(text)
    if not qsq:
        return None, None
    best = None
    best_key = None
    best_name_len = 0
    for key, entry in catalog.items():
        if not isinstance(entry, dict):
            continue
        ksq = sq(key)
        if ksq and (ksq in qsq or qsq in ksq):
            name_len = len(sq(str(entry.get("name", "")).lower()))
            if best is None or len(ksq) < best_name_len:
                best = entry
                best_key = key
                best_name_len = name_len
    return best, best_key


def consensus_lookup(query, catalog):
    """Port consensusLookup. Mengembalikan entri dict atau None."""
    entry, _ = lookup_key(query, catalog)
    return entry


def lookup_score(model, catalog, field):
    """Skor + kunci katalog untuk satu model berspasi, atau (None, None)."""
    entry, key = lookup_key(model, catalog)
    if entry is None:
        return None, None
    return _score_of(entry, field), key


def extract_vram_gb(text):
    """Port extractVramGb persis (termasuk urutan fallback-nya)."""
    t = (text or "").lower()
    m = re.search(r"\b(\d{1,2})\s*gb\b", t)
    if m:
        val = int(m.group(1))
        if val in VRAM_VALID:
            return val
    if "rtx 3060" in t and "ti" not in t:
        return 12
    if "rx 6700 xt" in t or "rx 6750 xt" in t:
        return 12
    if "rx 6800" in t:
        return 16
    if "rtx 4070" in t:
        return 12
    if ("rtx 4060" in t or "rx 6600" in t or "rtx 3050" in t
            or "rtx 2060 super" in t):
        return 8
    if "gtx 1660" in t or "rtx 2060" in t:
        return 6
    if "gtx 1650" in t:
        return 4
    return None


def extract_gpu_model(text):
    """Token model GPU berspasi dari _modelTokens cabang GPU, atau None."""
    m = GPU_RE.search((text or "").lower())
    if not m:
        return None
    out = m.group(1) + " " + m.group(2)
    if m.group(3):
        out += " " + m.group(3)
    return out


def gpu_sig(text):
    """Port _gpuSig: sig padat ('rtx4060ti') atau None."""
    m = GPU_SIG_RE.search((text or "").lower())
    if not m:
        return None
    return m.group(1) + m.group(2) + (m.group(3) or "")


def extract_cpu_model(text):
    """Token model CPU berspasi dari _modelTokens cabang CPU, atau None."""
    m = CPU_MODEL_RE.search((text or "").lower())
    if not m:
        return None
    tier = re.search(r"[3579]", m.group(1)).group(0)
    suffix = m.group(3) or ""
    if "ryzen" in m.group(1):
        return f"ryzen {tier} {m.group(2)}{suffix}"
    return f"core i{tier} {m.group(2)}{suffix}"


def cpu_sig(text):
    """Port _cpuSig: sig padat ('corei512450h') atau None."""
    m = CPU_SIG_RE.search((text or "").lower())
    if not m:
        return None
    raw_fam = re.sub(r"\s+", "", m.group(1))
    if re.fullmatch(r"i[3579]", raw_fam):
        raw_fam = "core" + raw_fam
    num = m.group(2) or ""
    if not num:
        return None
    return raw_fam + num


def is_integrated_gpu(text):
    """Port _isIntegratedGpu."""
    if text is None:
        return True
    low = text.lower().strip()
    if not low:
        return True
    return any(tok in low for tok in IGPU_TOKENS)


def _best_in(full, catalog):
    """Helper bestIn dari resolveCpuLaptop (port setia, quirk ikut)."""
    qsq = sq(full)
    best = None
    best_name_len = 0
    for key, entry in catalog.items():
        if not isinstance(entry, dict):
            continue
        ksq = sq(key)
        if qsq and (ksq in qsq or qsq in ksq):
            name_len = len(sq(str(entry.get("name", "")).lower()))
            if best is None or len(ksq) < best_name_len:
                best = entry
                best_name_len = name_len
    return best


def _new_cpu_full(low):
    """Pola baru CPU laptop (A4) -> (full kanonik, tag) atau (None, None).

    Urutan: bare iX, Core tanpa i, Ultra 3 digit. CPU_RE lama tidak
    menangkap ketiganya: bare iX tanpa kata 'core', 'Core 5' tanpa 'i',
    dan nomor Ultra 3 digit (CPU_RE menuntut 4-5 digit).
    """
    m = BARE_IX_RE.search(low)
    if m:
        return "core i%s %s" % (m.group(1), m.group(2).lower()), "bare_ix"
    m = CORE_NO_I_RE.search(low)
    if m:
        return "core %s %s" % (m.group(1), m.group(2).lower()), "core_no_i"
    m = ULTRA_3_RE.search(low)
    if m:
        return "ultra %s %s" % (m.group(1), m.group(2).lower()), "ultra_3"
    return None, None


def _apple_cpu_entry(low, bench_mobile, bench_cpu):
    """Entri Apple eksak untuk chip M1-M4, atau (None, None).

    Syarat: judul/spec menyebut konteks Apple (apple/macbook) agar
    'M2 2280' (ukuran SSD) tidak ikut terpetakan; kualifikasi pro/max
    hanya dihitung bila langsung mengikuti chip ('M1 Pro'), bukan
    'MacBook Pro ... M1' (itu chip base di laptop Pro); 'M2 2280'/'2230'
    (ukuran SSD) selalu dilewati. Kunci eksak harus ADA di katalog
    (mobile dulu, lalu desktop) — skor tidak pernah dikarang.
    """
    if "apple" not in low and "macbook" not in low \
            and "mac book" not in low:
        return None, None
    m = APPLE_CHIP_RE.search(low)
    if not m:
        return None, None
    if re.match(r"\s+22[38]0\b", low[m.end():]):
        return None, None
    tail = low[m.end():]
    if re.match(r"\s+max\b", tail):
        table = APPLE_MAX_KEYS
    elif re.match(r"\s+pro\b", tail):
        table = APPLE_PRO_KEYS
    else:
        table = APPLE_BASE_KEYS
    key = table.get(m.group(1))
    if key is None:
        return None, None
    for catalog in (bench_mobile, bench_cpu):
        entry = catalog.get(key)
        if isinstance(entry, dict):
            score = _score_of(entry, "score")
            if score is not None:
                return score, key
    return None, None


def resolve_cpu_laptop(text, bench_cpu, bench_mobile):
    """Port resolveCpuLaptop + pola baru A4.

    Mengembalikan (skor, full, tag); tag: 'old', 'bare_ix',
    'core_no_i', 'ultra_3', 'apple', atau 'none'. Alur lama tidak
    berubah: _best_in (mobile, lalu desktop), lalu proksi famili+tier.
    Pola baru memakai alur yang sama; Apple hanya kunci eksak, tanpa
    proksi. Proksi tidak menjangkau kunci 3 digit Core/Ultra karena
    CPU_RE kunci juga menuntut 4-5 digit — perilaku ini sama di Dart.
    """
    low = (text or "").lower()
    m = CPU_RE.search(low)
    if m is not None:
        full = m.group(0).lower()
        tag = "old"
        num_raw = m.group(2)
    else:
        full, tag = _new_cpu_full(low)
        if full is None:
            score, key = _apple_cpu_entry(low, bench_mobile, bench_cpu)
            if score is None:
                return None, None, "none"
            return score, key, "apple"
        num_raw = re.search(r"(\d+[a-z]{0,3})$", full).group(1)
    entry = _best_in(full, bench_mobile)
    if entry is None:
        entry = _best_in(full, bench_cpu)
    if entry is not None:
        score = _score_of(entry, "score")
        if score is not None:
            return score, full, tag
    tier_m = re.search(r"(i[3579]|[3579])", full)
    if tier_m is None:
        return None, full, "none"
    tier_ch = tier_m.group(1)[-1]
    is_intel = ("core" in full) or ("ultra" in full)
    want_str = re.sub(r"[a-z]+$", "", num_raw.lower())
    if not re.fullmatch(r"\d+", want_str or ""):
        return None, full, "none"
    want_num = int(want_str)

    def cand_num(key):
        cm = CPU_RE.search(key.lower())
        if cm is None:
            return None
        kfull = cm.group(0).lower()
        kt = re.search(r"(i[3579]|[3579])", kfull)
        if kt is None or kt.group(1)[-1] != tier_ch:
            return None
        kintel = ("core" in kfull) or ("ultra" in kfull)
        if kintel != is_intel:
            return None
        knum = re.sub(r"[a-z]+$", "", cm.group(2).lower())
        if not re.fullmatch(r"\d+", knum or ""):
            return None
        return int(knum)

    pool = []
    for key, entry in bench_cpu.items():
        if not isinstance(entry, dict):
            continue
        knum = cand_num(key)
        if knum is not None:
            pool.append((abs(knum - want_num), len(sq(key)), entry))
    if not pool:
        return None, full, "none"
    pool.sort(key=lambda x: (x[0], x[1]))
    score = _score_of(pool[0][2], "score")
    return score, full, tag


def extract_ram_text(text):
    """Port _extractRamFromText (untuk laptop)."""
    t = (text or "").lower()
    m = re.search(r"\bram\s*(\d{1,2})\s*gb\b", t)
    if m:
        return int(m.group(1))
    m = re.search(r"(\d{1,2})\s*gb\s*(?:ddr|ram|memory)\b", t)
    if m:
        return int(m.group(1))
    m = re.search(r"\b(\d{1,2})\s*/\s*\d{3,4}\b", t)
    if m:
        return int(m.group(1))
    return None


def extract_storage_text(text):
    """Port _extractStorageFromText (untuk laptop). Desimal TB
    didukung (2.0TB -> 2000), karena regex digit-mentah salah baca
    '2.0TB' sebagai 0TB."""
    t = (text or "").lower()
    m = re.search(r"(\d+(?:[.,]\d+)?)\s*tb\b", t)
    if m:
        return int(round(float(m.group(1).replace(",", ".")) * 1000))
    m = re.search(r"\b\d{1,2}\s*/\s*(\d{3,4})\b", t)
    if m:
        return int(m.group(1))
    m = re.search(r"\b(128|256|512|1000|1024)\s*(?:gb)?\s*(?:ssd|nvme|storage|rom)?\b", t)
    if m:
        return int(m.group(1))
    return None


def extract_ram_cat(text):
    """RAM kategori: total GB (kit NxM dijumlah), DDR, speed, sodimm."""
    t = (text or "").lower()
    total = None
    m = re.search(r"(\d)\s*x\s*(\d{1,2}(?:[.,]\d+)?)\s*gb\b", t)
    if m:
        total = int(m.group(1)) * int(round(
            float(m.group(2).replace(",", "."))))
    else:
        m = re.search(r"(\d{1,2}(?:[.,]\d+)?)\s*gb\b", t)
        if m:
            total = int(round(float(m.group(1).replace(",", "."))))
    ddr = None
    m = re.search(r"ddr\s*([345])", t)
    if m:
        ddr = int(m.group(1))
    speed = None
    m = re.search(r"(\d{3,4})\s*mhz\b", t)
    if m:
        speed = int(m.group(1))
    sodimm = 1 if "sodimm" in t.replace("-", "") else 0
    return total, ddr, speed, sodimm


NEG_PHRASE_RE = re.compile(r"\b(bukan|non|no|tanpa)[\s\-]+(nvme|pcie|sata)\b")


def classify_storage_type(text):
    """Klasifikasi tipe storage, urutan keputusan Fase A2 (didokumentasikan
    di laporan draft). Mengembalikan (tipe, alasan_buang) dengan tipe
    None bila baris harus dibuang:
    1. token nvme/pcie yang TIDAK dinegasikan -> nvme (negasi = kata
       bukan/non/no/tanpa yang langsung mendahului atau terhubung
       tanda hubung; frasa ternegasi dihapus dulu dari teks);
    2. token sata eksplisit (tidak ternegasi) -> sata_ssd, WALAU ada m.2;
    3. ada m.2 tapi tidak ada nvme/pcie/sata -> BUANG (m2_tanpa_tipe),
       token ssd saja tidak menyelamatkan;
    4. token ssd tanpa m.2 -> sata_ssd;
    5. token hdd/harddisk/hardisk -> hdd;
    6. sisanya -> BUANG (tipe_tidak_dikenali)."""
    t = (text or "").lower()
    clean = NEG_PHRASE_RE.sub(" ", t)
    if re.search(r"\bnvme\b|\bpcie\b", clean):
        return "nvme", None
    if re.search(r"\bsata\b", clean):
        return "sata_ssd", None
    if re.search(r"\bm\.?2\b", clean):
        return None, "m2_tanpa_tipe"
    if re.search(r"\bssd\b", clean):
        return "sata_ssd", None
    if re.search(r"\bhdd\b|\bharddisk\b|\bhardisk\b", clean):
        return "hdd", None
    return None, "tipe_tidak_dikenali"


def extract_storage_cat(text):
    """Storage kategori: kapasitas GB (TB x 1000) + tipe (Fase A2).
    Desimal didukung (2.0TB -> 2000; '2.0TB' pernah salah dibaca
    0TB oleh regex digit-mentah dan membuat log(0) crash)."""
    t = (text or "").lower()
    cap = None
    m = re.search(r"(\d+(?:[.,]\d+)?)\s*tb\b", t)
    if m:
        cap = int(round(float(m.group(1).replace(",", ".")) * 1000))
    else:
        m = re.search(r"(\d{1,4}(?:[.,]\d+)?)\s*gb\b", t)
        if m:
            cap = int(round(float(m.group(1).replace(",", "."))))
    stype, _ = classify_storage_type(t)
    return cap, stype


def extract_chipset(text):
    """Port regex _modelTokens cabang motherboard."""
    m = CHIPSET_RE.search((text or "").lower())
    return m.group(1) if m else None


def map_condition(value):
    """Satu pemetaan kondisi: baru/new -> new, bekas/second -> second,
    sisanya (termasuk kosong) -> unknown. Jangan ditebak."""
    v = (value or "").strip().lower()
    if v in ("new", "baru"):
        return "new"
    if v in ("second", "bekas"):
        return "second"
    return "unknown"


def fmt_num(v):
    """Format angka untuk kunci grup: 10.0 -> '10', 10.5 -> '10.5'."""
    f = float(v)
    return str(int(f)) if f == int(f) else str(f)


def cond_dummies(condition):
    return (1.0 if condition == "new" else 0.0,
            1.0 if condition == "second" else 0.0)


SECOND_TITLE_RE = re.compile(
    r"second|2nd|bekas|seken|used|preloved|copotan", re.IGNORECASE)


def infer_condition(source, raw_condition, title):
    """A3-3: HANYA baris Tokopedia dengan condition kosong yang
    diinferensi dari JUDUL (second bila judul memuat penanda bekas,
    selain itu new). Facebook memakai label aslinya; kosong = unknown.
    Mengembalikan (kondisi_efektif, diinferensi?)."""
    if (source or "").strip().lower() == "tokopedia" \
            and not (raw_condition or "").strip():
        if SECOND_TITLE_RE.search(title or ""):
            return "second", True
        return "new", True
    return map_condition(raw_condition), False


def resolve_condition_dummies(defaults, condition):
    """Dummy kondisi untuk INFERENSI (dipakai Dart di fase integrasi):
    new -> (1,0); second -> (0,1); unknown -> (0,0); 'any' -> memakai
    cond_new_mean dan cond_second_mean dari defaults (BUKAN 0,0)."""
    if condition == "new":
        return (1.0, 0.0)
    if condition == "second":
        return (0.0, 1.0)
    if condition == "any":
        return (float(defaults.get("cond_new_mean", 0.0)),
                float(defaults.get("cond_second_mean", 0.0)))
    return (0.0, 0.0)


def predict_price(entry, feat, condition="any"):
    """Prediksi harga dari entri model JSON + dict fitur non-dummy
    (sudah transformasi log bila perlu). Dummy kondisi diisi lewat
    resolve_condition_dummies; src_tokopedia (bila ada di features)
    diisi src_tokopedia_mean dari defaults karena user app tidak
    memilih sumber. None bila kategori tidak enabled/fallback atau
    ada fitur yang hilang."""
    if not entry.get("enabled") and not entry.get("enabled_fallback"):
        return None
    defaults = entry.get("defaults", {})
    cn, cs = resolve_condition_dummies(defaults, condition)
    vals = dict(feat)
    vals["cond_new"] = cn
    vals["cond_second"] = cs
    names = [f["name"] for f in entry["features"]]
    if "src_tokopedia" in names:
        vals["src_tokopedia"] = float(
            defaults.get("src_tokopedia_mean", 0.0))
    total = float(entry["intercept"])
    for f in entry["features"]:
        v = vals.get(f["name"])
        if v is None:
            return None
        total += float(f["coef"]) * float(v)
    return float(np.exp(total))


def group_key(cat, rec):
    """Kunci grup produk dari FITUR FINAL (setelah imputasi)."""
    if cat == "gpu":
        return rec["model"] + "|" + fmt_num(rec["vram"])
    if cat == "cpu":
        return rec["model"]
    if cat == "ram":
        return "ddr%d|%d" % (rec["ddr"], rec["total"])
    if cat == "storage":
        return "%s|%d" % (rec["stype"], rec["cap"])
    if cat == "motherboard":
        return rec["chipset"]
    return rec["cpu_sig"] + "|" + rec["gpu_sig"]


def process_category(cat, rows, cons_gpu, cons_cpu, bench_cpu, bench_mobile,
                     scales=None, feat_names=None):
    """Ekstraksi + imputasi + IQR untuk satu kategori.

    rows: list dict (sudah dedupe global + filter harga) dengan kunci
    title, spec, price, condition. scales: dict kolom -> (katalog, field
    skor) untuk gpu, cpu, laptop_gpu (default Fase A: konsensus).
    feat_names: dict kolom -> nama fitur ln skor (mengikuti skala).
    Mengembalikan dict hasil + diagnostik.
    """
    if scales is None:
        scales = {"gpu": (cons_gpu, "consensus_score"),
                  "cpu": (cons_cpu, "consensus_score"),
                  "laptop_gpu": (cons_gpu, "consensus_score")}
    if feat_names is None:
        feat_names = {"gpu": "ln_consensus", "cpu": "ln_consensus",
                      "laptop_gpu": "ln_gpu_consensus"}
    drops = Counter()
    drop_titles = defaultdict(list)

    def note_drop(reason, title):
        drops[reason] += 1
        drop_titles[reason].append(title)

    unmatched = []
    recs = []
    cons_matched = 0
    laptop_cpu_matched = 0
    laptop_cpu_new = Counter()
    laptop_gpu_matched = 0
    laptop_gpu_sig = 0
    for r in rows:
        text = (r["title"] + " " + r["spec"]).strip()
        cond = r["condition"]
        price = r["price"]
        base = {"price": price, "condition": cond,
                "title": r["title"], "spec": r["spec"],
                "src": 1.0 if (r.get("source") or "").strip().lower()
                == "tokopedia" else 0.0}
        if cat == "gpu":
            model = extract_gpu_model(text)
            if model is None:
                note_drop("model_tidak_ditemukan", r["title"])
                continue
            score, _ = lookup_score(model, scales["gpu"][0],
                                    scales["gpu"][1])
            if score is None:
                note_drop("konsensus_tidak_cocok", r["title"])
                unmatched.append(r["title"])
                continue
            cons_matched += 1
            rec = dict(base, model=model, score=score,
                       vram_raw=extract_vram_gb(text))
            recs.append(rec)
        elif cat == "cpu":
            model = extract_cpu_model(text)
            if model is None:
                note_drop("model_tidak_ditemukan", r["title"])
                continue
            score, _ = lookup_score(model, scales["cpu"][0],
                                    scales["cpu"][1])
            if score is None:
                note_drop("konsensus_tidak_cocok", r["title"])
                unmatched.append(r["title"])
                continue
            cons_matched += 1
            recs.append(dict(base, model=model, score=score))
        elif cat == "ram":
            total, ddr, speed, sodimm = extract_ram_cat(text)
            if total is None or total <= 0 or ddr is None:
                note_drop("kapasitas/ddr_tidak_ditemukan", r["title"])
                continue
            recs.append(dict(base, total=total, ddr=ddr,
                             speed_raw=speed, sodimm=sodimm))
        elif cat == "storage":
            cap, stype = extract_storage_cat(text)
            if cap is None or cap <= 0:
                note_drop("kapasitas_tidak_ditemukan", r["title"])
                continue
            if stype is None:
                _, reason = classify_storage_type(text)
                note_drop(reason, r["title"])
                continue
            recs.append(dict(base, cap=cap, stype=stype))
        elif cat == "motherboard":
            chip = extract_chipset(text)
            if chip is None:
                note_drop("chipset_tidak_ditemukan", r["title"])
                continue
            recs.append(dict(base, chipset=chip))
        elif cat == "laptop":
            cpu_score, cpu_full, cpu_tag = resolve_cpu_laptop(
                text, bench_cpu, bench_mobile)
            if cpu_score is None:
                note_drop("cpu_passmark_tidak_cocok", r["title"])
                continue
            laptop_cpu_matched += 1
            if cpu_tag in ("bare_ix", "core_no_i", "ultra_3", "apple"):
                laptop_cpu_new[cpu_tag] += 1
            gsig = gpu_sig(text)
            if gsig is not None:
                laptop_gpu_sig += 1
                gmodel = extract_gpu_model(text)
                gscore, _ = lookup_score(
                    gmodel, scales["laptop_gpu"][0],
                    scales["laptop_gpu"][1]) if gmodel else (None, None)
                if gscore is None:
                    note_drop("gpu_konsensus_tidak_cocok", r["title"])
                    continue
                laptop_gpu_matched += 1
                has_dgpu, ln_gpu = 1, math.log(gscore)
            else:
                has_dgpu, ln_gpu = 0, 0.0
            ram = extract_ram_text(text)
            sto = extract_storage_text(text)
            if ram is None or ram <= 0 or sto is None or sto <= 0:
                note_drop("ram/storage_hilang", r["title"])
                continue
            csig = cpu_sig(text)
            if csig is None:
                csig = sq(cpu_full) if cpu_full else "none"
            recs.append(dict(base, cpu_score=cpu_score, cpu_sig=csig,
                             gpu_sig=gsig or "none", has_dgpu=has_dgpu,
                             ln_gpu=ln_gpu, ram=ram, storage=sto))
    stage_ok = len(recs)
    # --- Imputasi (hanya gpu vram dan ram speed) ---
    if cat == "gpu":
        by_model = defaultdict(list)
        for rec in recs:
            if rec["vram_raw"] is not None:
                by_model[rec["model"]].append(rec["vram_raw"])
        med = {m: float(np.median(v)) for m, v in by_model.items()}
        kept = []
        for rec in recs:
            if rec["vram_raw"] is not None:
                rec["vram"] = float(rec["vram_raw"])
            elif rec["model"] in med:
                rec["vram"] = med[rec["model"]]
            else:
                note_drop("vram_tidak_bisa_diimputasi", rec["title"])
                continue
            kept.append(rec)
        recs = kept
    if cat == "ram":
        by_ddr = defaultdict(list)
        all_speeds = []
        for rec in recs:
            if rec["speed_raw"] is not None:
                by_ddr[rec["ddr"]].append(rec["speed_raw"])
                all_speeds.append(rec["speed_raw"])
        if not all_speeds:
            raise ValueError("tidak ada speed teramati di kategori ram")
        global_med = float(np.median(all_speeds))
        ddr_med = {d: float(np.median(v)) for d, v in by_ddr.items()}
        for rec in recs:
            rec["speed"] = (float(rec["speed_raw"])
                            if rec["speed_raw"] is not None
                            else ddr_med.get(rec["ddr"], global_med))
    # --- Kunci grup dari fitur final ---
    for rec in recs:
        rec["group"] = group_key(cat, rec)
    # --- IQR per grup (n >= 4), persentil linear numpy ---
    iqr_dropped = 0
    if recs:
        by_group = defaultdict(list)
        for i, rec in enumerate(recs):
            by_group[rec["group"]].append(i)
        keep = set(range(len(recs)))
        for idxs in by_group.values():
            if len(idxs) >= 4:
                prices = np.array([recs[i]["price"] for i in idxs],
                                  dtype=float)
                q1, q3 = np.percentile(prices, [25, 75])
                lo, hi = q1 - 1.5 * (q3 - q1), q3 + 1.5 * (q3 - q1)
                for i in idxs:
                    if recs[i]["price"] < lo or recs[i]["price"] > hi:
                        keep.discard(i)
                        iqr_dropped += 1
        recs = [recs[i] for i in sorted(keep)]
    # --- Fitur final + kolom (urutan tetap) ---
    mobo_levels = []
    mobo_other = False
    if cat == "motherboard" and recs:
        counts = Counter(rec["chipset"] for rec in recs)
        mobo_levels = sorted(c for c, n in counts.items() if n >= 5)
        mobo_other = any(n < 5 for n in counts.values())
    feature_cols = _feature_cols(cat, mobo_levels, mobo_other, feat_names)
    finals, raws = [], []
    for rec in recs:
        cn, cs = cond_dummies(rec["condition"])
        if cat == "gpu":
            fin = {feat_names["gpu"]: math.log(rec["score"]),
                   "vram_gb": rec["vram"],
                   "cond_new": cn, "cond_second": cs}
            raw = {feat_names["gpu"]: math.log(rec["score"]),
                   "vram_gb": rec["vram_raw"],
                   "cond_new": cn, "cond_second": cs}
        elif cat == "cpu":
            fin = {feat_names["cpu"]: math.log(rec["score"]),
                   "cond_new": cn, "cond_second": cs}
            raw = dict(fin)
        elif cat == "ram":
            fin = {"ln_capacity_gb": math.log(rec["total"]),
                   "ddr_gen": float(rec["ddr"]),
                   "is_sodimm": float(rec["sodimm"]),
                   "speed_mhz": rec["speed"],
                   "cond_new": cn, "cond_second": cs}
            raw = dict(fin, speed_mhz=rec["speed_raw"])
        elif cat == "storage":
            fin = {"ln_capacity_gb": math.log(rec["cap"]),
                   "type_nvme": 1.0 if rec["stype"] == "nvme" else 0.0,
                   "type_sata_ssd": 1.0 if rec["stype"] == "sata_ssd" else 0.0,
                   "type_hdd": 1.0 if rec["stype"] == "hdd" else 0.0,
                   "cond_new": cn, "cond_second": cs}
            raw = dict(fin)
        elif cat == "motherboard":
            rec_lvl = (rec["chipset"] if rec["chipset"] in mobo_levels
                       else "other")
            fin = {"chipset_" + lv: (1.0 if lv == rec_lvl else 0.0)
                   for lv in mobo_levels}
            if mobo_other:
                fin["chipset_other"] = 1.0 if rec_lvl == "other" else 0.0
            fin["cond_new"] = cn
            fin["cond_second"] = cs
            raw = dict(fin)
        else:  # laptop
            fin = {feat_names["laptop_gpu"]: rec["ln_gpu"],
                   "ln_cpu_passmark": math.log(rec["cpu_score"]),
                   "has_dgpu": float(rec["has_dgpu"]),
                   "ln_ram_gb": math.log(rec["ram"]),
                   "ln_storage_gb": math.log(rec["storage"]),
                   "cond_new": cn, "cond_second": cs}
            raw = dict(fin)
        finals.append(fin)
        raws.append(raw)
    prices = np.array([rec["price"] for rec in recs], dtype=float)
    defaults = _defaults(cat, recs)
    if finals:
        defaults["cond_new_mean"] = float(
            np.mean([f["cond_new"] for f in finals]))
        defaults["cond_second_mean"] = float(
            np.mean([f["cond_second"] for f in finals]))
    else:
        defaults["cond_new_mean"] = 0.0
        defaults["cond_second_mean"] = 0.0
    # A5: src_tokopedia_mean DIHAPUS dari defaults (model final
    # tanpa-src). Kolom src di recs tetap dipakai untuk evaluasi
    # varian perbandingan with_src di main loop.
    X_base = (np.array([[f[c] for c in feature_cols] for f in finals],
                       dtype=float) if finals
              else np.zeros((0, len(feature_cols))))
    src_arr = (np.array([r["src"] for r in recs], dtype=float)
               if recs else np.zeros(0))
    X_with_src = (np.hstack([X_base, src_arr.reshape(-1, 1)])
                  if finals else np.zeros((0, len(feature_cols) + 1)))
    result = {
        "feature_cols": feature_cols,
        "X": X_base,
        "X_with_src": X_with_src,
        "src_col": len(feature_cols),
        "y": np.log(prices) if len(prices) else np.zeros(0),
        "prices": prices,
        "groups": np.array([rec["group"] for rec in recs]),
        "conds": np.array([rec["condition"] for rec in recs]),
        "n_final": len(recs),
        "stage_ok": stage_ok,
        "iqr_dropped": iqr_dropped,
        "drops": dict(drops),
        "drop_titles": {k: list(v) for k, v in drop_titles.items()},
        "unmatched": unmatched,
        "cons_matched": cons_matched,
        "laptop_cpu_matched": laptop_cpu_matched,
        "laptop_cpu_new": dict(laptop_cpu_new),
        "laptop_gpu_matched": laptop_gpu_matched,
        "laptop_gpu_sig": laptop_gpu_sig,
        "mobo_levels": mobo_levels,
        "mobo_other": mobo_other,
        "storage_type_dist": (dict(Counter(r["stype"] for r in recs))
                              if cat == "storage" else {}),
        "storage_hdd_token_final": (
            sum(1 for r in recs
                if re.search(r"hdd|harddisk|hardisk",
                             (r["title"] + " " + r["spec"]).lower()))
            if cat == "storage" else 0),
        "defaults": _defaults(cat, recs),
        "parity": [{"raw_title": rec["title"], "raw_spec_text": rec["spec"],
                    "raw_features": raws[i], "final_features": finals[i]}
                   for i, rec in enumerate(recs[:5])],
    }
    result["defaults"] = defaults
    return result


def _feature_cols(cat, mobo_levels, mobo_other, feat_names=None):
    if feat_names is None:
        feat_names = {"gpu": "ln_consensus", "cpu": "ln_consensus",
                      "laptop_gpu": "ln_gpu_consensus"}
    if cat == "gpu":
        return [feat_names["gpu"], "vram_gb", "cond_new", "cond_second"]
    if cat == "cpu":
        return [feat_names["cpu"], "cond_new", "cond_second"]
    if cat == "ram":
        return ["ln_capacity_gb", "ddr_gen", "is_sodimm", "speed_mhz",
                "cond_new", "cond_second"]
    if cat == "storage":
        return ["ln_capacity_gb", "type_nvme", "type_sata_ssd", "type_hdd",
                "cond_new", "cond_second"]
    if cat == "motherboard":
        cols = ["chipset_" + lv for lv in mobo_levels]
        if mobo_other:
            cols.append("chipset_other")
        return cols + ["cond_new", "cond_second"]
    return ["ln_cpu_passmark", feat_names["laptop_gpu"], "has_dgpu",
            "ln_ram_gb", "ln_storage_gb", "cond_new", "cond_second"]


def _defaults(cat, recs):
    if cat == "gpu" and recs:
        return {"vram_gb": float(np.median([r["vram"] for r in recs]))}
    if cat == "ram" and recs:
        out = {"speed_mhz": float(np.median([r["speed"] for r in recs]))}
        for ddr in sorted({r["ddr"] for r in recs}):
            out["speed_mhz_ddr%d" % ddr] = float(
                np.median([r["speed"] for r in recs if r["ddr"] == ddr]))
        return out
    return {}


def _mae(a, b):
    return float(np.mean(np.abs(np.asarray(a) - np.asarray(b))))


def _mape(a, b):
    a = np.asarray(a, dtype=float)
    b = np.asarray(b, dtype=float)
    return float(np.mean(np.abs(a - b) / b))


def eval_a(X, y, prices, groups, conds, src_col=None):
    """KFold 5 acak (seed 42). Baseline = median pool (grup,kondisi)
    train fold, fallback median grup (<3), lalu median kategori (<3).
    Baseline TIDAK berubah di Fase A2. Yang berubah hanya metrik
    pemisah: group_n = jumlah baris grup produk yang sama di train
    fold, TANPA kondisi dan TANPA rantai fallback.
    src_col (A3-4): bila diisi, kolom src pada baris test diganti
    RATA-RATA src train fold (anti-leakage: user app tidak memilih
    sumber), sementara fit tetap memakai src asli train fold."""
    n = len(prices)
    if n < N_SPLITS:
        return None
    kf = KFold(n_splits=N_SPLITS, shuffle=True, random_state=SEED)
    oof_log = np.full(n, np.nan)
    oof_base = np.full(n, np.nan)
    group_n = np.zeros(n, dtype=int)
    for train_idx, test_idx in kf.split(X):
        pipe = Pipeline([("scaler", StandardScaler()),
                         ("ridge", Ridge(alpha=ALPHA))])
        X_tr = X[train_idx]
        X_te = X[test_idx].copy()
        if src_col is not None:
            X_te[:, src_col] = X_tr[:, src_col].mean()
        pipe.fit(X_tr, y[train_idx])
        oof_log[test_idx] = pipe.predict(X_te)
        gc = defaultdict(list)
        g = defaultdict(list)
        for j in train_idx:
            gc[(groups[j], conds[j])].append(prices[j])
            g[groups[j]].append(prices[j])
        cat_prices = list(prices[train_idx])
        for j in test_idx:
            pool = gc.get((groups[j], conds[j]))
            if pool is None or len(pool) < 3:
                pool = g.get(groups[j])
            if pool is None or len(pool) < 3:
                pool = cat_prices
            oof_base[j] = float(np.median(pool))
            group_n[j] = int((groups[train_idx] == groups[j]).sum())
    model_pred = np.exp(oof_log)
    lt = group_n < 5
    ge = ~lt
    return {
        "mae_model": _mae(model_pred, prices),
        "mae_baseline": _mae(oof_base, prices),
        "mape_model": _mape(model_pred, prices),
        "mape_baseline": _mape(oof_base, prices),
        "sigma_log": float(np.std(oof_log - y, ddof=1)),
        "mae_model_a_group_lt5": _mae(model_pred[lt], prices[lt]) if lt.any() else None,
        "mae_baseline_a_group_lt5": _mae(oof_base[lt], prices[lt]) if lt.any() else None,
        "mae_model_a_group_ge5": _mae(model_pred[ge], prices[ge]) if ge.any() else None,
        "mae_baseline_a_group_ge5": _mae(oof_base[ge], prices[ge]) if ge.any() else None,
        "n_group_lt5": int(lt.sum()),
        "n_group_ge5": int(ge.sum()),
    }


def eval_b(X, y, prices, groups, src_col=None):
    """GroupKFold 5 (grup = kunci produk). Baseline = median kategori
    train fold. None bila jumlah grup < 5. src_col (A3-4): sama
    seperti eval_a, kolom src baris test diganti rata-rata train."""
    if len(set(groups.tolist())) < N_SPLITS:
        return None
    gkf = GroupKFold(n_splits=N_SPLITS)
    oof = np.full(len(prices), np.nan)
    base = np.full(len(prices), np.nan)
    for train_idx, test_idx in gkf.split(X, y, groups):
        pipe = Pipeline([("scaler", StandardScaler()),
                         ("ridge", Ridge(alpha=ALPHA))])
        X_tr = X[train_idx]
        X_te = X[test_idx].copy()
        if src_col is not None:
            X_te[:, src_col] = X_tr[:, src_col].mean()
        pipe.fit(X_tr, y[train_idx])
        oof[test_idx] = pipe.predict(X_te)
        base[test_idx] = float(np.median(prices[train_idx]))
    return {
        "mae_model_group": _mae(np.exp(oof), prices),
        "mae_category_median_group": _mae(base, prices),
    }


def fit_final_raw(X, y):
    """Fit scaler+Ridge di semua baris, konversi koefisien ke skala
    mentah, SELF-CHECK lawan prediksi pipeline (maks < 1e-6)."""
    pipe = Pipeline([("scaler", StandardScaler()),
                     ("ridge", Ridge(alpha=ALPHA))])
    pipe.fit(X, y)
    scaler = pipe.named_steps["scaler"]
    ridge = pipe.named_steps["ridge"]
    scale = np.where(scaler.scale_ == 0, 1.0, scaler.scale_)
    coef_raw = ridge.coef_ / scale
    intercept_raw = float(ridge.intercept_
                          - np.sum(ridge.coef_ * scaler.mean_ / scale))
    raw_pred = X @ coef_raw + intercept_raw
    max_diff = float(np.max(np.abs(raw_pred - pipe.predict(X)))) if len(X) else 0.0
    if max_diff >= 1e-6:
        raise SystemExit(
            "SELF-CHECK GAGAL: prediksi koefisien mentah menyimpang "
            "%.3g dari pipeline sklearn (batas 1e-6)" % max_diff)
    return intercept_raw, coef_raw, max_diff


CAT_KEYS = {
    "enabled", "enabled_fallback", "reason", "reason_fallback",
    "intercept", "features", "defaults", "sigma_log", "n_rows",
    "mae_model", "mae_baseline", "mape_model", "mape_baseline",
    "mae_model_group", "mae_category_median_group",
    "mae_model_a_group_lt5", "mae_baseline_a_group_lt5",
    "mae_model_a_group_ge5", "mae_baseline_a_group_ge5",
    "n_group_lt5", "n_group_ge5",
    "src_variant", "src_variant_reason",
    "mae_model_a_nosrc", "mae_model_b_nosrc",
    "mae_model_a_withsrc", "mae_model_b_withsrc",
}


def fmt_rp(v):
    if v is None:
        return "-"
    return "Rp" + f"{int(round(v)):,}".replace(",", ".")


def fmt_pct(v):
    if v is None:
        return "-"
    return "%.1f%%" % (v * 100)


def fmt_num(v):
    if v is None:
        return "-"
    return "%.4g" % v


BUNDLE_MARKERS = ["pc rakitan", "pc gaming", "paket", "bundling",
                  "set pc"]
MARKER_RES = [(p, re.compile(r"\b" + re.escape(p) + r"\b"))
              for p in BUNDLE_MARKERS]
GPU_PAIR_RE = re.compile(r"(rtx|gtx|rx)\s*\d{3,4}")
CPU_PAIR_RE = re.compile(r"(ryzen\s*[3579]|core\s*i[3579])\s*-?\s*\d{4,5}")
RAM_CTX_RE = re.compile(r"\bram\b|\bddr\s*[345]\b")
GB_PAIR_RE = re.compile(r"\b\d{1,2}\s*gb\b")
SSD_SIZE_RE = re.compile(r"\b\d{1,4}\s*gb\b|\b\d\s*tb\b")
SSD_TOK_RE = re.compile(r"\bssd\b|\bnvme\b|\bhdd\b|\bharddisk\b"
                        r"|\bhardisk\b|\bm\.?2\b")
# A5: varian BARU deteksi pasangan. Konstanta lama di atas TIDAK diubah
# (dipakai first_model_pos aturan aksesori); pair_types_old di bawah
# mempertahankan perilaku lama untuk diff verdict lama-vs-baru.
GPU_PAIR_NEW_RE = re.compile(r"\b(rtx|gtx|rx)\s*\d{3,4}")
OLD_CPU_RE = re.compile(
    r"\b(pentium|celeron|athlon|core\s*2(?![\d.])\s*(duo|quad)?)\b")
PLUS_COMP_RE = re.compile(r"\+\s*(mobo|motherboard|processor|ram|vga)\b")
PLUS_COMP_TYPE = {"mobo": "motherboard", "motherboard": "motherboard",
                  "processor": "cpu", "ram": "ram", "vga": "gpu"}
SSD_KINGSTON_CTX_RE = re.compile(r"\bssd\b|\bkingston\b")


def pair_types_old(title):
    """Aturan pasangan LAMA (pra-A5), dipertahankan untuk diff."""
    t = (title or "").lower()
    types = set()
    if GPU_PAIR_RE.search(t):
        types.add("gpu")
    if CPU_PAIR_RE.search(t):
        types.add("cpu")
    if CHIPSET_RE.search(t):
        types.add("motherboard")
    if RAM_CTX_RE.search(t) and GB_PAIR_RE.search(t):
        types.add("ram")
    if SSD_SIZE_RE.search(t) and SSD_TOK_RE.search(t):
        types.add("storage")
    return types


def pair_types(title):
    """Jenis komponen yang disebut di judul (untuk deteksi pasangan).

    A5 vs aturan lama: (a) model GPU butuh word boundary di awal
    (jadi "VENOMRX 256" TIDAK terbaca GPU, tapi "RTX 4060"/"RX 580"/
    "GTX 1660" tetap cocok); (b) "a400" TIDAK dihitung chipset bila
    judul memuat token ssd/kingston (Kingston A400 adalah SSD) —
    chipset lain di judul yang sama tetap dihitung; (c) CPU lama
    (Pentium, Celeron, Athlon, Core 2) dihitung tipe cpu, dan pola
    "+ mobo/motherboard/processor/ram/vga" (plus LANGSUNG sebelum kata
    benda) dihitung tipe komponen itu — plus sebelum kata lain (box,
    fan, bonus) dan plus SESUDAH kata benda ("ram+ddr4") bukan pola
    ini. GB telanjang TIDAK dihitung sebagai RAM (bisa VRAM); RAM
    butuh konteks ram/ddr. SSD butuh ukuran + token ssd/nvme/hdd/m.2."""
    t = (title or "").lower()
    types = set()
    if GPU_PAIR_NEW_RE.search(t):
        types.add("gpu")
    if CPU_PAIR_RE.search(t) or OLD_CPU_RE.search(t):
        types.add("cpu")
    ssd_ctx = bool(SSD_KINGSTON_CTX_RE.search(t))
    for m in CHIPSET_RE.finditer(t):
        if m.group(1) == "a400" and ssd_ctx:
            continue
        types.add("motherboard")
        break
    if RAM_CTX_RE.search(t) and GB_PAIR_RE.search(t):
        types.add("ram")
    if SSD_SIZE_RE.search(t) and SSD_TOK_RE.search(t):
        types.add("storage")
    pm = PLUS_COMP_RE.search(t)
    if pm:
        types.add(PLUS_COMP_TYPE[pm.group(1)])
    return types


def bundle_filter(df):
    """Filter bundle/rakitan Fase A2 (MENGGANTIKAN aturan Fase A).

    Diterapkan setelah filter harga, sebelum ekstraksi fitur dan IQR.
    Baris dihitung sekali, penanda didahulukan:
    (a) penanda frasa HANYA di JUDUL, word boundary (jadi "paketan"
    TIDAK memicu "paket"); daftar akhir tanpa "fullset"/"full set":
    pc rakitan, pc gaming, paket, bundling, set pc;
    (b) deteksi pasangan: baris kategori single-komponen (gpu, cpu,
    ram, storage, motherboard) dibuang bila judulnya memuat dua jenis
    komponen BERBEDA (aturan kombo 3 jenis Fase A adalah subset dari
    ini). Laptop DIKECUALIKAN dari aturan pasangan.
    A5: aturan pasangan memakai pair_types baru (boundary rx/gtx/rtx,
    a400 bukan chipset bila konteks ssd/kingston, CPU lama + pola
    "+ kata-benda-komponen"); verdict aturan lama (pair_types_old)
    tetap dihitung pada populasi yang sama untuk diff, dan filter
    yang diterapkan adalah aturan baru.
    Mengembalikan (df_sisa, stats) dengan stats per kategori berisi
    hitungan penanda, pasangan, contoh, dan judul lolos yang mengandung
    "+", "&", atau "paketan" (maks 4 per kategori, untuk inspeksi).
    """
    stats = {}
    keep_idx = []
    for idx, row in df.iterrows():
        cat = row["category"]
        if cat not in CATEGORIES:
            keep_idx.append(idx)
            continue
        st = stats.setdefault(cat, {"marker": 0, "pair": 0,
                                    "examples_marker": [],
                                    "examples_pair": [],
                                    "passed_special": [],
                                    "pair_diff_new_drop": 0,
                                    "pair_diff_new_pass": 0,
                                    "examples_new_drop": [],
                                    "examples_new_pass": [],
                                    "_per_marker": {}})
        title = str(row["raw_title"])
        tlow = title.lower()
        hit = None
        for phrase, rx in MARKER_RES:
            if rx.search(tlow):
                hit = phrase
                break
        if hit is not None:
            st["marker"] += 1
            if st["_per_marker"].get(hit, 0) < 2:
                st["examples_marker"].append((title, hit))
                st["_per_marker"][hit] = st["_per_marker"].get(hit, 0) + 1
            continue
        if cat != "laptop":
            # A5: diff verdict aturan lama-vs-baru pada populasi yang
            # SAMA (baris yang lolos penanda dan mencapai cek pasangan;
            # penanda tidak berubah sehingga tidak masuk diff).
            old_types = pair_types_old(title)
            types = pair_types(title)
            old_drop = len(old_types) >= 2
            new_drop = len(types) >= 2
            if old_drop and not new_drop:
                st["pair_diff_new_pass"] += 1
                st["examples_new_pass"].append(
                    (title, "+".join(sorted(old_types)) + " -> "
                     + ("+".join(sorted(types)) or "-")))
            elif new_drop and not old_drop:
                st["pair_diff_new_drop"] += 1
                st["examples_new_drop"].append(
                    (title, ("+".join(sorted(old_types)) or "-") + " -> "
                     + "+".join(sorted(types))))
            if new_drop:
                st["pair"] += 1
                st["examples_pair"].append(
                    (title, "+".join(sorted(types))))
                continue
        keep_idx.append(idx)
        if ("+" in title or "&" in title or "paketan" in tlow) \
                and len(st["passed_special"]) < 4:
            st["passed_special"].append(title)
    for st in stats.values():
        st.pop("_per_marker", None)
    return df.loc[keep_idx], stats


def normalize_title(title):
    """Normalisasi judul untuk dedupe A3-5: lowercase, non-alfanumerik
    jadi spasi, rapikan spasi berlebih, trim."""
    t = (title or "").lower()
    t = re.sub(r"[^a-z0-9]+", " ", t)
    return re.sub(r"\s+", " ", t).strip()


def dedupe_normalized(df):
    """A3-5: dedupe (seller, judul ternormalisasi), sisakan baris
    pertama menurut urutan CSV. Mengembalikan (df_sisa, hitungan)."""
    seen = set()
    keep_idx = []
    dropped = Counter()
    for idx, row in df.iterrows():
        cat = row["category"]
        key = (str(row["seller"]), normalize_title(str(row["raw_title"])))
        if key in seen:
            if cat in CATEGORIES:
                dropped[cat] += 1
            continue
        seen.add(key)
        keep_idx.append(idx)
    return df.loc[keep_idx], dict(dropped)


PLACEHOLDER_EXACT = {123456789, 987654321, 123123}
REPEATED_DIGITS_RE = re.compile(r"^(\d)\1{4,}$")


def placeholder_reason(price_int):
    """A3-1: alasan harga placeholder (None bila bukan placeholder).
    Urutan: nilai persis -> digit berulang 5+ kali pada seluruh angka
    -> angka diawali '12345'. Dihitung sekali, pola pertama menang."""
    if price_int in PLACEHOLDER_EXACT:
        return "exact"
    s = str(price_int)
    if REPEATED_DIGITS_RE.match(s):
        return "repeated"
    if s.startswith("12345"):
        return "prefix12345"
    return None


def placeholder_filter(df):
    """A3-1: buang harga placeholder SETELAH filter rentang (jadi yang
    dihitung hanya baris yang lolos rentang tapi dibuang aturan ini).
    Mengembalikan (df_sisa, stats per kategori per pola)."""
    stats = {}
    keep_idx = []
    for idx, row in df.iterrows():
        cat = row["category"]
        reason = placeholder_reason(int(float(row["_price_num"])))
        if reason is None or cat not in CATEGORIES:
            keep_idx.append(idx)
            continue
        st = stats.setdefault(cat, {"exact": 0, "repeated": 0,
                                    "prefix12345": 0, "total": 0})
        st[reason] += 1
        st["total"] += 1
    return df.loc[keep_idx], stats


ACCESSORY_PHRASES = ["fan", "kipas", "thermal paste", "thermal pad",
                     "bracket", "riser", "backplate", "waterblock",
                     "water block", "baterai", "charger", "adaptor",
                     "adapter", "lcd", "keyboard", "engsel", "casing",
                     "enclosure", "converter"]
ACCESSORY_RES = [(p, re.compile(r"\b" + re.escape(p) + r"\b"))
                 for p in ACCESSORY_PHRASES]
FAN_COUNT_RE = re.compile(
    r"\b(single|dual|triple|quad|double|twin|2|3)\s*x?\s*(fan|kipas)\b")
LAPTOP_COMPONENT_START_RE = re.compile(
    r"^(ram|ssd|hdd|memory|sodimm)\b")


def first_model_pos(t):
    """Posisi awal pola model komponen pertama di judul (None bila
    tidak ada). Dipakai aturan aksesori A3-2."""
    positions = []
    for rx in (GPU_PAIR_RE, CPU_PAIR_RE, CHIPSET_RE):
        m = rx.search(t)
        if m:
            positions.append(m.start())
    if RAM_CTX_RE.search(t):
        m = GB_PAIR_RE.search(t)
        if m:
            positions.append(m.start())
    if SSD_TOK_RE.search(t):
        m = SSD_SIZE_RE.search(t)
        if m:
            positions.append(m.start())
    return min(positions) if positions else None


def accessory_filter(df):
    """A3-2: buang aksesori/salah kategori dari JUDUL (lowercase,
    hyphen dinormalisasi jadi spasi). Baris dibuang bila:
    (a) judul DIAWALI frasa aksesori, ATAU frasa aksesori muncul
    SEBELUM pola model komponen apa pun (model yang disebut hanya
    kompatibilitas); (b) khusus laptop, judul diawali
    ram/ssd/hdd/memory/sodimm.
    PENGECUALIAN: spek jumlah fan ('dual fan', 'triple fan',
    'single fan', dan pola sejenis) dihapus dulu dari teks sebelum
    dicek, sehingga 'VGA RTX 3060 Dual Fan' lolos sementara
    'Kipas VGA RTX 3060' dibuang.
    Mengembalikan (df_sisa, stats) dengan 15 contoh buang per kategori
    dan judul lolos ber-fan/kipas (maks 4 per kategori)."""
    stats = {}
    keep_idx = []
    for idx, row in df.iterrows():
        cat = row["category"]
        if cat not in CATEGORIES:
            keep_idx.append(idx)
            continue
        st = stats.setdefault(cat, {"count": 0, "examples": [],
                                    "passed_fan": []})
        title = str(row["raw_title"])
        norm = re.sub(r"\s+", " ",
                      title.lower().replace("-", " ")).strip()
        checked = FAN_COUNT_RE.sub(" ", norm)
        drop_rule = None
        if cat == "laptop" and LAPTOP_COMPONENT_START_RE.search(norm):
            drop_rule = "laptop_awal_komponen"
        else:
            acc_pos = None
            acc_phrase = None
            for phrase, rx in ACCESSORY_RES:
                m = rx.search(checked)
                if m and (acc_pos is None or m.start() < acc_pos):
                    acc_pos = m.start()
                    acc_phrase = phrase
            if acc_pos is not None:
                model_pos = first_model_pos(checked)
                if acc_pos == 0 or (model_pos is not None
                                    and acc_pos < model_pos):
                    drop_rule = "aksesori:" + acc_phrase
        if drop_rule is not None:
            st["count"] += 1
            if len(st["examples"]) < 15:
                st["examples"].append((title, drop_rule))
            continue
        keep_idx.append(idx)
        tlow = title.lower()
        if ("fan" in tlow or "kipas" in tlow) \
                and len(st["passed_fan"]) < 4:
            st["passed_fan"].append(title)
    return df.loc[keep_idx], stats


def diverse_examples(examples, limit=10):
    """Urutkan contoh agar beragam aturan dulu, baru sisanya."""
    seen_rules = []
    for _, rule in examples:
        if rule not in seen_rules:
            seen_rules.append(rule)
    out = []
    for rule in seen_rules:
        for title, r in examples:
            if r == rule and (title, r) not in out:
                out.append((title, r))
                break
    for item in examples:
        if item not in out:
            out.append(item)
    return out[:limit]


POPULAR_GPUS = ["rtx 3050", "rtx 3060", "rtx 3060 ti", "rtx 4060",
                "rtx 4060 ti", "rtx 4070", "rx 6600", "rx 6700 xt",
                "gtx 1650", "gtx 1660 super"]


def _spearman(scores, medians):
    if len(scores) < 3:
        return None
    v = pd.Series(scores, dtype=float).corr(
        pd.Series(medians, dtype=float), method="spearman")
    return None if pd.isna(v) else float(v)


def _choose_scale(cov_c, cov_b, sp_c, sp_b):
    """Aturan pilih SATU skala per kolom (didokumentasikan di laporan):
    skala dengan coverage baris < 30% didiskualifikasi bila skala lain
    >= 30%; di antara yang lolos, Spearman interseksi lebih tinggi
    menang; bila selisih Spearman < 0,05, coverage lebih tinggi menang;
    bila Spearman tak tersedia, coverage yang menang."""
    if cov_c < 0.30 and cov_b >= 0.30:
        return "passmark", "coverage konsensus < 30%, passmark lolos"
    if cov_b < 0.30 and cov_c >= 0.30:
        return "consensus", "coverage passmark < 30%, konsensus lolos"
    if sp_c is not None and sp_b is not None \
            and abs(sp_c - sp_b) >= 0.05:
        if sp_c > sp_b:
            return "consensus", "spearman interseksi lebih tinggi"
        return "passmark", "spearman interseksi lebih tinggi"
    if cov_c >= cov_b:
        return "consensus", "spearman setara/tak tersedia, coverage menang"
    return "passmark", "spearman setara/tak tersedia, coverage menang"


def _sanity_column(rows, model_fn, cons_cat, bench_cat):
    """rows: list (title, spec, price). Mengembalikan tabel per model +
    metrik kedua skala. Median harga per model mencampur kondisi
    (new/second/unknown) — sanity monotonisitas, bukan evaluasi model."""
    by_model = defaultdict(list)
    for title, spec, price in rows:
        m = model_fn((title + " " + spec))
        if m is not None:
            by_model[m].append(price)
    models = {}
    for m, prices in by_model.items():
        c_score, c_key = lookup_score(m, cons_cat, "consensus_score")
        b_score, b_key = lookup_score(m, bench_cat, "score")
        models[m] = {"n": len(prices),
                     "median": float(np.median(prices)),
                     "cons_key": c_key, "cons_score": c_score,
                     "bench_key": b_key, "bench_score": b_score}
    n_with = sum(v["n"] for v in models.values())
    n_c = sum(v["n"] for v in models.values()
              if v["cons_score"] is not None)
    n_b = sum(v["n"] for v in models.values()
              if v["bench_score"] is not None)
    cov_c = n_c / n_with if n_with else 0.0
    cov_b = n_b / n_with if n_with else 0.0
    sp_c = _spearman([v["cons_score"] for v in models.values()
                      if v["cons_score"] is not None],
                     [v["median"] for v in models.values()
                      if v["cons_score"] is not None])
    sp_b = _spearman([v["bench_score"] for v in models.values()
                      if v["bench_score"] is not None],
                     [v["median"] for v in models.values()
                      if v["bench_score"] is not None])
    inter = [v for v in models.values()
             if v["cons_score"] is not None
             and v["bench_score"] is not None]
    sp_ic = _spearman([v["cons_score"] for v in inter],
                      [v["median"] for v in inter])
    sp_ib = _spearman([v["bench_score"] for v in inter],
                      [v["median"] for v in inter])
    chosen, reason = _choose_scale(cov_c, cov_b, sp_ic, sp_ib)
    return {"models": models, "n_rows": len(rows), "n_with_model": n_with,
            "cov_cons": cov_c, "cov_bench": cov_b,
            "n_models_cons": sum(1 for v in models.values()
                                 if v["cons_score"] is not None),
            "n_models_bench": sum(1 for v in models.values()
                                  if v["bench_score"] is not None),
            "n_models_inter": len(inter),
            "sp_cons": sp_c, "sp_bench": sp_b,
            "sp_inter_cons": sp_ic, "sp_inter_bench": sp_ib,
            "chosen": chosen, "choice_reason": reason}


def score_sanity(df_clean, cons_gpu, cons_cpu, bench_gpu, bench_cpu):
    """Sanity skor untuk kolom gpu, cpu, dan GPU laptop. df sudah
    dedupe + filter harga + filter bundle (populasi input latih)."""
    def rows_of(cat):
        sub = df_clean[df_clean["category"] == cat]
        return [(str(t), str(s), float(p))
                for t, s, p in zip(sub["raw_title"], sub["raw_spec_text"],
                                   sub["_price_num"])]
    out = {
        "gpu": _sanity_column(rows_of("gpu"), extract_gpu_model,
                              cons_gpu, bench_gpu),
        "cpu": _sanity_column(rows_of("cpu"), extract_cpu_model,
                              cons_cpu, bench_cpu),
        "laptop_gpu": _sanity_column(rows_of("laptop"), extract_gpu_model,
                                     cons_gpu, bench_gpu),
    }
    gpu_models = out["gpu"]["models"]
    out["popular_gpu"] = [
        {"model": m,
         "cons_score": gpu_models[m]["cons_score"]
         if m in gpu_models else None,
         "bench_score": gpu_models[m]["bench_score"]
         if m in gpu_models else None,
         "n": gpu_models[m]["n"] if m in gpu_models else 0,
         "median": gpu_models[m]["median"] if m in gpu_models else None}
        for m in POPULAR_GPUS]
    return out


def _count_patterns(titles, patterns):
    """Hitung pola kebocoran dengan prioritas (satu judul satu pola)."""
    counts = Counter()
    for t in titles:
        low = (t or "").lower()
        hit = None
        for name, rx in patterns:
            if rx.search(low):
                hit = name
                break
        counts[hit if hit else "lainnya"] += 1
    return dict(counts)


def _fmt_counts(d):
    return "; ".join("%s: %d" % (k, v) for k, v in sorted(d.items()))


def build_report(ctx, results, trained_at):
    """ctx: info jalan; results: dict kategori -> dict laporan."""
    lines = []
    lines.append("# Laporan ML Harga Wajar")
    lines.append("")
    lines.append("Laporan Step 1 resmi (Fase B) model harga wajar "
                 "WorthBang. Model dilatih dari skrip "
                 "tools/ml/train_price_models.py (logika A5, tanpa "
                 "perubahan) dan dipakai AnalysisEngine sebagai "
                 "fallback Tier 2 saat pembanding exact-match < 5.")
    lines.append("")
    lines.append("- Tanggal latih (trained_at): %s" % trained_at)
    lines.append("- Input: %s (%d baris CSV)" % (ctx["input"], ctx["csv_rows"]))
    lines.append("- md5 CSV: %s" % ctx["csv_md5"])
    lines.append("- Konsensus generated_at: %s; benchmark generated_at: %s"
                 % (ctx["cons_gen"], ctx["bench_gen"]))
    lines.append("- venv: tools/ml/.venv (pandas, numpy, scikit-learn)")
    lines.append("- Perintah reproduksi: tools/ml/.venv/bin/python "
                 "tools/ml/train_price_models.py --out "
                 "assets/data/price_models.json --report docs/ml_report.md "
                 "--dump-parity --parity-out test/fixtures/ml_parity.json")
    lines.append("")
    lines.append("## Definisi kunci grup produk (dari FITUR FINAL)")
    lines.append("")
    lines.append("- gpu = (model, vram); cpu = (model); "
                 "ram = (ddr, total_gb); storage = (tipe, kapasitas_gb); "
                 "motherboard = (chipset); laptop = (cpu_sig, gpu_sig).")
    lines.append("- Baseline (a): median pool (grup, kondisi) train fold; "
                 "bila (grup, kondisi) < 3 baris pakai median grup; bila "
                 "grup < 3 baris pakai median kategori.")
    lines.append("- Baseline (b): median kategori train fold (GroupKFold).")
    lines.append("- Pemisah evaluasi (a) Fase A2: group_n = jumlah baris "
                 "grup produk yang sama di train fold, TANPA kondisi dan "
                 "TANPA rantai fallback (perhitungan baseline (a) sendiri "
                 "tidak berubah). Segmen group_n < 5 vs >= 5; segmen dengan "
                 "n < 20 ditandai 'tidak cukup untuk disimpulkan'.")
    lines.append("- Gerbang Fase A2: Tier 1 butuh >= 150 baris bersih dan "
                 "MAE (a) model < MAE (a) baseline. Tier 2 butuh >= 100 "
                 "baris bersih DAN MAE (b) model <= 0,9 x MAE median "
                 "kategori (b) (lebih kecil minimal 10%). Gerbang 150 "
                 "tidak lagi diterapkan ke Tier 2.")
    lines.append("- Gerbang A4 (menggantikan syarat Tier 1 A2): Tier 1 "
                 "butuh >= 150 baris bersih DAN MAE (a) model <= 0,95 x "
                 "MAE (a) baseline (lebih kecil minimal 5%). Tier 2 "
                 "TETAP >= 100 baris DAN MAE (b) model <= 0,9 x MAE "
                 "median kategori (b).")
    lines.append("- Gerbang A5 (MENGGANTIKAN gerbang A4): Tier 1 "
                 "DINONAKTIFKAN untuk semua kategori (enabled=false); "
                 "alasan per kategori ditulis dari angka segmen group_n "
                 ">= 5 evaluasi (a) run ini. Tier 2 butuh KETIGA syarat: "
                 "(i) baris bersih >= 100; (ii) MAE (b) model <= 0,9 x "
                 "median kategori (b); (iii) BILA segmen group_n < 5 "
                 "evaluasi (a) punya n >= 20, MAE model segmen itu <= "
                 "MAE baseline segmen itu (segmen n < 20 tidak "
                 "menggugurkan). Model final A5 TANPA fitur "
                 "src_tokopedia; varian with_src hanya perbandingan.")
    lines.append("- Filter pasangan A5 (judul saja, single-komponen, "
                 "laptop dikecualikan): model GPU butuh word boundary "
                 "di awal (VENOMRX bukan GPU); 'a400' bukan chipset bila "
                 "konteks ssd/kingston; CPU lama (Pentium, Celeron, "
                 "Athlon, Core 2) dihitung tipe cpu; pola '+ mobo/"
                 "motherboard/processor/ram/vga' dihitung tipe komponen "
                 "itu. Diff verdict lama-vs-baru ada di seksi Diff "
                 "filter pasangan.")
    lines.append("- Aturan pilih skala skor (Fase A2): skala dengan "
                 "coverage baris < 30% didiskualifikasi bila skala lain "
                 ">= 30%; di antara yang lolos, Spearman interseksi "
                 "lebih tinggi menang; bila selisih < 0,05, coverage "
                 "lebih tinggi menang; bila Spearman tak tersedia, "
                 "coverage yang menang.")
    lines.append("")
    lines.append("## Hasil per kategori (model final tanpa-src, A5)")
    lines.append("")
    lines.append("| kategori | baris bersih | enabled | fallback | "
                 "varian src | MAE (a) model | MAE (a) baseline | MAPE model | "
                 "MAPE baseline | MAE (b) model | MAE (b) median kategori |")
    lines.append("|---|---|---|---|---|---|---|---|---|---|---|")
    for cat in CATEGORIES:
        r = results[cat]
        lines.append("| %s | %d | %s | %s | %s | %s | %s | %s | %s | %s | %s |" % (
            cat, r["n_rows"], r["enabled"], r["enabled_fallback"],
            r.get("src_variant", "-"),
            fmt_rp(r["mae_model"]), fmt_rp(r["mae_baseline"]),
            fmt_pct(r["mape_model"]), fmt_pct(r["mape_baseline"]),
            fmt_rp(r["mae_model_group"]),
            fmt_rp(r["mae_category_median_group"])))
    lines.append("")
    lines.append("## Eksperimen source (A3-4, dua varian per kategori)")
    lines.append("")
    lines.append("PERBANDINGAN SAJA — model final A5 TANPA src_tokopedia "
                 "untuk semua kategori; varian with_src di bawah TIDAK "
                 "dipakai untuk gerbang maupun JSON final. Varian "
                 "dengan-src dilatih dengan nilai src asli, tapi "
                 "DIEVALUASI dengan kolom src baris test diganti rata-rata "
                 "src train fold (anti-leakage: user app tidak memilih "
                 "sumber). Kolom 'model final' selalu tanpa-src.")
    lines.append("")
    lines.append("| kategori | MAE (a) tanpa-src | MAE (a) dengan-src | "
                 "MAE (b) tanpa-src | MAE (b) dengan-src | model final | "
                 "alasan |")
    lines.append("|---|---|---|---|---|---|---|")
    for cat in CATEGORIES:
        r = results[cat]
        lines.append("| %s | %s | %s | %s | %s | %s | %s |" % (
            cat, fmt_rp(r.get("mae_model_a_nosrc")),
            fmt_rp(r.get("mae_model_a_withsrc")),
            fmt_rp(r.get("mae_model_b_nosrc")),
            fmt_rp(r.get("mae_model_b_withsrc")),
            r.get("src_variant", "-"),
            r.get("src_variant_reason", "-")))
    lines.append("")
    lines.append("## Pecahan MAE evaluasi (a) menurut group_n (Fase A2)")
    lines.append("")
    lines.append("group_n = jumlah baris grup produk yang sama di train "
                 "fold (tanpa kondisi, tanpa fallback). Segmen n < 20 "
                 "ditandai 'tidak cukup untuk disimpulkan'.")
    lines.append("")
    lines.append("| kategori | n group_n < 5 | MAE model < 5 | MAE baseline < 5 | "
                 "n group_n >= 5 | MAE model >= 5 | MAE baseline >= 5 |")
    lines.append("|---|---|---|---|---|---|---|")
    for cat in CATEGORIES:
        r = results[cat]
        flag_lt = " (tidak cukup untuk disimpulkan)" \
            if r["n_group_lt5"] < 20 else ""
        flag_ge = " (tidak cukup untuk disimpulkan)" \
            if r["n_group_ge5"] < 20 else ""
        lines.append("| %s | %d%s | %s | %s | %d%s | %s | %s |" % (
            cat, r["n_group_lt5"], flag_lt,
            fmt_rp(r["mae_model_a_group_lt5"]),
            fmt_rp(r["mae_baseline_a_group_lt5"]), r["n_group_ge5"],
            flag_ge, fmt_rp(r["mae_model_a_group_ge5"]),
            fmt_rp(r["mae_baseline_a_group_ge5"])))
    lines.append("")
    lines.append("## Gerbang baru (A5)")
    lines.append("")
    lines.append("Tier 1 DINONAKTIFKAN untuk semua kategori "
                 "(enabled=false, tanpa kecuali). Alasan Tier 1 di bawah "
                 "memakai angka segmen group_n >= 5 evaluasi (a) run ini "
                 "— bukan gerbang lama — dengan interpretasi jujur. "
                 "Tier 2 butuh KETIGA syarat: (i) baris bersih >= 100; "
                 "(ii) MAE (b) model <= 0,9 x median kategori (b); "
                 "(iii) BILA segmen group_n < 5 punya n >= 20, MAE model "
                 "segmen itu <= MAE baseline segmen itu (segmen n < 20 "
                 "tidak menggugurkan).")
    lines.append("")
    lines.append("| kategori | baris bersih | n group_n < 5 | MAE model < 5 | "
                 "MAE baseline < 5 | n group_n >= 5 | MAE model >= 5 | "
                 "MAE baseline >= 5 | Tier 1 | Tier 2 |")
    lines.append("|---|---|---|---|---|---|---|---|---|---|")
    for cat in CATEGORIES:
        r = results[cat]
        lines.append("| %s | %d | %d | %s | %s | %d | %s | %s | %s | "
                     "%s |" % (
            cat, r["n_rows"], r["n_group_lt5"],
            fmt_rp(r["mae_model_a_group_lt5"]),
            fmt_rp(r["mae_baseline_a_group_lt5"]), r["n_group_ge5"],
            fmt_rp(r["mae_model_a_group_ge5"]),
            fmt_rp(r["mae_baseline_a_group_ge5"]),
            r["enabled"], r["enabled_fallback"]))
    lines.append("")
    for cat in CATEGORIES:
        r = results[cat]
        lines.append("- %s: Tier 1 enabled=false "
                     "(alasan: %s)." % (cat, r["reason"]))
        mod_ge, base_ge = (r["mae_model_a_group_ge5"],
                           r["mae_baseline_a_group_ge5"])
        if r["n_group_ge5"] < 20:
            interp = ("segmen >= 5 hanya n=%d (tidak cukup untuk "
                      "disimpulkan); penonaktifan Tier 1 adalah kebijakan "
                      "A5, bukan vonis dari segmen ini"
                      % r["n_group_ge5"])
        elif mod_ge is None or base_ge is None or base_ge == 0:
            interp = "angka segmen >= 5 tidak tersedia"
        elif mod_ge <= base_ge:
            pct = 100.0 * (1.0 - mod_ge / base_ge)
            interp = ("di segmen >= 5 model %s vs baseline %s "
                      "(menang tipis %.1f%% — dalam noise, bukan "
                      "kemenangan meyakinkan; tetap dinonaktifkan "
                      "karena kebijakan A5)"
                      % (fmt_rp(mod_ge), fmt_rp(base_ge), pct))
        else:
            pct = 100.0 * (mod_ge / base_ge - 1.0)
            interp = ("di segmen >= 5 model %s vs baseline %s "
                      "(kalah %.1f%% — median produk persis lebih kuat "
                      "bila pembanding banyak)"
                      % (fmt_rp(mod_ge), fmt_rp(base_ge), pct))
        lines.append("  - Alasan Tier 1: %s." % interp)
        c1 = r["n_rows"] >= 100
        c2 = r["mae_model_group"] is not None \
            and r["mae_category_median_group"] is not None \
            and r["mae_model_group"] <= TIER2_RATIO \
            * r["mae_category_median_group"]
        if r["n_group_lt5"] < 20:
            c3txt = ("syarat (iii) dilewati (segmen < 5 hanya n=%d)"
                     % r["n_group_lt5"])
        elif r["mae_model_a_group_lt5"] is not None \
                and r["mae_baseline_a_group_lt5"] is not None:
            c3txt = ("syarat (iii) %s: MAE model segmen < 5 %s vs "
                     "baseline %s"
                     % ("LOLOS" if r["mae_model_a_group_lt5"]
                        <= r["mae_baseline_a_group_lt5"] else "GAGAL",
                        fmt_rp(r["mae_model_a_group_lt5"]),
                        fmt_rp(r["mae_baseline_a_group_lt5"])))
        else:
            c3txt = "syarat (iii) tidak dapat dihitung"
        lines.append("  - Tier 2 enabled_fallback=%s (alasan: %s): "
                     "syarat (i) %s (baris %d, butuh >= 100); syarat (ii) "
                     "%s (MAE (b) model %s vs ambang 0,9 x median %s); "
                     "%s."
                     % (r["enabled_fallback"], r["reason_fallback"],
                        "LOLOS" if c1 else "GAGAL", r["n_rows"],
                        "LOLOS" if c2 else "GAGAL",
                        fmt_rp(r["mae_model_group"]),
                        fmt_rp(TIER2_RATIO
                               * r["mae_category_median_group"])
                        if r["mae_category_median_group"] is not None
                        else "-", c3txt))
    lines.append("")
    lines.append("## Pembersihan per kategori (funnel lengkap, urutan A3)")
    lines.append("")
    lines.append("Urutan: mentah -> dedupe hash -> dedupe (seller, "
                 "raw_title) -> dedupe (seller, judul ternormalisasi) "
                 "-> filter harga 50rb-150jt -> filter placeholder -> "
                 "filter bundle A2 + perbaikan pasangan A5 -> filter "
                 "aksesori -> lolos ekstraksi "
                 "-> setelah IQR (final). Inferensi kondisi tidak "
                 "membuang baris.")
    lines.append("")
    lines.append("| kategori | mentah | dedupe hash+judul | dedupe judul "
                 "normalisasi (buang) | setelah harga | placeholder "
                 "(buang) | setelah bundle | aksesori (buang) | setelah "
                 "aksesori | lolos ekstraksi | setelah IQR (final) | "
                 "alasan buang ekstraksi |")
    lines.append("|---|---|---|---|---|---|---|---|---|---|---|---|")
    for cat in CATEGORIES:
        c = ctx["counts"][cat]
        d = results[cat].get("drops", {})
        drop_txt = "; ".join("%s: %d" % (k, v) for k, v in sorted(d.items()))
        lines.append("| %s | %d | %d | %d (%d) | %d | %d | %d | %d | %d | "
                     "%d | %d | %s |" % (
            cat, c["raw"], c["deduped"], c["deduped_norm"],
            c["deduped_norm_drop"], c["priced"],
            c["placeholder_total"], c["after_bundle"],
            c["accessory"], c["after_accessory"],
            c["stage_ok"], results[cat]["n_rows"],
            drop_txt if drop_txt else "-"))
    lines.append("")
    lines.append("## Filter placeholder (A3-1)")
    lines.append("")
    lines.append("Diterapkan SETELAH filter rentang (yang dihitung hanya "
                 "baris lolos rentang tapi dibuang aturan ini). Definisi: "
                 "nilai persis 123456789, 987654321, 123123; digit "
                 "berulang yang sama 5+ kali pada seluruh angka harga "
                 "(regex ^(\\d)\\1{4,}$, mis. 11111, 555555, 9999999); "
                 "angka yang digitnya diawali '12345' (12345x, mis. "
                 "123456, 1234567, 123450). Dihitung sekali per baris, "
                 "pola pertama menang (persis > berulang > awalan).")
    lines.append("")
    lines.append("| kategori | persis | berulang | awalan 12345 | total |")
    lines.append("|---|---|---|---|---|")
    for cat in CATEGORIES:
        c = ctx["counts"][cat]
        lines.append("| %s | %d | %d | %d | %d |" % (
            cat, c["placeholder_exact"], c["placeholder_repeated"],
            c["placeholder_prefix12345"], c["placeholder_total"]))
    lines.append("")
    lines.append("## Filter bundle/rakitan (Fase A2, MENGGANTIKAN Fase A)")
    lines.append("")
    lines.append("Diterapkan setelah filter placeholder, sebelum filter "
                 "aksesori, ekstraksi fitur, dan IQR. (a) Penanda frasa "
                 "HANYA di JUDUL, word boundary "
                 "(jadi 'paketan' TIDAK memicu 'paket'); daftar akhir: "
                 "pc rakitan, pc gaming, paket, bundling, set pc "
                 "('fullset'/'full set' DIHAPUS). (b) Deteksi pasangan: "
                 "baris kategori single-komponen (gpu, cpu, ram, storage, "
                 "motherboard) dibuang bila judulnya memuat dua jenis "
                 "komponen berbeda (model gpu, model cpu, chipset mobo, "
                 "spek ram berkonteks RAM/DDR, spek ssd berukuran+token). "
                 "Laptop DIKECUALIKAN dari aturan pasangan. Baris "
                 "dihitung sekali (penanda didahulukan).")
    lines.append("")
    lines.append("Perbaikan pasangan A5 (hanya deteksi pasangan; penanda "
                 "tidak berubah): (a) model GPU butuh word boundary di "
                 "awal kata — 'VENOMRX 256' TIDAK terbaca GPU, sementara "
                 "'RTX 4060', 'RX 580', 'GTX 1660' tetap cocok; "
                 "(b) 'a400' TIDAK dihitung chipset bila judul memuat "
                 "token ssd/kingston (Kingston A400 adalah SSD) — "
                 "chipset lain di judul yang sama tetap dihitung; "
                 "(c) CPU lama (Pentium, Celeron, Athlon, Core 2 "
                 "Duo/Quad) dihitung tipe cpu, dan pola '+ mobo/"
                 "motherboard/processor/ram/vga' (plus LANGSUNG sebelum "
                 "kata benda) dihitung tipe komponen itu — plus sebelum "
                 "kata lain (box, fan, bonus) dan plus SESUDAH kata "
                 "benda ('ram+ddr4') bukan pola ini.")
    lines.append("")
    lines.append("")
    lines.append("| kategori | setelah placeholder | buang penanda judul | "
                 "buang pasangan | setelah bundle |")
    lines.append("|---|---|---|---|---|")
    for cat in CATEGORIES:
        c = ctx["counts"][cat]
        lines.append("| %s | %d | %d | %d | %d |" % (
            cat, c["after_placeholder"], c["bundle_marker"], c["bundle_pair"],
            c["after_bundle"]))
    lines.append("")
    lines.append("### Diff filter pasangan (A5: aturan lama vs baru)")
    lines.append("")
    lines.append("Populasi diff = baris yang lolos penanda dan mencapai "
                 "cek pasangan (kategori single-komponen, laptop "
                 "dikecualikan), pada pipeline yang sama sampai tahap "
                 "itu. 'Baru dibuang' = lolos aturan lama, dibuang "
                 "aturan baru; 'baru lolos' = dibuang aturan lama, lolos "
                 "aturan baru. Hanya baris yang verdict-nya BERUBAH yang "
                 "masuk hitungan dan contoh di bawah.")
    lines.append("")
    lines.append("| kategori | baru dibuang | baru lolos |")
    lines.append("|---|---|---|")
    for cat in CATEGORIES:
        pdiff = ctx["bundle"][cat]["pair_diff"]
        lines.append("| %s | %d | %d |"
                     % (cat, pdiff["new_drop"], pdiff["new_pass"]))
    lines.append("")
    lines.append("#### Contoh BARU dibuang aturan A5 (maks 10, beragam "
                 "tanda lama -> baru)")
    for title, sig in diverse_examples(
            [(t, s) for t, s in
             sum([ctx["bundle"][c]["pair_diff"]["examples_new_drop"]
                  for c in CATEGORIES], [])]):
        lines.append("- [%s] %s" % (sig, title or "(judul kosong)"))
    lines.append("")
    lines.append("#### Contoh BARU lolos aturan A5 (maks 10, beragam "
                 "tanda lama -> baru)")
    for title, sig in diverse_examples(
            [(t, s) for t, s in
             sum([ctx["bundle"][c]["pair_diff"]["examples_new_pass"]
                  for c in CATEGORIES], [])]):
        lines.append("- [%s] %s" % (sig, title or "(judul kosong)"))
    lines.append("")
    lines.append("### Contoh judul dibuang filter bundle baru "
                 "(maks 10 per kategori, diurut beragam aturan)")
    lines.append("")
    for cat in CATEGORIES:
        lines.append("#### %s (penanda judul)" % cat)
        for title, rule in diverse_examples(
                ctx["bundle"][cat]["examples_marker"]):
            lines.append("- [%s] %s" % (rule, title or "(judul kosong)"))
        lines.append("#### %s (pasangan komponen)" % cat)
        for title, rule in diverse_examples(
                ctx["bundle"][cat]["examples_pair"]):
            lines.append("- [%s] %s" % (rule, title or "(judul kosong)"))
        lines.append("")
    lines.append("### Judul yang LOLOS tapi mengandung '+', '&', atau "
                 "'paketan' (total 10, beragam kategori, untuk inspeksi Dan)")
    lines.append("")
    pool = []
    cats_cycle = [c for c in CATEGORIES]
    per_cat = {c: list(ctx["bundle"][c]["passed_special"])
               for c in CATEGORIES}
    while len(pool) < 10 and any(per_cat.values()):
        for c in cats_cycle:
            if per_cat[c]:
                pool.append((c, per_cat[c].pop(0)))
            if len(pool) >= 10:
                break
    for cat, title in pool:
        lines.append("- [%s] %s" % (cat, title or "(judul kosong)"))
    lines.append("")
    lines.append("Baris diabaikan (kategori di luar latih, mis. pc): %d."
                 % ctx["ignored_rows"])
    lines.append("")
    lines.append("## Filter aksesori/salah kategori (A3-2)")
    lines.append("")
    lines.append("Diterapkan setelah filter bundle, dari JUDUL saja "
                 "(lowercase, hyphen dinormalisasi jadi spasi). Baris "
                 "dibuang bila judul DIAWALI kata aksesori, ATAU frasa "
                 "aksesori muncul SEBELUM pola model komponen apa pun "
                 "(model yang disebut hanya kompatibilitas). Daftar "
                 "aksesori: fan, kipas, thermal paste, thermal pad, "
                 "bracket, riser, backplate, waterblock, water block, "
                 "baterai, charger, adaptor, adapter (varian ejaan "
                 "adaptor), lcd, keyboard, engsel, casing, enclosure, "
                 "converter. PENGECUALIAN: spek jumlah fan ('dual fan', "
                 "'triple fan', 'single fan', dan pola sejenis) dihapus "
                 "dulu sebelum dicek, sehingga 'VGA RTX 3060 Dual Fan' "
                 "lolos sementara 'Kipas VGA RTX 3060' dibuang. Khusus "
                 "laptop: judul yang diawali ram/ssd/hdd/memory/sodimm "
                 "dibuang (komponen salah kategori).")
    lines.append("")
    lines.append("| kategori | dibuang aksesori | setelah aksesori |")
    lines.append("|---|---|---|")
    for cat in CATEGORIES:
        c = ctx["counts"][cat]
        lines.append("| %s | %d | %d |" % (
            cat, c["accessory"], c["after_accessory"]))
    lines.append("")
    lines.append("### Contoh judul dibuang filter aksesori "
                 "(maks 15 per kategori)")
    lines.append("")
    for cat in CATEGORIES:
        lines.append("#### %s" % cat)
        for title, rule in ctx["accessory"][cat]["examples"]:
            lines.append("- [%s] %s" % (rule, title or "(judul kosong)"))
        lines.append("")
    lines.append("### Judul yang LOLOS tapi mengandung 'fan'/'kipas' "
                 "(total 10, beragam kategori, bukti pengecualian bekerja)")
    lines.append("")
    pool = []
    per_cat = {c: list(ctx["accessory"][c]["passed_fan"])
               for c in CATEGORIES}
    while len(pool) < 10 and any(per_cat.values()):
        for c in CATEGORIES:
            if per_cat[c]:
                pool.append((c, per_cat[c].pop(0)))
            if len(pool) >= 10:
                break
    for cat, title in pool:
        lines.append("- [%s] %s" % (cat, title or "(judul kosong)"))
    lines.append("")
    lines.append("## Inferensi kondisi (A3-3, tanpa drop)")
    lines.append("")
    lines.append("Hanya baris Tokopedia dengan condition kosong yang "
                 "diinferensi dari JUDUL: memuat second|2nd|bekas|seken|"
                 "used|preloved|copotan (case-insensitive) -> 'second', "
                 "selain itu 'new'. Disimpan sebagai kolom turunan "
                 "condition_inferred di dataframe training (bukan di "
                 "CSV). Facebook memakai label aslinya; kosong = "
                 "unknown. Inferensi diterapkan SEBELUM baseline "
                 "grup+kondisi dan fitur dummy. Di inferensi nanti, "
                 "kondisi 'any' memakai cond_new_mean dan "
                 "cond_second_mean dari defaults (bukan 0,0); Dart "
                 "memakai logika yang sama di fase integrasi.")
    lines.append("")
    lines.append("| kategori | Tokopedia kosong -> second | Tokopedia "
                 "kosong -> new | cond_new_mean | cond_second_mean |")
    lines.append("|---|---|---|---|---|")
    for cat in CATEGORIES:
        c = ctx["counts"][cat]
        d = results[cat].get("defaults", {})
        lines.append("| %s | %d | %d | %s | %s |" % (
            cat, c["infer_second"], c["infer_new"],
            fmt_num(d.get("cond_new_mean")),
            fmt_num(d.get("cond_second_mean"))))
    lines.append("")
    lines.append("## Kecocokan katalog (match rate)")
    lines.append("")
    lines.append("Denominator = baris kategori setelah dedupe + filter harga "
                 "+ filter placeholder + filter bundle + filter aksesori "
                 "(populasi masuk ekstraksi).")
    for cat in CATEGORIES:
        c = ctx["counts"][cat]
        den = c["after_accessory"] or 1
        r = results[cat]
        if cat in ("gpu", "cpu"):
            lines.append("- %s: konsensus cocok %d/%d (%.1f%%); "
                         "judul gagal cocok total %d."
                         % (cat, r["cons_matched"], c["after_accessory"],
                            100.0 * r["cons_matched"] / den,
                            len(r["unmatched"])))
        elif cat == "laptop":
            lines.append("- laptop: CPU PassMark cocok %d/%d (%.1f%%); "
                         "GPU (%s) cocok %d/%d (%.1f%%); "
                         "baris dengan sig dGPU %d."
                         % (r["laptop_cpu_matched"], c["after_accessory"],
                            100.0 * r["laptop_cpu_matched"] / den,
                            ctx["scales"]["laptop_gpu"],
                            r["laptop_gpu_matched"], c["after_accessory"],
                            100.0 * r["laptop_gpu_matched"] / den,
                            r["laptop_gpu_sig"]))
        else:
            lines.append("- %s: lolos ekstraksi %d/%d (%.1f%%)."
                         % (cat, c["stage_ok"], c["after_accessory"],
                            100.0 * c["stage_ok"] / den))
    lines.append("")
    lines.append("## Coverage CPU PassMark laptop: sebelum vs sesudah (A4)")
    lines.append("")
    lines.append("SEBELUM = run laporan draft lama (20:39, regex lama); "
                 "SESUDAH = run ini (regex baru). Denominator sama: "
                 "baris laptop setelah dedupe + filter harga + "
                 "placeholder + bundle + aksesori (populasi masuk "
                 "ekstraksi). Baris final = setelah ekstraksi + IQR.")
    lines.append("")
    lines.append("| | CPU cocok | coverage | baris final |")
    lines.append("|---|---|---|---|")
    lap = results["laptop"]
    den_lap = ctx["counts"]["laptop"]["after_accessory"] or 1
    lines.append("| SEBELUM | 1679/4545 | 36,9% | 840 |")
    lines.append("| SESUDAH | %d/%d | %.1f%% | %d |" % (
        lap["laptop_cpu_matched"],
        ctx["counts"]["laptop"]["after_accessory"],
        100.0 * lap["laptop_cpu_matched"] / den_lap, lap["n_rows"]))
    lines.append("")
    lines.append("Baris diselamatkan pola baru (di antara yang cocok "
                 "SESUDAH, dihitung saat ekstraksi):")
    lines.append("")
    new = lap.get("laptop_cpu_new", {})
    for tag in ("bare_ix", "core_no_i", "ultra_3", "apple"):
        lines.append("- %s: %d" % (tag, new.get(tag, 0)))
    lines.append("- total pola baru: %d" % sum(new.values()))
    lines.append("")
    lines.append("Catatan pola: bare iX = 'iX + nomor' tanpa kata Core; "
                 "Core tanpa i = 'Core 5/7/9 + nomor 3 digit'; ultra_3 = "
                 "'Ultra 5/7/9 + nomor 3 digit' (CPU_RE lama menuntut "
                 "4-5 digit); Apple = chip M1-M4 hanya bila konteks "
                 "apple/macbook ada dan kunci eksaknya ada di katalog "
                 "(kualifikasi pro/max hanya bila langsung mengikuti "
                 "chip; 'M2 2280' ukuran SSD dilewati). Proksi "
                 "famili+tier tidak menjangkau kunci 3 digit "
                 "Core/Ultra karena CPU_RE kunci juga menuntut 4-5 "
                 "digit — perilaku ini sama di Dart. Pola yang masih "
                 "di luar cakupan: Ryzen AI, seri N, bare iX tanpa "
                 "nomor model.")
    lines.append("")
    lines.append("## Sanity fitur skor (Fase A2)")
    lines.append("")
    lines.append("Populasi = baris setelah dedupe + filter harga + filter "
                 "placeholder + filter bundle + filter aksesori (sebelum "
                 "ekstraksi fitur). Median harga per model mencampur kondisi "
                 "(new/second/unknown) — sanity monotonisitas, bukan "
                 "evaluasi model. Lookup kedua skala memakai port yang "
                 "sama (probe + squash), jadi perbandingan adil; kunci "
                 "katalog yang cocok dicetak agar bisa dicek manual.")
    lines.append("")
    for col, label in (("gpu", "GPU (kategori gpu)"),
                       ("cpu", "CPU (kategori cpu)"),
                       ("laptop_gpu", "GPU laptop (kategori laptop)")):
        s = ctx["sanity"][col]
        lines.append("### %s — skala terpilih: %s (%s)"
                     % (label, s["chosen"], s["choice_reason"]))
        lines.append("")
        lines.append("| model | kunci konsensus | skor konsensus | "
                     "kunci passmark | skor passmark | n listing | "
                     "median harga |")
        lines.append("|---|---|---|---|---|---|---|")
        for m in sorted(s["models"], key=lambda k: -s["models"][k]["n"]):
            v = s["models"][m]
            lines.append("| %s | %s | %s | %s | %s | %d | %s |" % (
                m, v["cons_key"] or "-", fmt_num(v["cons_score"]),
                v["bench_key"] or "-", fmt_num(v["bench_score"]),
                v["n"], fmt_rp(v["median"])))
        lines.append("")
    lines.append("### Spearman(skor, median harga per model)")
    lines.append("")
    lines.append("| kolom | skala | n model cocok | coverage baris | "
                 "spearman (set sendiri) | spearman (interseksi) |")
    lines.append("|---|---|---|---|---|---|")
    for col in ("gpu", "cpu", "laptop_gpu"):
        s = ctx["sanity"][col]
        lines.append("| %s | konsensus | %d | %.1f%% | %s | %s |" % (
            col, s["n_models_cons"], 100.0 * s["cov_cons"],
            fmt_num(s["sp_cons"]), fmt_num(s["sp_inter_cons"])))
        lines.append("| %s | passmark | %d | %.1f%% | %s | %s |" % (
            col, s["n_models_bench"], 100.0 * s["cov_bench"],
            fmt_num(s["sp_bench"]), fmt_num(s["sp_inter_bench"])))
    lines.append("")
    lines.append("### 10 GPU populer (cek manual urutan skor)")
    lines.append("")
    lines.append("| model | skor konsensus | skor passmark (G3D) | "
                 "n listing | median harga |")
    lines.append("|---|---|---|---|---|")
    for p in ctx["sanity"]["popular_gpu"]:
        lines.append("| %s | %s | %s | %d | %s |" % (
            p["model"], fmt_num(p["cons_score"]),
            fmt_num(p["bench_score"]), p["n"], fmt_rp(p["median"])))
    lines.append("")
    lines.append("### Keputusan skala per kolom (diimplementasikan di skrip)")
    lines.append("")
    for col in ("gpu", "cpu", "laptop_gpu"):
        s = ctx["sanity"][col]
        lines.append("- %s: pakai %s (alasan: %s). Coverage konsensus "
                     "%.1f%% vs passmark %.1f%%; Spearman interseksi "
                     "konsensus %s vs passmark %s."
                     % (col, s["chosen"], s["choice_reason"],
                        100.0 * s["cov_cons"], 100.0 * s["cov_bench"],
                        fmt_num(s["sp_inter_cons"]),
                        fmt_num(s["sp_inter_bench"])))
    lines.append("- Konsekuensi Dart (fase integrasi): kolom yang "
                 "pilihannya passmark HARUS membaca benchmark_scores.json "
                 "(G3D untuk GPU, CPU Mark untuk CPU) dengan nama fitur "
                 "ln_passmark / ln_gpu_passmark; kolom yang pilihannya "
                 "konsensus tetap membaca consensus_scores.json dengan "
                 "nama fitur ln_consensus / ln_gpu_consensus. CPU laptop "
                 "tetap PassMark (keputusan Fase A, tidak diubah di sini).")
    lines.append("")
    lines.append("## Storage: distribusi tipe + investigasi type_hdd")
    lines.append("")
    lines.append("Urutan keputusan klasifikasi (Fase A2): (1) token nvme/"
                 "pcie yang tidak dinegasikan -> nvme (negasi = bukan/non/"
                 "no/tanpa yang langsung mendahului atau terhubung tanda "
                 "hubung; negasi yang sama berlaku untuk sata, dianggap "
                 "tidak ada); (2) token sata eksplisit -> sata_ssd WALAU "
                 "ada m.2; (3) ada m.2 tapi tidak ada nvme/pcie/sata -> "
                 "DIBUANG (m2_tanpa_tipe), token ssd saja tidak "
                 "menyelamatkan — pilihan ini eksplisit supaya Dan bisa "
                 "membatalkannya dalam satu kalimat; (4) token ssd tanpa "
                 "m.2 -> sata_ssd; (5) token hdd/harddisk/hardisk -> hdd; "
                 "(6) sisanya -> buang.")
    lines.append("")
    lines.append("Distribusi tipe baris storage FINAL: %s."
                 % (results["storage"].get("storage_type_dist", {})))
    lines.append("")
    lines.append("Corong baris storage yang mengandung token hdd/harddisk/"
                 "hardisk (judul ATAU spec): mentah %d, setelah dedupe %d, "
                 "setelah harga %d, setelah bundle %d, setelah aksesori "
                 "%d, final (lolos ekstraksi + IQR) %d."
                 % (ctx["storage_hdd"]["raw"], ctx["storage_hdd"]["deduped"],
                    ctx["storage_hdd"]["priced"],
                    ctx["storage_hdd"]["after_bundle"],
                    ctx["storage_hdd"]["after_accessory"],
                    results["storage"].get("storage_hdd_token_final", 0)))
    lines.append("")
    lines.append(ctx["storage_hdd"]["note"])
    lines.append("")
    lines.append("## Kebocoran ekstraksi (sampel acak, seed 42)")
    lines.append("")
    lines.append("Perluasan regex dari sampel bocor TIDAK diterapkan pada "
                 "run ini. Alasannya ada di analisis pola di bawah: pola "
                 "sistematis yang ditemukan adalah keterbatasan yang SAMA "
                 "di sisi Dart "
                 "(regex Dart _cpuRe/_modelTokens juga tidak menangani "
                 "pola itu), sehingga memperluas hanya di Python akan "
                 "merusak paritas latih/inferensi. Pola-pola itu dicatat "
                 "sebagai kandidat perbaikan BERSAMA Python+Dart di "
                 "Fase C, bukan di sini.")
    lines.append("")
    for cat, reason in (("gpu", "model_tidak_ditemukan"),
                        ("laptop", "cpu_passmark_tidak_cocok")):
        titles = results[cat].get("drop_titles", {}).get(reason, [])
        sample = random.Random(42).sample(
            titles, 20) if len(titles) >= 20 else list(titles)
        lines.append("### %s — alasan %s (%d judul total)"
                     % (cat, reason, len(titles)))
        for t in sample:
            lines.append("- %s" % (t or "(judul kosong)"))
        lines.append("")
    lines.append("### Pola di dalam judul bocor (hitung prioritas, "
                 "satu judul satu pola)")
    lines.append("")
    lines.append("GPU model_tidak_ditemukan: %s."
                 % ctx["leak_patterns"]["gpu"])
    lines.append("")
    lines.append("Laptop cpu_passmark_tidak_cocok: %s."
                 % ctx["leak_patterns"]["laptop"])
    lines.append("")
    lines.append("## Judul GPU/CPU yang gagal cocok (maks 15 per kategori)")
    lines.append("")
    for cat in ("gpu", "cpu"):
        lines.append("### %s (%d judul gagal total)"
                     % (cat, len(results[cat]["unmatched"])))
        for t in results[cat]["unmatched"][:15]:
            lines.append("- %s" % (t or "(judul kosong)"))
        lines.append("")
    lines.append("## Penyimpangan dari brief / keputusan yang dikunci")
    lines.append("")
    lines.append("- Pencocokan konsensus dari token model berspasi dulu, "
                 "bukan judul mentah (judul mentah terbukti gagal karena "
                 "prefix vendor di kunci katalog).")
    lines.append("- CPU laptop konsisten skala PassMark (cpu_mobile, lalu "
                 "cpu desktop, lalu proksi famili+tier resolveCpuLaptop); "
                 "GPU laptop tetap konsensus; tiap kolom satu skala.")
    lines.append("- Baris laptop dengan sig dGPU ditemukan tapi konsensus "
                 "gagal dibuang (ln_gpu tidak terdefinisi). Baris laptop "
                 "tanpa sig dGPU dianggap has_dgpu=0, ln_gpu=0.0.")
    lines.append("- Grup dari fitur final (setelah imputasi); RAM 2x8GB "
                 "masuk grup 16GB; storage 1TB masuk grup 1000GB.")
    lines.append("- IQR memakai persentil linear numpy, bukan metode indeks "
                 "engine Dart (sisi latih, bukan port engine).")
    lines.append("- Storage kategori memakai parse GB/TB umum; storage "
                 "laptop memakai port _extractStorageFromText (daftar "
                 "ukuran tetap) agar selaras dengan helper inferensi.")
    lines.append("- VRAM diimputasi median per model; speed RAM diimputasi "
                 "median per DDR (fallback median global). defaults di "
                 "JSON berisi median kategori (vram) dan median global + "
                 "per-DDR (speed).")
    lines.append("- sigma_log = std residual out-of-fold evaluasi (a), "
                 "bukan residual training.")
    lines.append("- Storage tanpa kata tipe dibuang dan dihitung; prioritas "
                 "tipe nvme > sata_ssd > hdd; is_sodimm hanya dari token "
                 "sodimm/so-dimm; motherboard tanpa usaha ekstra "
                 "(chipset + kondisi saja), gerbang yang memutuskan.")
    lines.append("- Filter bundle/rakitan Dan diterapkan setelah filter "
                 "harga, sebelum ekstraksi dan IQR (penanda frasa + kombo "
                 "judul GPU+CPU+RAM, kecuali laptop untuk kombo).")
    lines.append("- vram_gb mentah (bukan ln); kapasitas ram/storage/laptop "
                 "pakai ln; speed_mhz mentah; ddr_gen numerik.")
    lines.append("- Fase A2: skala skor per kolom dipilih dari sanity "
                 "(aturan di atas) dan diimplementasikan di skrip; nama "
                 "fitur ln mengikuti skala (ln_consensus vs ln_passmark).")
    lines.append("- Fase A2: klasifikasi storage memakai urutan "
                 "nvme/pcie (negasi-aware) > sata eksplisit > m.2 saja "
                 "dibuang > ssd > hdd > buang; 'm.2' tanpa tipe tidak "
                 "ditebak.")
    lines.append("- Fase A2: filter bundle menggantikan Fase A — penanda "
                 "hanya di judul dengan word boundary (tanpa fullset/"
                 "full set) + deteksi pasangan dua komponen berbeda; "
                 "laptop dikecualikan dari pasangan.")
    lines.append("- Fase A2: pemisah evaluasi (a) memakai group_n tanpa "
                 "kondisi/fallback; baseline (a) tidak berubah.")
    lines.append("- Fase A2: gerbang Tier 2 = >= 100 baris DAN MAE (b) "
                 "model <= 0,9 x MAE median kategori (b); gerbang 150 "
                 "hanya untuk Tier 1.")
    lines.append("- Fase A2: tidak ada perluasan regex dari sampel bocor; "
                 "pola sistematis (bare iX, Core tanpa i, seri N, sufiks "
                 "XTX) adalah keterbatasan bersama Dart, kandidat "
                 "perbaikan bersama di Fase C.")
    lines.append("- Fase A2: fixture parity ditulis ke path draft "
                 "(ml_parity_draft.json), bukan test/fixtures; fixture "
                 "draft memuat 3 kasus tipe storage khusus.")
    lines.append("- A3: urutan pipeline final = dedupe hash -> dedupe "
                 "(seller, raw_title) -> dedupe (seller, judul "
                 "ternormalisasi) -> filter harga -> filter placeholder "
                 "-> filter bundle A2 -> filter aksesori -> inferensi "
                 "kondisi (tanpa drop) -> drop ekstraksi -> IQR -> "
                 "latih varian -> evaluasi + gerbang A2-6.")
    lines.append("- A3-1: harga placeholder dibuang setelah filter "
                 "rentang (persis 123456789/987654321/123123, digit "
                 "berulang 5+, awalan 12345).")
    lines.append("- A3-2: filter aksesori dari judul saja (daftar di "
                 "atas); spek jumlah fan dikecualikan; laptop diawali "
                 "ram/ssd/hdd/memory/sodimm dibuang.")
    lines.append("- A3-3: inferensi kondisi hanya Tokopedia kosong dari "
                 "judul; defaults memuat cond_new_mean, "
                 "cond_second_mean, src_tokopedia_mean; kondisi 'any' "
                 "di inferensi memakai kedua cond mean (fungsi "
                 "resolve_condition_dummies/predict_price di skrip).")
    lines.append("- A3-4: dua varian src per kategori; varian dengan-src "
                 "dievaluasi dengan mean-fill train fold; pilihan "
                 "per kategori utama MAE (a), (b) konfirmasi; gerbang "
                 "dari varian terpilih; skema JSON bertambah "
                 "src_variant, src_variant_reason, dan MAE kedua "
                 "varian.")
    lines.append("- Perbaikan kapasitas desimal: '2.0TB' kini dibaca "
                 "2000 (dulu salah dibaca 0TB dan membuat log(0) crash "
                 "kategori storage); guard cap/total/ram/storage <= 0 "
                 "kini dibuang sebagai tidak ditemukan, bukan crash. "
                 "Perubahan ini harus di-port bersama ke Dart di "
                 "Fase C agar paritas latih/inferensi terjaga.")
    lines.append("- A4: gerbang Tier 1 = >= 150 baris DAN MAE (a) model "
                 "<= 0,95 x baseline; Tier 2 tetap 0,9 x median (b). "
                 "Alasan gerbang baru: "
                 "mae_model_a_le_95persen_baseline_a / "
                 "mae_model_a_tidak_lebih_baik_5persen.")
    lines.append("- A4: ekstraksi CPU laptop diperluas (bare iX, Core "
                 "tanpa i, Ultra 3 digit, Apple kunci eksak); sisi Dart "
                 "disiapkan sebagai file draft "
                 "tools/ml/draft/dart_laptop_cpu_parse_draft.dart, "
                 "BELUM diterapkan ke lib/ (diterapkan di Fase C).")
    lines.append("- A4: laporan dan JSON baru berekstensi A3 "
                 "(ml_report_draft_A3.md, price_models_draft_A3.json, "
                 "ml_parity_draft_A3.json); fixture parity baru = kasus "
                 "kategori lama + kasus CPU laptop baru; file lama "
                 "tidak ditimpa.")
    lines.append("")
    lines.append("## Keterbatasan")
    lines.append("")
    lines.append("(a) Label harga = harga pasang marketplace: model "
                 "dilatih dari harga yang dipasang penjual di Facebook "
                 "Marketplace dan Tokopedia, bukan harga transaksi "
                 "yang terbukti laku.")
    lines.append("(b) Kondisi Tokopedia diinferensi dari judul: baris "
                 "Tokopedia dengan condition kosong dilabeli second "
                 "bila judul memuat second|2nd|bekas|seken|used|"
                 "preloved|copotan, selain itu new; inferensi ini bisa "
                 "salah bila judul tidak menyebut kondisi.")
    _lap = results["laptop"]
    _den_lap = ctx["counts"]["laptop"]["after_accessory"] or 1
    _cov_lap = 100.0 * _lap["laptop_cpu_matched"] / _den_lap
    lines.append("(c) Coverage ekstraksi laptop: CPU PassMark cocok "
                 + "%.1f%% (%d/%d baris masuk ekstraksi)" % (
                     _cov_lap, _lap["laptop_cpu_matched"],
                     ctx["counts"]["laptop"]["after_accessory"])
                 + " dan hanya %d dari %d baris laptop yang terpakai "
                 "sebagai training; sebagian besar listing laptop "
                 "tidak bisa diparse CPU-nya, sehingga model laptop "
                 "hanya mewakili subset yang ter-parse."
                 % (_lap["n_rows"], ctx["counts"]["laptop"]["raw"]))
    lines.append("(d) Model hanya dipakai saat pembanding exact-match "
                 "< 5 (Tier 2); Tier 1 sengaja nonaktif karena median "
                 "produk lebih kuat bila pembanding banyak.")
    _mape_txt = ", ".join(
        "%s %.1f%%" % (cat, 100.0 * results[cat]["mape_model"])
        for cat in CATEGORIES)
    _in_range = [cat for cat in CATEGORIES
                 if 40.0 <= 100.0 * results[cat]["mape_model"] <= 50.0]
    _above = [cat for cat in CATEGORIES
              if 100.0 * results[cat]["mape_model"] > 50.0]
    _below = [cat for cat in CATEGORIES
              if 100.0 * results[cat]["mape_model"] < 40.0]
    lines.append("(e) MAPE model per kategori dari tabel final: "
                 + _mape_txt + ". Rentang 'sekitar 40-50%' tepat untuk "
                 + (", ".join(_in_range) if _in_range
                    else "tidak ada kategori")
                 + "; di atas rentang: "
                 + (", ".join(_above) if _above else "-")
                 + "; di bawah rentang: "
                 + (", ".join(_below) if _below else "-")
                 + ". Jadi kesalahan relatif masih besar terutama "
                 "untuk kategori di atas rentang.")
    lines.append("(f) Model beku di APK: price_models.json adalah "
                 "asset beku yang ikut di APK, sehingga harus dilatih "
                 "ulang tiap panen data baru; median pembanding di "
                 "app bersifat live, model tidak.")
    return "\n".join(lines) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(description="Latih model harga wajar.")
    ap.add_argument("--input", default=None)
    ap.add_argument("--out", default=None)
    ap.add_argument("--report", default=None)
    ap.add_argument("--dump-parity", action="store_true")
    ap.add_argument("--parity-out", default=None)
    args = ap.parse_args(argv)
    in_path = Path(args.input) if args.input else \
        REPO / "tools/listings_import/listings_clean.csv"
    out_path = Path(args.out) if args.out else \
        REPO / "assets/data/price_models.json"
    report_path = Path(args.report) if args.report else \
        REPO / "docs/ml_report.md"
    with open(REPO / "assets/data/consensus_scores.json",
              encoding="utf-8") as f:
        cons = json.load(f)
    with open(REPO / "assets/data/benchmark_scores.json",
              encoding="utf-8") as f:
        bench = json.load(f)
    cons_gpu = cons.get("gpu", {})
    cons_cpu = cons.get("cpu", {})
    bench_cpu = bench.get("cpu", {})
    bench_mobile = bench.get("cpu_mobile", {})
    bench_gpu = bench.get("gpu", {})
    df = pd.read_csv(in_path, dtype=str, keep_default_na=False)
    csv_rows = len(df)
    df["_price_num"] = pd.to_numeric(df["raw_price"], errors="coerce")
    counts = {}
    ignored_rows = 0
    for cat in CATEGORIES:
        counts[cat] = {"raw": 0, "deduped": 0, "deduped_norm": 0,
                       "deduped_norm_drop": 0, "priced": 0,
                       "placeholder_exact": 0, "placeholder_repeated": 0,
                       "placeholder_prefix12345": 0, "placeholder_total": 0,
                       "after_placeholder": 0, "stage_ok": 0,
                       "after_bundle": 0, "bundle_marker": 0,
                       "bundle_pair": 0, "accessory": 0,
                       "after_accessory": 0, "infer_second": 0,
                       "infer_new": 0}
    counts_raw_all = Counter(df["category"])
    for cat in CATEGORIES:
        counts[cat]["raw"] = int(counts_raw_all.get(cat, 0))
    ignored_rows = int(sum(v for k, v in counts_raw_all.items()
                           if k not in CATEGORIES))

    def storage_hdd_count(d):
        sub = d[d["category"] == "storage"]
        mask = sub["raw_title"].str.contains(
            r"hdd|harddisk|hardisk", case=False, na=False) | \
            sub["raw_spec_text"].str.contains(
                r"hdd|harddisk|hardisk", case=False, na=False)
        return int(mask.sum())

    # URUTAN PIPELINE FINAL (A3): dedupe hash -> dedupe (seller,
    # raw_title) -> dedupe (seller, judul ternormalisasi) -> filter
    # harga -> filter placeholder -> filter bundle A2 -> filter
    # aksesori -> inferensi kondisi (tanpa drop) -> drop ekstraksi
    # -> IQR -> latih varian -> evaluasi + gerbang.
    storage_hdd = {"raw": storage_hdd_count(df)}
    df = df.drop_duplicates(subset=["listing_hash"], keep="first")
    df = df.drop_duplicates(subset=["seller", "raw_title"], keep="first")
    for cat in CATEGORIES:
        counts[cat]["deduped"] = int((df["category"] == cat).sum())
    storage_hdd["deduped"] = storage_hdd_count(df)
    df, norm_dropped = dedupe_normalized(df)
    for cat in CATEGORIES:
        counts[cat]["deduped_norm"] = int((df["category"] == cat).sum())
        counts[cat]["deduped_norm_drop"] = norm_dropped.get(cat, 0)
    df = df[df["_price_num"].notna()
            & (df["_price_num"] >= PRICE_MIN)
            & (df["_price_num"] <= PRICE_MAX)]
    for cat in CATEGORIES:
        counts[cat]["priced"] = int((df["category"] == cat).sum())
    storage_hdd["priced"] = storage_hdd_count(df)
    df, placeholder_stats = placeholder_filter(df)
    for cat in CATEGORIES:
        counts[cat]["after_placeholder"] = int(
            (df["category"] == cat).sum())
        st = placeholder_stats.get(cat, {})
        counts[cat]["placeholder_exact"] = st.get("exact", 0)
        counts[cat]["placeholder_repeated"] = st.get("repeated", 0)
        counts[cat]["placeholder_prefix12345"] = st.get("prefix12345", 0)
        counts[cat]["placeholder_total"] = st.get("total", 0)
    df, bundle_stats = bundle_filter(df)
    for cat in CATEGORIES:
        counts[cat]["after_bundle"] = int((df["category"] == cat).sum())
        counts[cat]["bundle_marker"] = bundle_stats.get(cat, {}).get("marker", 0)
        counts[cat]["bundle_pair"] = bundle_stats.get(cat, {}).get("pair", 0)
    storage_hdd["after_bundle"] = storage_hdd_count(df)
    df, accessory_stats = accessory_filter(df)
    for cat in CATEGORIES:
        counts[cat]["after_accessory"] = int((df["category"] == cat).sum())
        counts[cat]["accessory"] = accessory_stats.get(cat, {}).get(
            "count", 0)
    storage_hdd["after_accessory"] = storage_hdd_count(df)
    # --- Sanity skor + pilih SATU skala per kolom (Fase A2) ---
    # Populasi sanity = setelah seluruh filter A3 (sebelum ekstraksi).
    sanity = score_sanity(df, cons_gpu, cons_cpu, bench_gpu, bench_cpu)
    scales = {}
    feat_names = {}
    for col, cons_cat, bench_cat, feat_cons, feat_bench in (
            ("gpu", cons_gpu, bench_gpu, "ln_consensus", "ln_passmark"),
            ("cpu", cons_cpu, bench_cpu, "ln_consensus", "ln_passmark"),
            ("laptop_gpu", cons_gpu, bench_gpu,
             "ln_gpu_consensus", "ln_gpu_passmark")):
        chosen = sanity[col]["chosen"]
        if chosen == "consensus":
            scales[col] = (cons_cat, "consensus_score")
            feat_names[col] = feat_cons
        else:
            scales[col] = (bench_cat, "score")
            feat_names[col] = feat_bench
        print("skala %s: %s (%s)" % (col, chosen,
                                     sanity[col]["choice_reason"]))
    trained_at = datetime.now(timezone(timedelta(hours=7))).isoformat(timespec="seconds")
    categories = {}
    results = {}
    parity = {}
    for cat in CATEGORIES:
        sub = df[df["category"] == cat]
        rows = []
        for t, s, p, c, src in zip(sub["raw_title"],
                                   sub["raw_spec_text"],
                                   sub["_price_num"],
                                   sub["condition"],
                                   sub["source"]):
            eff, inferred = infer_condition(src, c, str(t))
            if inferred:
                if eff == "second":
                    counts[cat]["infer_second"] += 1
                else:
                    counts[cat]["infer_new"] += 1
            rows.append({"title": str(t), "spec": str(s),
                         "price": int(float(p)),
                         "condition": eff, "source": str(src),
                         "condition_inferred": inferred})
        try:
            proc = process_category(cat, rows, cons_gpu, cons_cpu,
                                    bench_cpu, bench_mobile,
                                    scales=scales, feat_names=feat_names)
        except Exception as exc:  # noqa: BLE001 - satu kategori gagal,
            # kategori lain tetap jalan; kegagalan tertulis di laporan.
            print("PERINGATAN: kategori %s gagal diproses: %s" % (cat, exc),
                  file=sys.stderr)
            categories[cat] = {
                "enabled": False, "enabled_fallback": False,
                "reason": "error: %s" % exc, "reason_fallback": "error",
                "intercept": 0.0, "features": [], "defaults": {},
                "sigma_log": None, "n_rows": 0,
                "mae_model": None, "mae_baseline": None,
                "mape_model": None, "mape_baseline": None,
                "mae_model_group": None, "mae_category_median_group": None,
                "mae_model_a_group_lt5": None,
                "mae_baseline_a_group_lt5": None,
                "mae_model_a_group_ge5": None,
                "mae_baseline_a_group_ge5": None,
                "n_group_lt5": 0, "n_group_ge5": 0,
                "src_variant": "none", "src_variant_reason": "error",
                "mae_model_a_nosrc": None, "mae_model_b_nosrc": None,
                "mae_model_a_withsrc": None, "mae_model_b_withsrc": None,
            }
            results[cat] = dict(categories[cat], drops={},
                                drop_titles={},
                                unmatched=[], cons_matched=0,
                                laptop_cpu_matched=0, laptop_cpu_new={},
                                laptop_gpu_matched=0,
                                laptop_gpu_sig=0, storage_type_dist={},
                                storage_hdd_token_final=0)
            parity[cat] = []
            continue
        counts[cat]["stage_ok"] = proc["stage_ok"]
        n = proc["n_final"]
        # --- Eksperimen source A3-4: dua varian per kategori ---
        # Varian with-src dievaluasi dengan kolom src baris test diisi
        # rata-rata src train fold (anti-leakage).
        if n >= 1:
            ea_n = eval_a(proc["X"], proc["y"], proc["prices"],
                          proc["groups"], proc["conds"])
            eb_n = eval_b(proc["X"], proc["y"], proc["prices"],
                          proc["groups"])
            ea_w = eval_a(proc["X_with_src"], proc["y"], proc["prices"],
                          proc["groups"], proc["conds"],
                          src_col=proc["src_col"])
            eb_w = eval_b(proc["X_with_src"], proc["y"], proc["prices"],
                          proc["groups"], src_col=proc["src_col"])
            _, _, diff_n = fit_final_raw(proc["X"], proc["y"])
            _, _, diff_w = fit_final_raw(proc["X_with_src"], proc["y"])
            print("self-check %s: tanpa-src %.3g, dengan-src %.3g"
                  % (cat, diff_n, diff_w))
        else:
            ea_n = eb_n = ea_w = eb_w = None
        # A5: model final TANPA src_tokopedia untuk semua kategori.
        # Varian with_src tetap dievaluasi di atas HANYA untuk tabel
        # perbandingan di laporan; tidak dipakai gerbang atau JSON.
        ea, eb = ea_n, eb_n
        X_chosen = proc["X"]
        cols_chosen = proc["feature_cols"]
        src_variant = "without_src"
        src_reason = ("A5: model final tanpa-src; with_src hanya "
                      "perbandingan")
        if n >= 1:
            intercept, coef_raw, max_diff = fit_final_raw(X_chosen,
                                                          proc["y"])
            print("self-check %s (varian terpilih %s): selisih maks %.3g"
                  % (cat, src_variant, max_diff))
        else:
            intercept, coef_raw = 0.0, np.zeros(len(cols_chosen))
        # Gerbang Tier 1 A5: DINONAKTIFKAN untuk semua kategori.
        # Alasan per kategori ditulis di laporan dari angka segmen
        # group_n >= 5 evaluasi (a) run ini, bukan dari gerbang lama.
        enabled, reason = False, "tier1_dinonaktifkan_a5"
        # Gerbang Tier 2 A5 (KETIGA syarat harus terpenuhi):
        # (i) >= 100 baris bersih; (ii) MAE (b) model <= 0,9 x median
        # kategori (b); (iii) BILA segmen group_n < 5 evaluasi (a)
        # punya n >= 20, MAE model segmen itu <= MAE baseline segmen
        # itu. Segmen n < 20 tidak menggugurkan (syarat iii dilewati).
        if n < MIN_ROWS_TIER2:
            fallback, reason_fb = False, "data kurang tier2 (<100)"
        elif eb is None:
            fallback, reason_fb = False, "evaluasi grup tidak tersedia"
        elif eb["mae_model_group"] > TIER2_RATIO * eb["mae_category_median_group"]:
            fallback, reason_fb = False, \
                "mae_model_b_tidak_lebih_baik_10persen"
        elif ea is not None and ea["n_group_lt5"] >= 20 \
                and ea["mae_model_a_group_lt5"] is not None \
                and ea["mae_baseline_a_group_lt5"] is not None \
                and ea["mae_model_a_group_lt5"] > ea["mae_baseline_a_group_lt5"]:
            fallback, reason_fb = False, \
                "tier2_gagal_syarat_iii_segmen_lt5"
        else:
            fallback, reason_fb = True, "tier2_lolos_a5"
        entry = {
            "enabled": enabled, "enabled_fallback": fallback,
            "reason": reason, "reason_fallback": reason_fb,
            "intercept": float(intercept),
            "features": [{"name": name, "coef": float(coef)}
                         for name, coef in zip(cols_chosen, coef_raw)],
            "defaults": proc["defaults"],
            "sigma_log": ea["sigma_log"] if ea else None,
            "n_rows": int(n),
            "mae_model": ea["mae_model"] if ea else None,
            "mae_baseline": ea["mae_baseline"] if ea else None,
            "mape_model": ea["mape_model"] if ea else None,
            "mape_baseline": ea["mape_baseline"] if ea else None,
            "mae_model_group": eb["mae_model_group"] if eb else None,
            "mae_category_median_group":
                eb["mae_category_median_group"] if eb else None,
            "mae_model_a_group_lt5":
                ea["mae_model_a_group_lt5"] if ea else None,
            "mae_baseline_a_group_lt5":
                ea["mae_baseline_a_group_lt5"] if ea else None,
            "mae_model_a_group_ge5":
                ea["mae_model_a_group_ge5"] if ea else None,
            "mae_baseline_a_group_ge5":
                ea["mae_baseline_a_group_ge5"] if ea else None,
            "n_group_lt5": ea["n_group_lt5"] if ea else 0,
            "n_group_ge5": ea["n_group_ge5"] if ea else 0,
            "src_variant": src_variant,
            "src_variant_reason": src_reason,
            "mae_model_a_nosrc": ea_n["mae_model"] if ea_n else None,
            "mae_model_b_nosrc": eb_n["mae_model_group"] if eb_n else None,
            "mae_model_a_withsrc": ea_w["mae_model"] if ea_w else None,
            "mae_model_b_withsrc": eb_w["mae_model_group"] if eb_w else None,
        }
        if set(entry.keys()) != CAT_KEYS:
            raise SystemExit("SKEMA GAGAL untuk %s: kunci %s"
                             % (cat, sorted(set(entry.keys()) ^ CAT_KEYS)))
        categories[cat] = entry
        results[cat] = dict(entry, drops=proc["drops"],
                            drop_titles=proc["drop_titles"],
                            unmatched=proc["unmatched"],
                            cons_matched=proc["cons_matched"],
                            laptop_cpu_matched=proc["laptop_cpu_matched"],
                            laptop_cpu_new=proc["laptop_cpu_new"],
                            laptop_gpu_matched=proc["laptop_gpu_matched"],
                            laptop_gpu_sig=proc["laptop_gpu_sig"],
                            storage_type_dist=proc["storage_type_dist"],
                            storage_hdd_token_final=proc["storage_hdd_token_final"])
        parity[cat] = [{"category": cat, **ex} for ex in proc["parity"]]
    payload = {
        "version": "1",
        "trained_at": trained_at,
        "source": {"csv_rows": int(csv_rows),
                   "consensus_generated_at": cons.get("generated_at"),
                   "benchmark_generated_at": bench.get("generated_at")},
        "categories": categories,
        "score_scales": {
            col: {"chosen": sanity[col]["chosen"],
                  "choice_reason": sanity[col]["choice_reason"],
                  "cov_cons": sanity[col]["cov_cons"],
                  "cov_bench": sanity[col]["cov_bench"],
                  "sp_inter_cons": sanity[col]["sp_inter_cons"],
                  "sp_inter_bench": sanity[col]["sp_inter_bench"]}
            for col in ("gpu", "cpu", "laptop_gpu")},
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, ensure_ascii=False)
    # --- Investigasi type_hdd: baris storage "hdd murni" setelah bundle ---
    sub_st = df[df["category"] == "storage"]
    pure_hdd = 0
    for _, r in sub_st.iterrows():
        txt = (str(r["raw_title"]) + " " + str(r["raw_spec_text"])).lower()
        clean = NEG_PHRASE_RE.sub(" ", txt)
        if re.search(r"\bhdd\b|\bharddisk\b|\bhardisk\b", clean) \
                and not re.search(r"\bnvme\b|\bpcie\b|\bsata\b|\bssd\b"
                                 r"|\bm\.?2\b", clean):
            pure_hdd += 1
    storage_hdd["pure_after_bundle"] = pure_hdd
    storage_hdd["final_dist"] = dict(
        results["storage"].get("storage_type_dist", {}))
    storage_hdd["note"] = (
        "Investigasi type_hdd: baris storage 'hdd murni' (hanya token "
        "hdd/harddisk/hardisk, tanpa nvme/pcie/sata/ssd/m.2) setelah "
        "bundle = %d; distribusi tipe final = %s. Dua mekanisme yang "
        "mengecilkan hdd: (1) prioritas token — judul keyword-stuffed "
        "yang menyebut ssd/nvme/sata sekaligus hdd diklasifikasikan ke "
        "tipe prioritas lebih tinggi, bukan hdd; (2) aturan m.2 Fase A2 "
        "— judul 'M.2 HDD' tanpa nvme/sata kini dibuang, bukan ditebak. "
        "Pada Fase A (data lama) type_hdd kosong karena baris HDD "
        "bersih memang hampir tidak ada setelah kedua mekanisme itu; "
        "pada data baru ini, angka final di atas yang berlaku."
        % (pure_hdd, storage_hdd["final_dist"]))
    leak_patterns = {
        "gpu": _fmt_counts(_count_patterns(
            results["gpu"].get("drop_titles", {}).get(
                "model_tidak_ditemukan", []),
            [("sufiks_xtx", re.compile(r"rx\s*\d{4}\s*xtx")),
             ("ponsel/tablet/dll",
              re.compile(r"samsung|galaxy|iphone|ipad|tablet|handphone"
                         r"|oppo|vivo|xiaomi|redmi|drone|watch|charger"
                         r"|gshock|powerbank|kamera|camera")),
             ("mini_pc", re.compile(r"mini pc|mini-pc|prodesk"
                                    r"|thinkcentre|optiplex"))])),
        "laptop": _fmt_counts(_count_patterns(
            results["laptop"].get("drop_titles", {}).get(
                "cpu_passmark_tidak_cocok", []),
            [("apple_m1_m2",
              re.compile(r"macbook|\bm[1234]\b")),
             ("bare_i9_tanpa_core",
              re.compile(r"\bi9[\s\-]*\d{4,5}")),
             ("bare_ix_tanpa_core",
              re.compile(r"\bi[3579][\s\-]*\d{4,5}")),
             ("ryzen_ai",
              re.compile(r"ryzen\s*ai")),
             ("core_tanpa_i",
              re.compile(r"\bcore\s+[579]\s+\d")),
             ("seri_n",
              re.compile(r"i[3579][\s\-]*n\d{3}")),
             ("tanpa_angka_model",
              re.compile(r"^[^0-9]*$"))])),
    }
    csv_md5 = hashlib.md5(in_path.read_bytes()).hexdigest()
    ctx = {"input": str(in_path), "csv_rows": int(csv_rows),
           "csv_md5": csv_md5,
           "cons_gen": cons.get("generated_at"),
           "bench_gen": bench.get("generated_at"),
           "counts": counts, "ignored_rows": ignored_rows,
           "bundle": {cat: {
               "examples_marker": bundle_stats.get(cat, {}).get(
                   "examples_marker", []),
               "examples_pair": bundle_stats.get(cat, {}).get(
                   "examples_pair", []),
               "passed_special": bundle_stats.get(cat, {}).get(
                   "passed_special", []),
               "pair_diff": {
                   "new_drop": bundle_stats.get(cat, {}).get(
                       "pair_diff_new_drop", 0),
                   "new_pass": bundle_stats.get(cat, {}).get(
                       "pair_diff_new_pass", 0),
                   "examples_new_drop": bundle_stats.get(cat, {}).get(
                       "examples_new_drop", []),
                   "examples_new_pass": bundle_stats.get(cat, {}).get(
                       "examples_new_pass", [])}}
               for cat in CATEGORIES},
           "accessory": {cat: {
               "examples": accessory_stats.get(cat, {}).get(
                   "examples", []),
               "passed_fan": accessory_stats.get(cat, {}).get(
                   "passed_fan", [])}
               for cat in CATEGORIES},
           "sanity": sanity,
           "scales": {col: sanity[col]["chosen"]
                      for col in ("gpu", "cpu", "laptop_gpu")},
           "storage_hdd": storage_hdd,
           "leak_patterns": leak_patterns}
    report_path.parent.mkdir(parents=True, exist_ok=True)
    with open(report_path, "w", encoding="utf-8") as f:
        f.write(build_report(ctx, results, trained_at))
    if args.dump_parity:
        parity_path = Path(args.parity_out) if args.parity_out \
            else REPO / "test/fixtures/ml_parity.json"
        storage_cases = [
            {"text": "SSD M.2 SATA 512GB", "expected": "sata_ssd"},
            {"text": "SSD M.2 512GB bukan NVME",
             "expected": "DROP:m2_tanpa_tipe"},
            {"text": "SSD M.2 512GB", "expected": "DROP:m2_tanpa_tipe"},
        ]
        for case in storage_cases:
            cap, st = extract_storage_cat(case["text"])
            _, reason = classify_storage_type(case["text"])
            actual = st if st else "DROP:" + reason
            case["actual"] = actual
            case["capacity_gb"] = cap
            if actual != case["expected"]:
                raise SystemExit(
                    "PARITY STORAGE GAGAL: %s -> %s (harap %s)"
                    % (case["text"], actual, case["expected"]))
        parity["storage_type_cases"] = storage_cases
        cond_cases = [
            {"source": "tokopedia", "raw_condition": "",
             "title": "VGA RTX 3060 Bekas Mulus Garansi",
             "expected": "second"},
            {"source": "tokopedia", "raw_condition": "",
             "title": "VGA RTX 3060 Garansi Resmi Segel",
             "expected": "new"},
            {"source": "facebook_marketplace", "raw_condition": "",
             "title": "VGA RTX 3060 Bekas Mulus",
             "expected": "unknown"},
        ]
        for case in cond_cases:
            actual, inferred = infer_condition(
                case["source"], case["raw_condition"], case["title"])
            case["actual"] = actual
            case["condition_inferred"] = inferred
            if actual != case["expected"]:
                raise SystemExit(
                    "PARITY KONDISI GAGAL: %s -> %s (harap %s)"
                    % (case["title"], actual, case["expected"]))
        gpu_defaults = categories["gpu"]["defaults"]
        cn_any, cs_any = resolve_condition_dummies(gpu_defaults, "any")
        if (cn_any, cs_any) != (gpu_defaults.get("cond_new_mean"),
                                gpu_defaults.get("cond_second_mean")):
            raise SystemExit("PARITY ANY GAGAL: dummy any != cond means")
        cond_cases.append({
            "condition_input": "any", "category": "gpu",
            "cond_new": cn_any, "cond_second": cs_any,
            "expected": "cond_new_mean/cond_second_mean dari JSON draft"})
        parity["condition_inference_cases"] = cond_cases
        laptop_cpu_cases = [
            {"text": "Laptop MSI Katana 15 HX I9 14900HX RTX5060 16GB 1TB",
             "expected_key": "intel core i9-14900hx",
             "expected_tag": "bare_ix"},
            {"text": "LOQ 15IRX9 I5 13450HX 16GB RTX 3050 Garansi 2028",
             "expected_key": "intel core i5-13450hx",
             "expected_tag": "bare_ix"},
            {"text": "Laptop HP 14 EP1177TU Intel Core 5-120U 8GB SSD 512GB",
             "expected_key": "intel core 5 120u",
             "expected_tag": "core_no_i"},
            {"text": "Laptop HP Omnibook 3 AI 14 Intel Core Ultra 5 125H "
             "16GB SSD 512GB",
             "expected_key": "intel core ultra 5 125h",
             "expected_tag": "ultra_3"},
            {"text": "Jual Santai Macbook Air M1 256GB SSD",
             "expected_key": "apple m1 8 core 3200 mhz",
             "expected_tag": "apple"},
            {"text": "Laptop Second Mulus Garansi",
             "expected_key": None, "expected_tag": "none"},
            {"text": "Laptop Gaming AMD Ryzen AI 9 HX 370 32GB",
             "expected_key": None, "expected_tag": "none"},
        ]
        for case in laptop_cpu_cases:
            score, full, tag = resolve_cpu_laptop(
                case["text"], bench_cpu, bench_mobile)
            case["actual_tag"] = tag
            case["actual_full"] = full
            exp_key = case["expected_key"]
            if exp_key is None:
                case["actual"] = "DROP:cpu_tidak_ditemukan"
                if score is not None or tag != "none":
                    raise SystemExit(
                        "PARITY LAPTOP CPU GAGAL: %s -> skor %s tag %s "
                        "(harap DROP)" % (case["text"], score, tag))
            else:
                exp_entry = bench_mobile.get(exp_key) \
                    or bench_cpu.get(exp_key)
                if not isinstance(exp_entry, dict):
                    raise SystemExit(
                        "PARITY LAPTOP CPU: kunci harap %s tidak ada di "
                        "katalog" % exp_key)
                exp_score = _score_of(exp_entry, "score")
                case["actual"] = full
                case["actual_score"] = score
                case["expected_score"] = exp_score
                if score != exp_score or tag != case["expected_tag"]:
                    raise SystemExit(
                        "PARITY LAPTOP CPU GAGAL: %s -> skor %s tag %s "
                        "(harap kunci %s skor %s tag %s)"
                        % (case["text"], score, tag, exp_key, exp_score,
                           case["expected_tag"]))
        parity["laptop_cpu_cases"] = laptop_cpu_cases
        parity_path.parent.mkdir(parents=True, exist_ok=True)
        with open(parity_path, "w", encoding="utf-8") as f:
            json.dump(parity, f, indent=2, ensure_ascii=False)
        print("parity ditulis: %s" % parity_path)
    print("JSON ditulis: %s" % out_path)
    print("Laporan ditulis: %s" % report_path)
    for cat in CATEGORIES:
        e = categories[cat]
        print("%s: n=%d enabled=%s fallback=%s src=%s MAE(a) model=%s "
              "baseline=%s MAPE model=%s MAE(b) model=%s median=%s"
              % (cat, e["n_rows"], e["enabled"], e["enabled_fallback"],
                 e["src_variant"],
                 fmt_rp(e["mae_model"]), fmt_rp(e["mae_baseline"]),
                 fmt_pct(e["mape_model"]), fmt_rp(e["mae_model_group"]),
                 fmt_rp(e["mae_category_median_group"])))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
