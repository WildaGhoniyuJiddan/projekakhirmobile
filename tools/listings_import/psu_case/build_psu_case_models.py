#!/usr/bin/env python3
"""Olah panen PSU + casing PC (FB Marketplace + Tokopedia) -> model bersih.

Sumber mentah: ~/workspace/scrape-20261021/psu_case_raw/{fb,toko}/batch_*.jsonl
Keluaran (lokal, belum masuk katalog):
  tools/listings_import/psu_case/psu_case_models.json
  tools/listings_import/psu_case/LAPORAN.md

Aturan mengikuti pipeline proyek (build_chat_catalog.py):
- Harga valid 50rb-150jt; harga placeholder digit-berulang dibuang.
- Harga representatif per model = MEDIAN listing valid.
- Mayoritas listing bekas -> nama model diberi penanda '(bekas)'.
- Model lolos: >=2 listing, ATAU 1 listing Tokopedia Official Store.
- src selalu 'market'.
"""
import json
import re
import statistics
import sys
from collections import Counter, defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
IMPORT_DIR = HERE.parent
sys.path.insert(0, str(IMPORT_DIR))
from build_chat_catalog import (  # noqa: E402
    BROKEN_RE, PLACEHOLDER_PRICES, clean_title, norm_key)

SCRAPE = Path.home() / "workspace/scrape-20261021/psu_case_raw"
OUT_JSON = HERE / "psu_case_models.json"
OUT_REPORT = HERE / "LAPORAN.md"

PRICE_MIN, PRICE_MAX = 50_000, 150_000_000

# ---------------------------------------------------------------- gerbang
FULLPC_RE = re.compile(
    r"(ryzen|core\s?i\d|intel\s+core|pentium|athlon|xeon).{0,60}"
    r"(rtx|gtx|radeon|\brx\s?\d{3,4}|ram\s?\d+\s?gb|ssd|nvme|hdd)|"
    r"\bpc\s+(gaming|rakitan|office|kantor|kerja|editing|render|streaming)\b|"
    r"\brakitan\b.{0,30}(ryzen|intel|rtx|gtx)|"
    r"\bpc\s+1\s+set\b|\bkomputer\s+pc\b|\bthinkpad\b|\blaptop\b|"
    r"\bmonitor\s+\d|\bsekolah\b.{0,20}\bpc\b",
    re.I)
LOT_RE = re.compile(
    r"borongan|\blot\b|paket\s+\d|ambil\s+semua|harga\s+borong|"
    r"\d+\s*(pcs|unit)\b.{0,15}(fan|kipas|semua|borong)", re.I)
PHONE_RE = re.compile(
    r"casing\s+hp|case\s+hp|softcase|hardcase|\bkoper\b|iphone|samsung|"
    r"\boppo\b|\bvivo\b|redmi|xiaomi|realme|infinix|tas\s+laptop", re.I)

PSU_OFFCAT_RE = re.compile(
    r"\bups\b|stavolt|stabilizer|adaptor|charger|cctv|power\s+supply\s+12v|"
    r"psu\s+(ampli|tv|printer|led)|power\s+supply\s+(printer|led|cctv)", re.I)
PSU_ACCESSORY_RE = re.compile(
    r"kabel|sleeve|braket|bracket|fan\s+hub|tester|jumper|shroud|"
    r"cover\s+psu|dust\s+filter", re.I)
CASE_ACCESSORY_START_RE = re.compile(
    r"^\s*(fan|kipas|panel|kaca|tempered|dust|led\s+strip|riser|baut|mur|"
    r"standoff|tombol|switch\s+power|kaki\s+casing|roda|cover|bracket|"
    r"mounting|filter)\b", re.I)
CASE_ACCESSORY_RE = re.compile(
    r"glass\s+saja|panel\s+saja|kaca\s+saja|fan\s+casing|fan\s+case|"
    r"kipas\s+casing|kipas\s+case|led\s+strip|dust\s+filter|riser\s+cable|"
    r"vertical\s+gpu|baut\s+casing|tombol\s+power\s+casing", re.I)

WATT_RE = re.compile(r"(\d{3,4})\s?(w|watt)\b", re.I)
CASE_OFFCAT_RE = re.compile(
    r"liquid\s+cooling|aio\s+cooler|water\s+cooler|cpu\s+cooler|"
    r"air\s+cooler|heatsink", re.I)
