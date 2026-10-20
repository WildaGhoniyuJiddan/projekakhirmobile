#!/usr/bin/env python3
"""Compile panen mentah -> listings_final.csv (aturan Dan 2026-10-20).

Aturan:
1. dedupe (listing_id > url > judul+harga+seller)
2. buang ex-mining (kecuali dinegasikan)
3. buang WTB / harga null / di luar 50rb-150jt / placeholder
4. klasifikasi kondisi baru/bekas dari label platform + penanda teks
"""
import csv
import glob
import hashlib
import json
import re
import sys
from pathlib import Path

BASE = Path(__file__).parent

MINING = re.compile(
    r"(ex[\s\-]?mining|mining\s*rig|rig\s*mining|bekas\s+mining|garapan|"
    r"crypto\s*mining|untuk\s+mining|penambangan)",
    re.I,
)
NEGATION = re.compile(r"(bukan|non[\s\-]?|no\s|tidak|anti|bkn)\W{0,4}$", re.I)

WTB = re.compile(
    r"^\s*(nyari|cari|wtb|wts\s*\/\s*wtb|dicari|dibutuhkan|dana\b|"
    r"looking\s+for|pengen\s+beli|mau\s+beli)",
    re.I,
)
PLACEHOLDER_PRICES = {1, 10, 100, 1000, 12345, 123456, 1234567, 111111, 999999}

BEKAS = re.compile(
    r"(bekas|second|2nd|seken|like\s*new|mulus|pemakaian|garansi\s+(off|habis|tidak\s+ada)|"
    r"fullset|batangan|no\s*minus|lecet|dijual\s+karena|butuh\s+uang|\bBU\b|"
    r"secondhand|bekas\s+pakai|ex\s+gaming|ex\s+display|bekas\s+review)",
    re.I,
)
BARU = re.compile(
    r"(BNIB|brand\s+new|\bbaru\b|segel|sealed|garansi\s+resmi|garansi\s+distributor|new\s+arrival)",
    re.I,
)


def is_mining(text: str) -> bool:
    for m in MINING.finditer(text):
        before = text[max(0, m.start() - 14) : m.start()]
        if NEGATION.search(before):
            continue
        return True
    return False


def classify(condition_raw: str, text: str) -> str:
    cr = (condition_raw or "").strip().lower()
    if cr.startswith("new"):
        return "baru"
    if cr.startswith("used"):
        return "bekas"
    if BEKAS.search(text):
        return "bekas"
    if BARU.search(text):
        return "baru"
    return ""


def main() -> None:
    rows = []
    files = sorted(glob.glob(str(BASE / "raw" / "*" / "batch_*.jsonl")))
    for fp in files:
        for line in open(fp, encoding="utf-8"):
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    stats = {"raw": len(rows)}
    seen = set()
    kept = []
    dropped = {"dup": 0, "mining": 0, "wtb": 0, "price": 0}
    for r in rows:
        title = (r.get("title") or "").strip()
        desc = r.get("description") or ""
        text = f"{title}\n{desc}"
        key = (
            r.get("listing_id")
            or r.get("url")
            or hashlib.sha256(
                f"{title}|{r.get('price_idr')}|{r.get('seller')}".encode()
            ).hexdigest()
        )
        if key in seen:
            dropped["dup"] += 1
            continue
        seen.add(key)
        if is_mining(text):
            dropped["mining"] += 1
            continue
        if WTB.search(title):
            dropped["wtb"] += 1
            continue
        price = r.get("price_idr")
        if (
            not isinstance(price, int)
            or price < 50_000
            or price > 150_000_000
            or price in PLACEHOLDER_PRICES
        ):
            dropped["price"] += 1
            continue
        cond = classify(r.get("condition_raw", ""), text)
        url = r.get("url") or ""
        kept.append(
            {
                "source": "facebook_marketplace"
                if r.get("source") == "facebook"
                else r.get("source", ""),
                "category": r.get("category", ""),
                "raw_title": title,
                "raw_price": price,
                "raw_spec_text": "",
                "description": desc[:4000],
                "listing_url": url,
                "listing_hash": hashlib.sha256(
                    f"{r.get('source')}|{url}".encode()
                ).hexdigest(),
                "condition": cond,
                "condition_raw": r.get("condition_raw", ""),
                "seller": r.get("seller", ""),
                "location": r.get("location", ""),
                "scraped_at": r.get("scraped_at", ""),
            }
        )
    stats["kept"] = len(kept)
    stats["dropped"] = dropped
    stats["by_source"] = {}
    stats["by_condition"] = {}
    for k in kept:
        stats["by_source"][k["source"]] = stats["by_source"].get(k["source"], 0) + 1
        c = k["condition"] or "(kosong)"
        stats["by_condition"][c] = stats["by_condition"].get(c, 0) + 1
    out = BASE / "listings_final.csv"
    with open(out, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(kept[0].keys()) if kept else [])
        if kept:
            w.writeheader()
            w.writerows(kept)
    (BASE / "compile_stats.json").write_text(json.dumps(stats, indent=1))
    print(json.dumps(stats, indent=1))


if __name__ == "__main__":
    sys.exit(main())
