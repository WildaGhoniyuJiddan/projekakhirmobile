#!/usr/bin/env python3
"""Normalisasi listings_final.csv -> siap impor Supabase (skema models.py).

- condition: baru->new, bekas->second, tak diketahui->NULL (engine: NULL='new')
- raw_spec_text: deskripsi dipotong 1000 char (membantu RPC ilike model)
- condition_source: label kondisi mentah platform (provenance)
- kolom location dibuang (tidak ada di skema); is_official_store/sold_count/
  rating NULL (tidak diketahui, jujur)
- baris kategori laptop juga diparse -> laptop_units.csv (brand/cpu/gpu/
  ram_gb/storage_gb dari judul, konservatif: tak yakin -> NULL)
- sampah produk-jelas-bukan-komponen dibuang & dihitung
"""
import csv
import json
import re
from pathlib import Path

BASE = Path(__file__).parent

JUNK_TITLE = re.compile(
    r"(dus\s+saja|box\s+saja|kotak\s+saja|hanya\s+(dus|box|kotak)|"
    r"manual\s+book\s+saja|sticker\s+vga|stiker\s+vga)",
    re.I,
)
BRANDS = [
    "ASUS", "Lenovo", "Acer", "HP", "MSI", "Dell", "Apple", "Axioo",
    "Advan", "Samsung", "LG", "Huawei", "Xiaomi", "Infinix", "Zyrex",
]
RAM_RE = re.compile(r"(\d{1,2})\s*GB\s*(DDR\d|RAM|LPDDR\d)?", re.I)
STORAGE_RE = re.compile(r"(SSD|NVMe|HDD)?\s*(128|256|512|1000|1024|2048)\s*(GB|TB)", re.I)
CPU_RE = re.compile(
    r"(Core\s+i[3579][-\s]?\w*|Ryzen\s+[3579]\s*\w*|Apple\s+M\d\w*|"
    r"Celeron\s*\w*|Pentium\s*\w*|Athlon\s*\w*|Snapdragon\s*\w*)",
    re.I,
)
GPU_RE = re.compile(
    r"(RTX\s*\d{4}\w*|GTX\s*\d{3,4}\w*|RX\s*\d{4}\w*|Iris\s*Xe|UHD\s*Graphics|"
    r"Radeon\s*\w*|MX\s*\d{3}|GeForce\s*\w*)",
    re.I,
)


def parse_laptop(title: str) -> dict:
    t = title
    brand = next((b for b in BRANDS if b.lower() in t.lower()), None)
    ram = None
    m = RAM_RE.search(t)
    if m and 2 <= int(m.group(1)) <= 64:
        ram = int(m.group(1))
    storage = None
    m = STORAGE_RE.search(t)
    if m:
        storage = int(m.group(2)) * (1024 if m.group(3).upper() == "TB" else 1)
        if storage == 1000:
            storage = 1024
    cpu = None
    m = CPU_RE.search(t)
    if m:
        cpu = re.sub(r"\s+", " ", m.group(1)).strip()
    gpu = None
    m = GPU_RE.search(t)
    if m:
        gpu = re.sub(r"\s+", " ", m.group(1)).strip()
    return {"brand": brand, "cpu": cpu, "gpu": gpu, "ram_gb": ram,
            "storage_gb": storage}


FULLPC_MARKERS = re.compile(
    r"(pc\s*rakitan|rakitan\s*pc|paket\s*pc|pc\s*fullset|fullset\s*pc|"
    r"komputer\s*rakitan|pc\s*siap\s*pakai|satu\s*set\s*pc|jual\s*pc\b|"
    r"pc\s*gaming\s*fullset|rakit\s*pc)",
    re.I,
)
LAPTOP_MARKERS = re.compile(
    r"(laptop|notebook|vivobook|zenbook|thinkpad|ideapad|legion|"
    r"predator\s*helios|victus|probook|elitebook|pavilion|tuf\s*(dash|gaming\s*f)|"
    r"nitro\s*\d|omen\s*\d|loq\s*\d|katana|aspire|inspiron|latitude|"
    r"\brog\s*(zephyrus|flow|strix\s*scar)|macbook|chromebook|"
    r"\d{2}[.,]\d\s*(inch|inci)|layar\s*\d{2})",
    re.I,
)
GROUPS = {
    "cpu": re.compile(r"(ryzen\s*[3579]|core\s*i[3579][-\s]?\d|athlon\s*\d|pentium\s*g\d)", re.I),
    "gpu": re.compile(r"(rtx\s*\d{4}|gtx\s*\d{3,4}|rx\s*\d{4}|arc\s*a\d{3})", re.I),
    "ram": re.compile(r"(\d+\s*gb\s*(ddr|ram|kit)|ddr[45]\s*\d+\s*gb|ram\s*\d+\s*gb|\d+x\d+\s*gb)", re.I),
    "storage": re.compile(r"((ssd|nvme|hdd)\s*\d+\s*(gb|tb)|\d+\s*(gb|tb)\s*(ssd|nvme|hdd))", re.I),
    "mobo": re.compile(r"(b550|b660|b450|a520|h610|h510|x570|z690|a620|b760)", re.I),
    "psu": re.compile(r"(psu|power\s*supply)\s*\d+\s*w", re.I),
}