SPEC_TOKENS = {"230v", "220v", "110v", "80plus", "12vhpwr", "240v"}
CASE_DISTINCTIVE = {
    "flow", "mesh", "glass", "rgb", "vision", "elite", "prime", "noir",
    "wood", "plus", "pro", "max", "mini", "air", "forge", "neo", "view",
    "stealth", "silent", "evo", "ultra",
}
CASE_BRAND_TOKENS = {
    "nzxt", "montech", "tecware", "deepcool", "corsair", "fractal",
    "phanteks", "thermaltake", "armaggeddon", "dazumba", "venomrx",
    "enlight", "simbadda", "raptor", "alcatroz", "imperion", "paradox",
    "nyk", "segotep", "xigmatek", "gamemax", "darkflash", "aigo",
    "jonsbo", "aerocool", "vurrion", "bulldozer", "invasion", "fantech",
    "rexus", "sades", "infinity", "gamen", "inforce", "lian", "lancool",
    "timber", "fusion",
}
PSU_TIER_RE = re.compile(
    r"80\s?\+|bronze|silver|\bgold\b|platinum|titanium|modular", re.I)
PSU_BRAND_RE = re.compile(
    r"corsair|seasonic|cooler\s?master|deepcool|msi|be\s?quiet|1stplayer|"
    r"aerocool|thermaltake|gigabyte|fsp|antec|evga|xigmatek|enermax|"
    r"silverstone|nzxt|asus|rog|super\s?flower|bitfenix|cougar|chieftec", re.I)
PSU_LOCAL_RE = re.compile(
    r"cube\s?gaming|armaggeddon|dazumba|varro|venomrx|infinity|enlight|"
    r"simbadda|raptor|imperion|paradox|ny k|nyk|segotep|gamemax|darkflash|"
    r"aigo|vurrion|bulldozer|power\s?up|micropack|eyota|vortex", re.I)
CASE_BRAND_RE = re.compile(
    r"nzxt|lian\s?li|lancool|montech|tecware|deepcool|cube\s?gaming|"
    r"corsair|fractal|phanteks|cooler\s?master|thermaltake|armaggeddon|"
    r"dazumba|venomrx|enlight|simbadda|raptor|alcatroz|imperion|paradox|"
    r"nyk|segotep|xigmatek|gamemax|darkflash|aigo|jonsbo|aerocool|"
    r"vurrion|bulldozer|invasion|prime|fantech|rexus|sades|digital\s+alliance|da\b", re.I)
FORM_FACTOR_RE = re.compile(r"\b(atx|m-?atx|matx|mini\s?-?\s?itx|e-?atx|micro\s?atx)\b", re.I)

GENERIC_KEY_WORDS = {
    "psu", "power", "supply", "powersupply", "pc", "komputer", "gaming",
    "casing", "case", "chassis", "tempered", "glass", "side", "panel",
    "hitam", "putih", "black", "white", "warna", "series", "edition",
}


def placeholder_price(p: int) -> bool:
    if p in PLACEHOLDER_PRICES:
        return True
    s = str(p)
    if len(s) >= 5 and len(set(s)) == 1:
        return True
    if re.fullmatch(r"(123)+|12|123|1234|1111|9999", s):
        return True
    if re.search(r"(.)\1{4,}$", s) and len(set(s)) <= 2:
        return True
    return False


def drop_reason(cat: str, title: str, price) -> str | None:
    if price is None or not (PRICE_MIN <= price <= PRICE_MAX):
        return "harga_tidak_valid"
    if placeholder_price(price):
        return "harga_placeholder"
    if BROKEN_RE.search(title):
        return "barang_rusak"
    if FULLPC_RE.search(title):
        return "pc_rakitan_bundle"
    if LOT_RE.search(title):
        return "lot_multi_item"
    if PHONE_RE.search(title):
        return "luar_kategori"
    if cat == "psu":
        if PSU_OFFCAT_RE.search(title):
            return "luar_kategori"
        if len({m.group(1) for m in WATT_RE.finditer(title)}) >= 2:
            return "varian_multi"
        if OTHER_COMP_RE.search(title) and not re.search(
                r"\bpsu\b|power\s+supply", title, re.I):
            return "luar_kategori"
        if PSU_ACCESSORY_RE.search(title) and not WATT_RE.search(title):
            return "aksesoris"
        if not (WATT_RE.search(title) or PSU_TIER_RE.search(title)
                or PSU_BRAND_RE.search(title) or PSU_LOCAL_RE.search(title)):
            return "judul_sampah"
    else:  # case
        if CASE_OFFCAT_RE.search(title) and not re.search(
                r"casing|\bcase\b|chassis", title, re.I):
            return "luar_kategori"
        if CASE_ACCESSORY_START_RE.search(title) or CASE_ACCESSORY_RE.search(title):
            return "aksesoris"
        if not (re.search(r"casing|\bcase\b", title, re.I)
                or CASE_BRAND_RE.search(title) or FORM_FACTOR_RE.search(title)):
            return "judul_sampah"
    name = clean_name(title)
    if len(name) < 10:
        return "judul_sampah"
    if cat == "psu" and not re.search(r"\d", name):
        return "judul_sampah"
    return None


