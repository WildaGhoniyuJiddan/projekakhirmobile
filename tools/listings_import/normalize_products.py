#!/usr/bin/env python3
"""Normalisasi katalog berjalan -> DATASET PRODUK untuk etalase Cari Produk.

Satu baris per PRODUK (bukan per varian listing): nama dibersihkan jadi
nama produk rapi ("Colorful RTX 3050 6GB"), harga representatif =
harga katalog retail upload Dan bila ada varian yang norm-key-nya cocok
persis, selain itu MEDIAN harga semua varian.

Deterministik, tanpa network. Aturan per kategori:
- gpu/cpu/ram/motherboard: ekstraktor pola (merek + seri inti + pembeda)
- storage/laptop/pc + fallback: cleaner token generik

Input : assets/data/retail_catalog.json (katalog berjalan)
        ~/workspace/user/files/retail_catalog.json (retail asli, prioritas harga)
Output: assets/data/products_normalized.json
"""
import json
import re
import statistics
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CURRENT_PATH = REPO / "assets/data/retail_catalog.json"
UPLOAD_PATH = Path.home() / "workspace/user/files/retail_catalog.json"
OUT_PATH = REPO / "assets/data/products_normalized.json"
CAT_ORDER = ["gpu", "cpu", "motherboard", "ram", "storage", "pc", "laptop"]

# ---------------------------------------------------------------------------
# Peta merek: token lowercase -> ejaan kanonik
# ---------------------------------------------------------------------------
BRANDS = {
    "amd": "AMD", "intel": "Intel", "nvidia": "NVIDIA",
    "asus": "ASUS", "msi": "MSI", "gigabyte": "Gigabyte", "asrock": "ASRock",
    "colorful": "Colorful", "igame": "iGame", "galax": "GALAX",
    "zotac": "Zotac", "sapphire": "Sapphire", "powercolor": "PowerColor",
    "palit": "Palit", "gainward": "Gainward", "inno3d": "Inno3D",
    "pny": "PNY", "xfx": "XFX", "maxsun": "Maxsun", "biostar": "Biostar",
    "afox": "AFOX", "venomrx": "VenomRX", "adata": "ADATA", "aigo": "Aigo",
    "kingston": "Kingston", "corsair": "Corsair", "klevv": "KLEVV",
    "teamgroup": "TeamGroup", "team": "TeamGroup", "hynix": "Hynix",
    "samsung": "Samsung", "wd": "WD", "wdc": "WD", "seagate": "Seagate",
    "crucial": "Crucial", "lexar": "Lexar", "sandisk": "SanDisk",
    "v-gen": "V-GeN", "vgen": "V-GeN", "hikvision": "Hikvision",
    "acer": "Acer", "lenovo": "Lenovo", "hp": "HP", "dell": "Dell",
    "nzxt": "NZXT",
    "apple": "Apple", "axioo": "Axioo", "msi": "MSI", "toshiba": "Toshiba",
    "transcend": "Transcend", "apacer": "Apacer", "patriot": "Patriot",
    "g.skill": "G.Skill", "gskill": "G.Skill",
}
# Pola merek multi-kata / bertanda hubung yang hancur saat tokenisasi.
BRAND_PATTERNS = [
    (re.compile(r"g[.\s]?skill", re.I), "G.Skill"),
    (re.compile(r"v-?gen", re.I), "V-GeN"),
    (re.compile(r"western\s+digital", re.I), "WD"),
]
AIB_GPU = {
    "asrock", "asus", "msi", "gigabyte", "colorful", "igame", "galax",
    "zotac", "sapphire", "powercolor", "palit", "gainward", "inno3d",
    "pny", "xfx", "maxsun", "biostar", "yeston", "leadtek", "evga",
    "manli", "afox", "venomrx",
}