def is_laptop(title: str) -> bool:
    return bool(LAPTOP_MARKERS.search(title))


def is_full_pc(title: str, desc: str) -> bool:
    """PC rakitan utuh != 1 komponen. Penanda eksplisit (judul/desc) ATAU
    >=3 grup komponen berspek angka dalam JUDUL saja (anti keyword-stuffing)."""
    if FULLPC_MARKERS.search(f"{title} {desc[:300]}"):
        return True
    hits = sum(1 for g in GROUPS.values() if g.search(title))
    return hits >= 3


def clean_title(t: str) -> str:
    return re.sub(r"\s+", " ", (t or "")).strip()


def main() -> None:
    rows = list(csv.DictReader(open(BASE / "listings_final.csv", encoding="utf-8")))
    out, laptops, dropped = [], [], {"junk": 0, "title": 0}
    moved_pc = {}
    for r in rows:
        title = clean_title(r["raw_title"])
        if len(title) < 8:
            dropped["title"] += 1
            continue
        if JUNK_TITLE.search(title):
            dropped["junk"] += 1
            continue
        cond_map = {"baru": "new", "bekas": "second"}
        cond = cond_map.get((r["condition"] or "").strip(), None)
        desc = (r["description"] or "").strip()
        category = r["category"]
        if category != "laptop" and is_laptop(title):
            moved_pc[f"laptop_dari_{category}"] = moved_pc.get(f"laptop_dari_{category}", 0) + 1
            category = "laptop"
        elif category != "laptop" and category != "pc" and is_full_pc(title, desc):
            moved_pc[category] = moved_pc.get(category, 0) + 1
            category = "pc"
        row = {
            "source": r["source"],
            "category": category,
            "raw_title": title,
            "raw_price": int(r["raw_price"]),
            "raw_spec_text": desc[:1000] if desc else "",
            "description": desc,
            "listing_url": r["listing_url"],
            "listing_hash": r["listing_hash"],
            "condition": cond or "",
            "seller": (r["seller"] or "")[:255],
            "is_official_store": "",
            "sold_count": "",
            "rating": "",
            "condition_source": (r["condition_raw"] or "")[:32],
            "scraped_at": r["scraped_at"],
        }
        out.append(row)
        if category == "laptop":
            p = parse_laptop(title)
            laptops.append({
                "listing_hash": r["listing_hash"],
                "brand": p["brand"] or "",
                "model": title[:255],
                "cpu": p["cpu"] or "",
                "gpu": p["gpu"] or "",
                "ram_gb": p["ram_gb"] or "",
                "storage_gb": p["storage_gb"] or "",
                "screen_size": "",
                "price": int(r["raw_price"]),
                "condition": cond or "",
                "source": r["source"],
                "listing_url": r["listing_url"],
                "scraped_at": r["scraped_at"],
            })
    cols = list(out[0].keys())
    with open(BASE / "listings_clean.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows(out)
    with open(BASE / "laptop_units_clean.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(laptops[0].keys()))
        w.writeheader()
        w.writerows(laptops)
    from collections import Counter
    stats = {
        "input": len(rows),
        "output": len(out),
        "dropped": dropped,
        "moved_to_pc": moved_pc,
        "laptop_units": len(laptops),
        "condition": dict(Counter(r["condition"] or "(null)" for r in out)),
        "by_source": dict(Counter(r["source"] for r in out)),
        "by_category": dict(Counter(r["category"] for r in out)),
        "laptop_parse_filled": {
            k: sum(1 for l in laptops if l[k]) for k in
            ("brand", "cpu", "gpu", "ram_gb", "storage_gb")
        },
    }
    (BASE / "normalize_stats.json").write_text(json.dumps(stats, indent=1))
    print(json.dumps(stats, indent=1))


if __name__ == "__main__":
    main()
