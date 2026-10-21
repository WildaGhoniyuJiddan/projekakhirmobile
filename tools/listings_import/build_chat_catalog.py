#!/usr/bin/env python3
"""Bangun katalog grounding Bang Worth (retail_catalog.json) yang lengkap.

Sumber:
1. Katalog retail existing (harga baru, nama rapi) — dipertahankan.
2. listings_clean.csv — panen marketplace (FB + Tokopedia) 2026-10-21:
   komponen gpu/cpu/motherboard/ram/storage + pc rakitan.
3. laptop_units_clean.csv — 681 unit laptop terparse dari panen sama.

Aturan:
- Harga representatif per model = MEDIAN harga listing valid.
- Harga valid: 50rb–150jt (aturan Dan).
- Model yang sudah ada di katalog retail TIDAK diduplikasi.
- Listing bundle (judul mengandung '+' komponen lain / 'paket') dibuang.
- Judul dibersihkan dari kata promo; mayoritas kondisi 'second' diberi
  penanda '(bekas)' pada nama tampil.
- Kategori baru: 'laptop' dan 'pc' (rakitan jadi).

Output ditulis ke supabase/functions/bang-worth/retail_catalog.json dan
assets/data/retail_catalog.json (dua salinan harus identik).
"""
import csv
import json
import re
import statistics
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FN_OUT = ROOT / "supabase/functions/bang-worth/retail_catalog.json"
APP_OUT = ROOT / "assets/data/retail_catalog.json"
LISTINGS = ROOT / "tools/listings_import/listings_clean.csv"
LAPTOPS = ROOT / "tools/listings_import/laptop_units_clean.csv"

PRICE_MIN, PRICE_MAX = 50_000, 150_000_000

PROMO_RE = re.compile(
    r"\b(dijual|jual|promo|murah|meriah|cod|nego|nett?|mulus|segel|like new|"
    r"ex user|ex pemakaian|pemakaian pribadi|garansi on|garansi resmi|"
    r"harga pas|harga net|jual cepat|bu|butuh uang|fullset|full set|"
    r"komplit|lengkap dengan|bonus|gratis|cashback|ready stock|ready|"
    r"stok|original|ori|resmi|termurah|terlaris|best seller|flash sale|"
    r"sold|terjual|istimewa)\b",
    re.I,
)
BUNDLE_RE = re.compile(r"\+|paket|bundle|combo|set dengan", re.I)


def norm_key(name: str) -> str:
    return re.sub(r"[^a-z0-9]", "", name.lower())


def clean_title(title: str) -> str:
    t = title.split("|")[0]
    t = re.sub(r"[\[\]{}<>#*_~`]", " ", t)
    t = re.sub(r"[-–—]{2,}", " ", t)
    # Buang frasa promo di mana pun, lalu rapikan sisa tanda baca tepi.
    t = PROMO_RE.sub(" ", t)
    t = re.sub(r"\s+", " ", t).strip(" -–—·•.,")
    # Promo sering menempel di ekor setelah ' - ': potong segmen ekor
    # yang tidak mengandung digit (segmen model selalu mengandung digit).
    parts = [p.strip() for p in t.split(" - ")]
    while len(parts) > 1 and not re.search(r"\d", parts[-1]):
        parts.pop()
    t = " - ".join(p for p in parts if p)
    t = re.sub(r"\s+", " ", t).strip()
    if len(t) > 95:
        t = t[:95].rsplit(" ", 1)[0]
    return t


def valid_price(v) -> int | None:
    try:
        p = int(float(v))
    except (TypeError, ValueError):
        return None
    return p if PRICE_MIN <= p <= PRICE_MAX else None


# Harga placeholder penjual ("Rp123.123", "Rp111.111") — racun grounding.
PLACEHOLDER_PRICES = {111_111, 123_123, 123_000, 999_999, 888_888, 555_555,
                      100_000_000, 99_999_999, 1_234_567}

# Lantai harga per kategori (di bawah ini = suku cadang/junk, bukan unit).
CAT_MIN = {"gpu": 120_000, "cpu": 100_000, "motherboard": 100_000,
           "ram": 50_000, "storage": 50_000, "laptop": 800_000,
           "pc": 1_000_000}