STOPWORDS = {
    "new", "unit", "box", "tray", "bulk", "package", "garansi", "warranty",
    "replacement", "resmi", "bekas", "second", "used", "ready", "promo",
    "murah", "original", "wts", "wtb", "jual", "dijual", "nego", "socket",
    "series", "cache", "th", "thn", "tahun", "year", "years", "up", "to",
    "with", "for", "cocok", "buat", "untuk", "bisa", "siap", "pakai",
    "dan", "atau", "yang", "di", "ke", "dari", "vga", "grs", "copotan",
    "longdimm", "longdim", "dimm", "edition", "version", "ghz", "mhz",
    "core", "cores", "thread", "threads", "bnib", "tinggal",
    "am3", "am4", "am5", "fm2", "str5", "swrx8",
}
JUNK_TOKEN = [
    re.compile(r"^\d+(\.\d+)?(ghz|mhz|rpm)$", re.I),       # frekuensi/putaran
    re.compile(r"^x\d$", re.I),                            # "x4" PCIe lanes
    re.compile(r"^\d+(\.\d+)?mb$", re.I),                  # cache MB
    re.compile(r"^\d+(\.\d+)?(mt/s|mb/s|gb/s|gbps|mbps)$", re.I),
    re.compile(r"^\d+(\.\d+)?w$", re.I),                   # watt
    re.compile(r"^\d+(\.\d+)?mm$", re.I),
    re.compile(r"^\d+%$"),                                 # diskon "67%"
    re.compile(r"^\d+\.\d+$"),                             # versi "4.0", "1.2"
    re.compile(r"^pc\d{4,5}$", re.I),                      # PC25600
    re.compile(r"^cl\d+(-\d+)*$", re.I),                   # timing CL16-..
    re.compile(r"^\d+x\d+(gb|mb)$", re.I),                 # notasi kit 2x8GB
    re.compile(r"^gddr\d\+?$", re.I),                      # GDDR6 dst
    re.compile(r"^\d+(st|nd|rd|th)$", re.I),               # "5th"
]
TOKEN_CANON = {
    "nvme": "NVMe", "ssd": "SSD", "hdd": "HDD", "sata": "SATA",
    "sata2": "SATA", "sata3": "SATA", "pc": "PC", "usb": "USB",
    "ddr3": "DDR3", "ddr4": "DDR4", "ddr5": "DDR5", "rgb": "RGB",
    "wifi": "WiFi", "ips": "IPS", "fhd": "FHD", "rtx": "RTX", "nas": "NAS",
    "gtx": "GTX", "rx": "RX", "i3": "i3", "i5": "i5", "i7": "i7",
    "i9": "i9", "m.2": None, "pcie": None, "gen3": None, "gen4": None,
    "gen5": None, "gen": None,
}


def norm_key(name: str) -> str:
    s = re.sub(r"[^a-z0-9]+", " ", name.lower())
    return re.sub(r"\s+", " ", s).strip()


def strip_segments(s: str) -> str:
    """Buang segmen [...] dan (...) beserta isinya."""
    s = re.sub(r"\[[^\]]*\]", " ", s)
    s = re.sub(r"\([^)]*\)", " ", s)
    return s


def find_brand(raw: str, tokens: list[str]) -> str | None:
    low = raw.lower()
    for pat, canon in BRAND_PATTERNS:
        if pat.search(low):
            return canon
    for tok in tokens[:4]:
        if tok.lower() in BRANDS:
            return BRANDS[tok.lower()]
    return None


def title_token(tok: str) -> str:
    low = tok.lower()
    if low in TOKEN_CANON:
        return TOKEN_CANON[low] or ""
    if low in BRANDS:
        return BRANDS[low]
    if re.search(r"\d", tok):
        # Token model: huruf ekor jadi kapital (7500f -> 7500F, 7800x3d -> 7800X3D)
        return re.sub(r"([a-z]+)$", lambda m: m.group(1).upper(), tok.lower()) \
            if re.fullmatch(r"\d+[a-z]{1,3}", low) else tok
    return tok.title() if tok.isalpha() else tok


# ---------------------------------------------------------------------------
# Ekstraktor per kategori — semua regex atas string mentah (case-insensitive)
# ---------------------------------------------------------------------------
def clean_gpu(raw: str) -> str | None:
    low = raw.lower()
    m = re.search(
        r"\b(rtx|gtx|rx|arc|gt)\s*-?\s*(\d{3,4}|[ab]\d{3})"
        r"\s*(ti|xtx|xt|super|gre|m|s)?\b", low)
    if not m:
        return None
    core, num, suf = m.group(1), m.group(2), m.group(3)
    core_canon = {"rtx": "RTX", "gtx": "GTX", "gt": "GT", "rx": "RX",
                  "arc": "Arc"}[core]
    if core == "arc":
        num = num.upper()
    suf_canon = {"ti": " Ti", "xt": " XT", "xtx": " XTX", "super": " Super",
                 "gre": " GRE", "m": "M", "s": "S"}.get(suf or "", "")
    # VRAM dicari mulai posisi model GPU & dipotong di kata 'ram'
    # (listing marketplace suka menyelipkan "RAM 16GB" = RAM sistem).
    seg = re.split(r"\bram\b", low[m.start():])[0]
    vram = re.search(r"(\d{1,2})\s?gb\b", seg)
    head = strip_segments(raw)
    tokens = re.split(r"[^A-Za-z0-9.]+", head)
    brand = None
    for tok in tokens[:5]:
        if tok.lower() in AIB_GPU:
            brand = BRANDS.get(tok.lower(), tok.title())
            break
    if brand is None:
        brand = {"rtx": "NVIDIA", "gtx": "NVIDIA", "gt": "NVIDIA",
                 "rx": "AMD", "arc": "Intel"}[core]
    name = f"{brand} {core_canon} {num}{suf_canon}"
    if vram:
        name += f" {vram.group(1)}GB"
    return name