INSTALLMENT_RE = re.compile(r"^\s*\d{1,2}\s*%\s*", re.I)
OTHER_COMP_RE = re.compile(
    r"\bgpu\b|\bvga\b|rtx|gtx|radeon|processor|motherboard|mainboard|"
    r"\bmobo\b|ram\s+ddr|ssd|nvme", re.I)
PSU_BRAND_TOKENS = {
    "corsair", "seasonic", "deepcool", "msi", "gigabyte", "fsp", "antec",
    "evga", "xigmatek", "enermax", "silverstone", "nzxt", "asus",
    "aerocool", "thermaltake", "segotep", "gamemax", "darkflash", "aigo",
}


def clean_name(title: str) -> str:
    """clean_title proyek + buang prefix cicilan Tokopedia ('15% ...')."""
    t = INSTALLMENT_RE.sub("", title or "")
    t = re.sub(r"\bcicilan\b", " ", t, flags=re.I)
    return clean_title(t)


def group_key(cat: str, name: str) -> str:
    # Samakan format watt: '650 Watt'/'650W' -> '650w'.
    n = WATT_RE.sub(lambda m: f"{m.group(1)}w", name.lower())
    tokens = re.findall(r"[a-z0-9]+", n)
    if cat == "psu":
        n = re.sub(r"([a-z]{1,3})-(\d{3,4})\b", r"\1\2", n)  # GX-650 -> GX650
        tokens = re.findall(r"[a-z0-9]+", n)
        watt = next((t for t in tokens if re.fullmatch(r"\d{3,4}w", t)), None)
        brand = next((t for t in tokens if t in PSU_BRAND_TOKENS
                      or t in ("cooler", "quiet", "1stplayer")), None)
        coded = [t for t in tokens if re.search(r"\d", t)
                 and t != watt and len(t) >= 3 and t not in SPEC_TOKENS
                 and not t.isdigit()]
        if watt and coded and any(
                c.endswith(watt[:-1]) for c in coded):
            # Watt tersirat di kode model (VS450 + '450W') -> samakan
            # dengan grup tanpa kata watt eksplisit.
            return " ".join(x for x in [brand] + coded[:2] if x)
        if watt and (brand or coded):
            return " ".join(x for x in [brand, watt] + coded[:2] if x)
        if coded:  # watt tersirat di kode model (CX650, P650SS, VS550)
            return " ".join(x for x in [brand] + coded[:2] if x)
    if cat == "case":
        tokens = ["nzxt" if t == "nxzt" else t for t in tokens]
        brand = next((t for t in tokens if t in CASE_BRAND_TOKENS), None)
        coded = sorted({t for t in tokens if re.search(r"\d", t)
                        and not t.isdigit()
                        and not re.fullmatch(r"\d+mm", t)})
        dist = sorted({t for t in tokens if t in CASE_DISTINCTIVE})
        if brand and (coded or dist):
            return " ".join([brand] + coded + dist)
    keep = [t for t in tokens if t not in GENERIC_KEY_WORDS]
    return "".join(keep) if keep else norm_key(name)


def load_rows():
    rows = []
    per_query = []
    qfiles = {"fb": "queries_psu_case.tsv", "toko": "queries_toko_psu_case.tsv"}
    for src, folder in (("facebook", "fb"), ("tokopedia", "toko")):
        qmap = {}
        qpath = SCRAPE.parent / qfiles[folder]
        if qpath.exists():
            for i, ln in enumerate(
                    qpath.read_text(encoding="utf-8").splitlines(), start=1):
                if ln.strip():
                    p = ln.split("\t")
                    qmap[i] = (p[0], p[1] if len(p) > 1 else "")
        files = sorted((SCRAPE / folder).glob("batch_*.jsonl"),
                       key=lambda f: int(re.search(r"\d+", f.stem).group()))
        for f in files:
            batch = []
            for ln in f.read_text(encoding="utf-8").splitlines():
                if ln.strip():
                    batch.append(json.loads(ln))
            idx = int(re.search(r"\d+", f.stem).group())
            q, cat = qmap.get(idx, (f.stem, ""))
            per_query.append((src, q, cat, len(batch)))
            rows.extend(batch)
    return rows, per_query