BROKEN_RE = re.compile(
    r"\b(rusak|mati total|matot|no display|error|bahan|kanibalan|"
    r"sparepart|spare part|buat kanibal|minus parah)\b", re.I)

GPU_SIGNAL = re.compile(
    r"rtx|gtx|radeon|geforce|\brx\s?\d|\bgt\s?\d{3}|arc\s?[ab]\d|quadro", re.I)
CPU_SIGNAL = re.compile(
    r"ryzen|core\s?i\d|core ultra|pentium|celeron|athlon|xeon|threadripper",
    re.I)
MOBO_SIGNAL = re.compile(
    r"motherboard|mainboard|mobo|\b[bhzxa]\d{3}\b|am[45]|lga\s?\d{4}", re.I)
RAM_SIGNAL = re.compile(r"ddr[345]|\bram\b|sodimm|so-dimm|dimm", re.I)
STORAGE_SIGNAL = re.compile(r"ssd|hdd|nvme|sata|harddisk|hardisk|m\.2", re.I)
LAPTOP_BRAND = re.compile(
    r"laptop|notebook|legion|loq|tuf|rog|nitro|predator|ideapad|thinkpad|"
    r"yoga|vivobook|zenbook|pavilion|omen|victus|alienware|macbook|aspire|"
    r"swift|envy|spectre|inspiron|latitude|\bxps\b|katana|bravo|modern|"
    r"prestige|matebook|surface|chromebook|advan|axioo|zyrex|msi|acer|asus|"
    r"lenovo|hp|dell|apple|samsung|lg gram|gigabyte|razer", re.I)
LAPTOP_REJECT = re.compile(
    r"sodimm|so-dimm|ram laptop|memory notebook|ram notebook|memory laptop|"
    r"monitor|tablet|iphone|smartphone|"
    r"samsung a\d|redmi|oppo|vivo|realme|\d{2}\s?-?\s?inch", re.I)
PC_SIGNAL = re.compile(r"\bpc\b|rakitan|build|paket|komputer|fullset", re.I)


def category_ok(cat: str, name: str) -> bool:
    """Gerbang sinyal: judul harus benar-benar milik kategorinya."""
    if BROKEN_RE.search(name):
        return False
    if cat == "gpu":
        # Listing 'pilihan' dua model GPU dalam satu judul = ambigu.
        if len(re.findall(r"(?:rtx|gtx|rx)\s?\d{3,4}", name, re.I)) > 1:
            return False
        return bool(GPU_SIGNAL.search(name))
    if cat == "cpu":
        if name.lower().startswith("pc "):
            return False
        return bool(CPU_SIGNAL.search(name))
    if cat == "motherboard":
        return bool(MOBO_SIGNAL.search(name))
    if cat == "ram":
        return bool(RAM_SIGNAL.search(name))
    if cat == "storage":
        return bool(STORAGE_SIGNAL.search(name))
    if cat == "pc":
        if "unit only" in name.lower():
            return False
        return bool(PC_SIGNAL.search(name))
    if cat == "laptop":
        if LAPTOP_REJECT.search(name):
            return False
        # Monitor menyamar seri laptop (mis. "Lenovo LOQ 24-10 24\""):
        # ukuran layar 19-34 inci dengan tanda kutip = monitor desktop.
        inch = re.search(r"(\d{2})\s*[\"”]", name)
        if inch and int(inch.group(1)) in {19, 20, 22, 24, 27, 32, 34}:
            return False
        if not LAPTOP_BRAND.search(name):
            return False
        # Laptop asli selalu menyebut CPU/GPU atau kata 'laptop' itu
        # sendiri — SSD/RAM polos yang lolos gerbang merek gugur di sini.
        compute = CPU_SIGNAL.search(name) or GPU_SIGNAL.search(name) or \
            re.search(r"\blaptop\b|a\d-\d{4}", name, re.I)
        return bool(compute)
    return True