def clean_cpu(raw: str) -> str | None:
    low = raw.lower()
    # Suffix model bisa menyelipkan digit (X3D) -> wajib mulai huruf,
    # sisanya alfanumerik. Pemisah kelas-model bisa '-' ("RYZEN 7 - 5700").
    m = re.search(r"threadripper\s+(pro\s+)?(\d{4})([a-z]{1,2})\b", low)
    if m:
        pro = "PRO " if m.group(1) else ""
        return f"AMD Ryzen Threadripper {pro}{m.group(2)}{m.group(3).upper()}"
    m = re.search(r"ryzen\s+(?:ai\s+)?([3579])[\s-]+(\d{4,5})"
                  r"([a-z][a-z0-9]{0,3})?\b", low)
    if m:
        return f"AMD Ryzen {m.group(1)} {m.group(2)}{(m.group(3) or '').upper()}"
    m = re.search(r"core\s+ultra\s+([3579])\s+(\d{3,4})([a-z][a-z0-9]{0,2})?\b",
                  low)
    if m:
        return (f"Intel Core Ultra {m.group(1)} {m.group(2)}"
                f"{(m.group(3) or '').upper()}")
    m = re.search(r"core\s+i([3579])\s*-?\s*(\d{4,5})([a-z][a-z0-9]{0,2})?\b",
                  low)
    if m:
        return (f"Intel Core i{m.group(1)} {m.group(2)}"
                f"{(m.group(3) or '').upper()}")
    m = re.search(r"athlon\s+(\d{4})([a-z]?)\b", low)
    if m:
        return f"AMD Athlon {m.group(1)}{m.group(2).upper()}"
    m = re.search(r"\ba(4|6|8|10|12)[\s-]+(\d{4})([a-z]?)\b", low)
    if m:  # APU A-series (A6-9500, A10-9700, ...)
        return f"AMD A{m.group(1)} {m.group(2)}{m.group(3).upper()}"
    m = re.search(r"(pentium|celeron)\s+([a-z]?\d{3,4}[a-z]?)", low)
    if m:
        return f"Intel {m.group(1).title()} {m.group(2).upper()}"
    m = re.search(r"xeon\s+([a-z]?\d-?\d{3,4}[a-z]?\d?)", low)
    if m:
        return f"Intel Xeon {m.group(1).upper()}"
    return None


def clean_ram(raw: str) -> str | None:
    low = raw.lower()
    ddr = re.search(r"ddr\s?([345])\b", low)
    cap = None
    for m in re.finditer(r"(\d{1,3})\s?gb\b", low):
        if m.start() > 0 and low[m.start() - 1] == "x":
            continue  # bagian dari notasi kit 2x32GB
        cap = m.group(1)
        break
    if cap is None:
        kit = re.search(r"(\d+)\s?x\s?(\d+)\s?gb", low)
        if kit:
            cap = str(int(kit.group(1)) * int(kit.group(2)))
    if cap is None:
        return None
    head = strip_segments(raw)
    tokens = re.split(r"[^A-Za-z0-9.]+", head)
    brand = find_brand(raw, tokens) or "RAM"
    name = brand
    if ddr:
        name += f" DDR{ddr.group(1)}"
    name += f" {cap}GB"
    if re.search(r"so-?dimm", low):
        name += " SODIMM"
    return name


def clean_motherboard(raw: str) -> str | None:
    low = raw.lower()
    chipset = None
    for tok in re.split(r"[^A-Za-z0-9]+", low):
        if re.fullmatch(r"(a|b|h|x|z|trx|wrx)\d{2,3}[a-z]{0,2}", tok):
            chipset = tok.upper()
            break
    if chipset is None:
        return None
    ddr = re.search(r"ddr\s?([345])\b", low)
    head = strip_segments(raw)
    tokens = re.split(r"[^A-Za-z0-9.]+", head)
    brand = find_brand(raw, tokens) or (tokens[0].title() if tokens else None)
    if brand is None:
        return None
    name = f"{brand} {chipset}"
    if ddr:
        name += f" DDR{ddr.group(1)}"
    return name