def main() -> None:
    rows, per_query = load_rows()
    raw_by_src = Counter(r["source"] for r in rows)
    raw_by_src_cat = Counter((r["source"], r["category"]) for r in rows)

    drops: dict[str, Counter] = {"psu": Counter(), "case": Counter()}
    groups: dict[str, dict[str, dict]] = {"psu": {}, "case": {}}
    kept = Counter()
    for r in rows:
        cat = r["category"]
        if cat not in groups:
            continue
        reason = drop_reason(cat, r["title"] or "", r.get("price_idr"))
        if reason:
            drops[cat][reason] += 1
            continue
        name = clean_name(r["title"])
        key = group_key(cat, name)
        g = groups[cat].setdefault(key, {
            "names": Counter(), "prices": [], "conds": Counter(),
            "official_single": False, "n_fb": 0, "n_toko": 0})
        g["names"][name] += 1
        g["prices"].append(int(r["price_idr"]))
        if r["source"] == "facebook":
            g["n_fb"] += 1
            cond = (r.get("condition_raw") or "").lower()
            g["conds"]["second" if cond.startswith("used") else "new"] += 1
        else:
            g["n_toko"] += 1
            g["conds"]["new"] += 1
            if r.get("is_official"):
                g["official_single"] = True
        kept[cat] += 1

    out: dict[str, list] = {}
    gugur = Counter()
    for cat, gmap in groups.items():
        models = []
        for g in gmap.values():
            n = len(g["prices"])
            if not (n >= 2 or (n == 1 and g["official_single"])):
                gugur[cat] += 1
                continue
            # Nama tampil: judul bersih paling sering muncul (seri -> terpendek).
            name = sorted(g["names"].items(), key=lambda kv: (-kv[1], len(kv[0])))[0][0]
            if g["conds"].get("second", 0) > g["conds"].get("new", 0):
                name += " (bekas)"
            models.append({
                "model": name,
                "price": int(statistics.median(g["prices"])),
                "src": "market",
                "_n": n, "_fb": g["n_fb"], "_toko": g["n_toko"],
            })
        models.sort(key=lambda m: m["price"])
        out[cat] = models

    payload = {
        cat: [{"model": m["model"], "price": m["price"], "src": m["src"]}
              for m in out[cat]]
        for cat in ("psu", "case")
    }
    OUT_JSON.write_text(json.dumps(payload, ensure_ascii=False, indent=1))

    # ---------------- LAPORAN.md ----------------
    L = ["# Panen PSU + Casing PC — Laporan Lokal", ""]
    L.append("Sumber: FB Marketplace (facebook-cli) + Tokopedia (Camoufox), "
             "dijadikan model ala build_chat_catalog.py. Semua lokal; "
             "belum masuk retail_catalog.json / Supabase.")
    L.append("")
    L.append("## Mentah per sumber")
    for src in ("facebook", "tokopedia"):
        L.append(f"- {src}: {raw_by_src[src]} baris "
                 f"(psu {raw_by_src_cat[(src, 'psu')]}, case {raw_by_src_cat[(src, 'case')]})")
    L.append("")
    L.append("## Mentah per kueri")
    L.append("| sumber | kategori | kueri | baris |")
    L.append("|---|---|---|---|")
    for src, q, cat, n in per_query:
        L.append(f"| {src} | {cat} | {q} | {n} |")
    for cat in ("psu", "case"):
        L.append("")
        L.append(f"## {cat.upper()} — saringan")
        L.append(f"- listing lolos saringan: {kept[cat]}")
        for reason, n in drops[cat].most_common():
            L.append(f"- gugur {reason}: {n}")
        L.append(f"- grup model gugur (<2 listing & bukan official tunggal): {gugur[cat]}")
        models = out[cat]
        L.append(f"- **model final: {len(models)}**")
        if models:
            L.append(f"- rentang harga: Rp{models[0]['price']:,} – Rp{models[-1]['price']:,}")
        L.append("")
        L.append(f"### 12 contoh model {cat} (termurah)")
        for m in models[:12]:
            L.append(f"- {m['model']} — Rp{m['price']:,} "
                     f"({m['_n']} listing: {m['_fb']} FB, {m['_toko']} Tokopedia)")
    OUT_REPORT.write_text("\n".join(L) + "\n", encoding="utf-8")

    print(f"mentah: {dict(raw_by_src)}")
    for cat in ("psu", "case"):
        ms = out[cat]
        print(f"{cat}: lolos {kept[cat]}, gugur {dict(drops[cat])}, "
              f"grup gugur {gugur[cat]}, MODEL FINAL {len(ms)}")
        if ms:
            print(f"  termurah: {ms[0]['model']} Rp{ms[0]['price']:,}")
            print(f"  termahal: {ms[-1]['model']} Rp{ms[-1]['price']:,}")


if __name__ == "__main__":
    main()