def main() -> None:
    catalog = json.loads(FN_OUT.read_text())
    before = {k: len(v) for k, v in catalog.items() if isinstance(v, list)}

    existing: dict[str, set[str]] = {}
    for cat in ("gpu", "cpu", "motherboard", "ram", "storage"):
        existing[cat] = {norm_key(it["model"]) for it in catalog.get(cat, [])}

    # --- Komponen + PC rakitan dari panen marketplace -------------------
    groups: dict[str, dict[str, dict]] = defaultdict(dict)
    rows = list(csv.DictReader(LISTINGS.open(encoding="utf-8")))
    cat_map = {"gpu": "gpu", "cpu": "cpu", "motherboard": "motherboard",
               "ram": "ram", "storage": "storage", "pc": "pc"}
    skipped_bundle = skipped_junk = 0
    for r in rows:
        cat = cat_map.get(r["category"])
        if cat is None:
            continue
        price = valid_price(r["raw_price"])
        if price is None or price in PLACEHOLDER_PRICES or \
                price < CAT_MIN.get(cat, PRICE_MIN):
            continue
        raw = r["raw_title"].strip()
        if BUNDLE_RE.search(raw):
            skipped_bundle += 1
            continue
        name = clean_title(raw)
        if len(name) < 10 or not re.search(r"\d", name) or \
                not category_ok(cat, name):
            skipped_junk += 1
            continue
        key = norm_key(name)
        g = groups[cat].setdefault(
            key, {"name": name, "prices": [], "conds": Counter()})
        g["prices"].append(price)
        if r["condition"]:
            g["conds"][r["condition"]] += 1

    added: dict[str, int] = {}
    for cat, gmap in groups.items():
        catalog.setdefault(cat, [])
        have = existing.get(cat, set())
        n = 0
        for key, g in gmap.items():
            if key in have:
                continue
            name = g["name"]
            if cat == "ram" and re.search(r"so-?dimm", name, re.I):
                # Faktor bentuk beda: RAM laptop jangan sampai dipilih
                # untuk build desktop — tandai agar model menghindarinya.
                name += " [SODIMM]"
            if g["conds"].get("second", 0) > g["conds"].get("new", 0):
                name += " (bekas)"
            catalog[cat].append(
                {"model": name, "price": int(statistics.median(g["prices"]))})
            have.add(key)
            n += 1
        added[cat] = n

    # --- Laptop ----------------------------------------------------------
    lap_groups: dict[str, dict] = {}
    for r in csv.DictReader(LAPTOPS.open(encoding="utf-8")):
        price = valid_price(r["price"])
        if price is None or price in PLACEHOLDER_PRICES or \
                price < CAT_MIN["laptop"]:
            continue
        name = clean_title(r["model"])
        if len(name) < 10 or not category_ok("laptop", name):
            continue
        key = norm_key(name)
        g = lap_groups.setdefault(
            key, {"name": name, "prices": [], "conds": Counter()})
        g["prices"].append(price)
        if r["condition"]:
            g["conds"][r["condition"]] += 1
    catalog["laptop"] = []
    for g in lap_groups.values():
        name = g["name"]
        if g["conds"].get("second", 0) > g["conds"].get("new", 0):
            name += " (bekas)"
        catalog["laptop"].append(
            {"model": name, "price": int(statistics.median(g["prices"]))})
    added["laptop"] = len(catalog["laptop"])

    # Urutkan tiap kategori berdasarkan harga naik agar file stabil.
    for cat in ("gpu", "cpu", "motherboard", "ram", "storage", "pc", "laptop"):
        if isinstance(catalog.get(cat), list):
            catalog[cat].sort(key=lambda it: it["price"])

    from datetime import datetime, timezone
    catalog["generated_at"] = datetime.now(timezone.utc).isoformat()

    payload = json.dumps(catalog, ensure_ascii=False, indent=1)
    FN_OUT.write_text(payload)
    APP_OUT.write_text(payload)

    after = {k: len(v) for k, v in catalog.items() if isinstance(v, list)}
    print(f"bundle dibuang: {skipped_bundle}, judul sampah dibuang: {skipped_junk}")
    for cat in sorted(set(before) | set(after)):
        print(f"{cat:12s} {before.get(cat, 0):5d} -> {after.get(cat, 0):5d} "
              f"(+{added.get(cat, 0)})")
    print("TOTAL:", sum(after.values()))


if __name__ == "__main__":
    main()