def clean_generic(raw: str, category: str) -> str | None:
    screen = None
    if category == "laptop":
        sm = re.search(r"(\d{2}(?:\.\d)?)\s?(inch|\")", raw.lower())
        if sm:
            screen = f"{sm.group(1)}\""
    s = strip_segments(raw)
    s = re.sub(r"\b\d+%\s?", " ", s)  # sisa penanda diskon "67%"
    tokens = re.split(r"[^A-Za-z0-9.\"]+", s)
    cap = {"storage": 7, "laptop": 7, "pc": 8}.get(category, 7)
    out: list[str] = []
    for tok in tokens:
        if not tok:
            continue
        low = tok.lower()
        if low in STOPWORDS or any(p.match(tok) for p in JUNK_TOKEN):
            continue
        if len(tok) == 1 and tok.isalpha():
            continue
        canon = title_token(tok)
        if canon:
            out.append(canon)
    # dedupe token berurutan yang sama
    out = [t for i, t in enumerate(out) if i == 0 or t != out[i - 1]]
    out = out[:cap]
    if screen and screen not in out:
        out.append(screen)
    if len(out) < 2:
        return None
    return " ".join(out)


EXTRACTORS = {"gpu": clean_gpu, "cpu": clean_cpu, "ram": clean_ram,
              "motherboard": clean_motherboard}


def clean_name(raw: str, category: str) -> str | None:
    name = None
    if category in EXTRACTORS:
        name = EXTRACTORS[category](raw)
    if name is None:
        name = clean_generic(raw, category)
    if name is None:
        return None
    name = name.replace("(", " ").replace(")", " ")
    name = re.sub(r"\s+", " ", name).strip()
    meaningful = [t for t in name.split() if len(t) >= 2 or t.isdigit()]
    if len(meaningful) < 2:
        return None
    return name


def slugify(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


def main() -> None:
    current = json.loads(CURRENT_PATH.read_text())
    upload = json.loads(UPLOAD_PATH.read_text())

    # Indeks retail upload: per kategori, norm_key -> harga (pertama menang)
    retail_idx: dict[str, dict[str, int]] = {}
    for cat, items in upload.items():
        if not isinstance(items, list):
            continue
        idx: dict[str, int] = {}
        for it in items:
            idx.setdefault(norm_key(it["model"]), int(it["price"]))
        retail_idx[cat] = idx

    groups: dict[tuple[str, str], dict] = {}
    raw_counts: dict[str, int] = {}
    dropped = 0
    for cat in CAT_ORDER:
        items = current.get(cat)
        if not isinstance(items, list):
            continue
        raw_counts[cat] = len(items)
        for it in items:
            raw_name, price = str(it["model"]), int(it["price"])
            clean = clean_name(raw_name, cat)
            if clean is None:
                dropped += 1
                continue
            key = (cat, clean.lower())
            g = groups.setdefault(key, {"name": clean, "prices": [],
                                        "retail": None, "sample_raw": raw_name})
            g["prices"].append(price)
            if g["retail"] is None:
                rp = retail_idx.get(cat, {}).get(norm_key(raw_name))
                if rp is not None:
                    g["retail"] = rp

    products = []
    used_ids: set[str] = set()
    per_cat: dict[str, int] = {}
    for cat in CAT_ORDER:
        cat_groups = [(k, g) for k, g in groups.items() if k[0] == cat]
        cat_groups.sort(key=lambda kv: kv[1]["name"].lower())
        for _, g in cat_groups:
            price = g["retail"] if g["retail"] is not None else \
                int(round(statistics.median(g["prices"])))
            base_id = f"{cat}-{slugify(g['name'])}"
            pid, n = base_id, 2
            while pid in used_ids:
                pid = f"{base_id}-{n}"
                n += 1
            used_ids.add(pid)
            products.append({
                "id": pid, "name": g["name"], "category": cat,
                "price": price, "variants": len(g["prices"]),
                "price_min": min(g["prices"]), "price_max": max(g["prices"]),
            })
            per_cat[cat] = per_cat.get(cat, 0) + 1

    OUT_PATH.write_text(json.dumps({"products": products},
                                   ensure_ascii=False, separators=(",", ":")))
    size_kb = OUT_PATH.stat().st_size / 1024

    print(f"RAW total: {sum(raw_counts.values())} | dropped: {dropped} "
          f"| produk: {len(products)} | file: {size_kb:.0f} KB")
    for cat in CAT_ORDER:
        print(f"  {cat}: {raw_counts.get(cat, 0)} mentah -> "
              f"{per_cat.get(cat, 0)} produk")
    top = sorted(products, key=lambda p: -p["variants"])[:5]
    print("TOP dedupe:")
    for p in top:
        print(f"  {p['name']} [{p['category']}] variants={p['variants']} "
              f"rentang {p['price_min']}-{p['price_max']} -> Rp{p['price']:,}")


if __name__ == "__main__":
    main()
