#!/usr/bin/env python3
"""Normalisasi katalog berjalan -> DATASET PRODUK untuk etalase Cari Produk.

Satu baris per PRODUK (bukan per varian listing): nama dibersihkan jadi
nama produk rapi ("Colorful RTX 3050 6GB"), harga representatif =
harga katalog retail upload Dan bila ada varian yang norm-key-nya cocok
persis, selain itu MEDIAN harga semua varian.

Deterministik, tanpa network. Aturan per kategori:
- gpu/cpu/ram/motherboard: ekstraktor pola (merek + seri inti + pembeda)
- storage/laptop/pc + fallback: cleaner token generik

TAHAP REKLASIFIKASI (sebelum dedupe, di level item mentah): kategori sumber
kotor (part nyasar di 'laptop', komponen lepas di 'pc', dst), jadi produk
kepala dideteksi dari TANDA TANGAN nama mentah. Prioritas (yang menang
lebih dulu):
  0a. Frasa part laptop (baterai/charger/layar/... + 'laptop') -> DROP
  0b. Kata benda aksesori/part di luar taksonomi di kepala nama -> DROP
  1.  Kepala sistem utuh (token pertama pc/komputer, 'rakitan' + spek,
      fullset/1set) -> pc
  0c. Kepala monitor (+ pola inci) / line HP-tablet -> DROP
  2.  Kepala storage (SSD/HDD/NVMe di 3 token pertama / line storage
      dikenal di kepala) -> storage
  3.  Kepala laptop (line laptop dikenal di mana pun, atau token
      laptop/notebook di 3 token pertama) -> laptop
  4.  Kepala motherboard (kata Motherboard/Mainboard/Mobo, atau chipset
      board + merek board di kepala) -> motherboard
  5.  Pola chipset GPU di mana pun -> gpu
  6.  Pola CPU di mana pun -> cpu
  7.  Kepala RAM (SODIMM, token pertama ram/memory, seri modul dikenal,
      DDR + kapasitas) -> ram
  8.  Fallback longgar: kata benda storage/laptop/ram di mana pun ->
      kategori itu; selain itu PERTAHANKAN kategori sumber (tak menebak).
Item yang kepalanya di luar taksonomi (monitor, HP, baterai, charger,
layar, PSU, casing, aksesori) di-DROP dengan alasan tercatat.
Setelah pindah kategori, normalisasi nama + dedupe + lookup harga retail
berjalan di kategori BARU.

Input : assets/data/retail_catalog.json (katalog berjalan)
        ~/workspace/user/files/retail_catalog.json (retail asli, prioritas harga)
Output: assets/data/products_normalized.json
        assets/data/products_images_manifest.json (dibangun ulang: entri
        'ok' dipertahankan hanya bila id produk masih ada)
"""
import json
import re
import statistics
from collections import Counter
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CURRENT_PATH = REPO / "assets/data/retail_catalog.json"
UPLOAD_PATH = Path.home() / "workspace/user/files/retail_catalog.json"
OUT_PATH = REPO / "assets/data/products_normalized.json"
MANIFEST_PATH = REPO / "assets/data/products_images_manifest.json"
CAT_ORDER = ["gpu", "cpu", "motherboard", "ram", "storage", "pc", "laptop",
             "psu", "case"]

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


# ---------------------------------------------------------------------------
# Reklasifikasi: deteksi produk kepala dari tanda tangan nama mentah.
# Mengembalikan (kategori_baru, catatan); kategori None = DROP (alasan di
# catatan). Urutan prioritas sesuai docstring modul.
# ---------------------------------------------------------------------------
LAPTOP_LINES = [re.compile(p, re.I) for p in [
    r"aspire", r"ideapad", r"thinkpad", r"thinkbook", r"vivobook",
    r"zenbook", r"rog flow", r"rog zephyrus", r"\blegion\b",
    r"\bloq\b", r"\bkatana\b",
    r"thin gf", r"\bcyborg\b", r"macbook", r"elitebook", r"probook",
    r"pavilion", r"inspiron", r"latitude", r"vostro", r"\bswift\b",
    r"\benvy\b", r"\bomen\b", r"victus", r"galaxy book", r"\bavita\b",
    r"tecra", r"portege", r"chromebook",
    r"msi\s+(modern|stealth|prestige|creator|thin|katana|cyborg)",
    r"\bhp\s?\d{2}s\b",  # HP 14s / 15s dst
    r"\bgf\d{2}\b",  # MSI GF63/GF65/GF76 (line laptop thin gaming)
    r"lenovo\s?k1[24]\b",  # Lenovo K14 (laptop bisnis)
]]
# Kepala komponen eksplisit: judul diawali kata ini = komponen tunggal,
# jangan ditelan aturan sistem utuh ("VGA Komputer RTX...", "RAM PC GAMING").
COMPONENT_HEADS = {"vga", "ram", "memory", "memori", "ssd", "hdd", "nvme",
                   "processor", "prosesor", "motherboard", "mainboard",
                   "mobo"}
CPU_LOOSE = re.compile(r"\bi[3579][\s-]?\d{4,5}[a-z]{0,2}\b|"
                       r"\bryzen\s?[3579]\b", re.I)
# Line ambigu: juga dipakai GPU/board/SSD (ROG Strix & TUF = AIB ASUS,
# Nitro = Sapphire GPU, Predator = SSD Acer). Hanya jadi laptop bila ada
# bukti laptop pendamping (token laptop/notebook, ukuran layar, kode model
# laptop, atau CPU mobile).
LAPTOP_LINES_AMBIG = [re.compile(p, re.I) for p in [
    r"rog strix", r"\btuf\b", r"\bnitro\b", r"predator",
]]
LAPTOP_EVIDENCE = re.compile(
    r"\blaptop\b|\bnotebook\b|\d{2}(\.\d)?\s?(inch|inci|\")|"
    r"\b(f1[57]|a1[57]|fx5\d\d|fa5\d\d|an5\d\d|anv1[57]|ph3\d\d|"
    r"g51\d|g71\d)\b|\b\d{4,5}(h|hx|hs)\b", re.I)
# Line laptop KUAT (audit arah sebaliknya): laptop utuh yang nyasar di
# kategori komponen lolos kemarin karena polanya tak dikenal (MSI
# "GAMING Thin" disela kata, ASUS "Gaming K16", Acer Nitro, kode model
# TUF FA/FX yang menyatu dgn suffix huruf). Pola ini menang atas kepala
# komponen. Kode TUF wajib ekor huruf opsional: \b sesudah digit gagal
# ("FA506NCQ", "FX505DY" satu token). Sapphire NITRO+ (GPU/mobo) aman:
# pola nitro menuntut spasi + angka seri laptop, bukan '+'.
LAPTOP_LINES_STRONG = [re.compile(p, re.I) for p in [
    r"msi\s+gaming\s+thin", r"asus\s+gaming\s+k\d",
    r"acer\s+nitro", r"\bnitro\s+(5|v\s?\d|an\d)",
    r"axioo\s+(hype|pongo)",
    r"ideapad", r"vivobook", r"zenbook", r"thinkpad", r"thinkbook",
    r"macbook", r"expertbook",
]]
TUF_LAPTOP_CODE = re.compile(r"\b(?:fa|fx)5\d{2}[a-z]{0,3}\b", re.I)
TUF_LAPTOP_CODE2 = re.compile(r"\b[fa]1[57]\b", re.I)
# Legion/LOQ ambigu (Legion juga seri SSD Lenovo): wajib bukti laptop
# pendamping (token laptop, layar, CPU mobile, refresh rate).
LAPTOP_LINES_GATED = [re.compile(p, re.I) for p in [r"\blegion\b", r"\bloq\b"]]
LAPTOP_EVIDENCE2 = re.compile(
    r"\blaptop\b|\bnotebook\b|\d{2}(\.\d)?\s?(inch|inci|\")|"
    r"\b\d{3,5}(h|hx|hs)\b|\d{2,3}\s?hz\b", re.I)
COMPONENT_CATS = ("gpu", "cpu", "motherboard", "ram", "storage")


def strong_laptop_line(low: str, tok: list[str]) -> bool:
    if any(p.search(low) for p in LAPTOP_LINES_STRONG):
        return True
    if ("tuf" in tok or "asus" in tok) and (
            TUF_LAPTOP_CODE.search(low) or TUF_LAPTOP_CODE2.search(low)):
        return True
    if any(p.search(low) for p in LAPTOP_LINES_GATED) and \
            LAPTOP_EVIDENCE2.search(low):
        return True
    return False


# Harga typo/placeholder penjual (pola angka asal ketik): item dibuang,
# bukan dipindah. Juga dipakai gerbang convert_retail_upload.py.
PLACEHOLDER_PRICES = {1111111, 2323232, 77752777, 123123, 1231234,
                      123456, 999999, 111111, 222222, 1234567}


def is_placeholder_price(price: int) -> bool:
    s = str(price)
    return price in PLACEHOLDER_PRICES \
        or re.fullmatch(r"(\d)\1{5,}", s) is not None \
        or re.fullmatch(r"(123)+|(1234)+", s) is not None
# Model GPU Intel Arc yg tabrakan dgn pola chipset board (A380, B580, ...)
ARC_MODELS = {"a310", "a380", "a580", "a750", "a770", "b570", "b580"}
STORAGE_LINES = [re.compile(p, re.I) for p in [
    r"exceria", r"barracuda", r"firecuda", r"ironwolf",
    r"\b(970|980|990)\s?(evo|pro|plus)\b", r"\bsn\s?(5|7)\d{2}\b",
    r"\bnv[123]\b", r"legend\s?\d", r"\b(mx500|bx500|su650|su800|su630)\b",
    r"\bkc(600|2500|3000)\b", r"\ba2000\b", r"\bp[345]\s?(plus|pro)?\b.*ssd",
]]
MODULE_SERIES = re.compile(
    r"vengeance|trident|ripjaws|ballistix|dominator|\bfury\b|t-?force|"
    r"gammix|lancer|tsunami|viper|night\s?hawk|delta\s?rgb", re.I)
PHONE_LINES = [re.compile(p, re.I) for p in [
    r"iphone", r"galaxy\s?[a-z]\d", r"redmi", r"\bpoco\s?[a-z]?\d",
    r"oppo\s?(a\d|reno|find)", r"realme\s?\d", r"infinix",
    r"\bvivo\s?[vy]\d", r"samsung\s?galaxy",
]]
PART_LAPTOP_PHRASE = re.compile(
    r"\b(layar|lcd|baterai|battery|charger|adaptor|adapter|keyboard|"
    r"engsel|flexible)\b.{0,25}\b(laptop|notebook)\b", re.I)
ACCESSORY_HEAD = {
    "baterai", "battery", "charger", "adaptor", "adapter", "keyboard",
    "mouse", "headset", "earphone", "speaker", "webcam", "kabel", "cable",
    "hub", "dock", "docking", "enclosure", "casing", "case", "tas",
    "kipas", "fan", "stand", "psu", "printer", "layar", "lcd", "engsel",
}
STORAGE_NOUNS = {"ssd", "hdd", "nvme", "harddisk", "hardisk"}
BOARD_BRANDS = AIB_GPU | {"jetway", "ecs"}


def _head_tokens(raw: str) -> list[str]:
    t = strip_segments(raw.lower())
    t = re.sub(r"^\s*\d+\s?%\s*", " ", t)  # diskon di depan judul
    return [x for x in re.split(r"[^a-z0-9.\"]+", t) if x]


def reclassify(raw: str, source_cat: str) -> tuple[str | None, str]:
    # Kategori baru psu/case: sumbernya sudah bersih & mesin taksonomi di
    # bawah justru mengenal psu/casing sebagai "di luar taksonomi" (DROP)
    # — jangan disentuh sama sekali, pertahankan kategori sumber.
    if source_cat in ("psu", "case"):
        return source_cat, "kategori psu/case: tetap"
    low = strip_segments(raw.lower())
    tok = _head_tokens(raw)
    head3 = set(tok[:3])

    # 0a. Frasa part laptop (part kuat + 'laptop'), kecuali line laptop utuh
    if PART_LAPTOP_PHRASE.search(low) and \
            not any(p.search(low) for p in LAPTOP_LINES):
        return None, "part laptop di luar taksonomi"
    # 0b. Aksesori/part di luar taksonomi sebagai kepala nama
    if tok and tok[0] in ACCESSORY_HEAD:
        return None, "aksesori/part di luar taksonomi (kepala nama)"
    if "power supply" in " ".join(tok[:3]):
        return None, "psu di luar taksonomi"
    # SODIMM tak ambigu: selalu modul RAM ("PC & Sodimm PLATINUM DDR5").
    if "sodimm" in low or "so-dimm" in low:
        return "ram", "sodimm (modul laptop tetap ram)"
    # 1. Kepala sistem utuh -> pc
    if tok and tok[0] in ("pc", "komputer"):
        return "pc", "kepala sistem utuh"
    cpu_hit = clean_cpu(raw) or CPU_LOOSE.search(low)
    sys_evidence = cpu_hit or clean_gpu(raw) or "rakitan" in tok \
        or "aio" in tok or ("ram" in tok
                            and any(t in STORAGE_NOUNS for t in tok))
    if not (tok and tok[0] in COMPONENT_HEADS):
        if re.search(r"\bpc\s+gaming\b|\bgaming\s+pc\b", low):
            return "pc", "frasa pc gaming/gaming pc"
        if ("pc" in tok[:4] or "komputer" in tok[:4]) and sys_evidence:
            return "pc", "token pc awal + bukti sistem"
        if "pc" in tok and cpu_hit and clean_gpu(raw):
            return "pc", "cpu+gpu disebut bersama (sistem)"
    if "rakitan" in tok and (clean_cpu(raw) or clean_gpu(raw)
                             or "ram" in tok or "ssd" in tok):
        return "pc", "rakitan + spek sistem"
    joined = " ".join(tok)
    # 'fullset' saja ambigu (GPU "fullset" = paket lengkap); wajib ada
    # bukti sistem: token pc/komputer atau pola CPU.
    if ("fullset" in joined or "1set" in joined.replace(" ", "")
            or "satu set" in joined) and \
            ("pc" in tok or "komputer" in tok or clean_cpu(raw)):
        return "pc", "paket sistem utuh"
    if tok and tok[0] == "cpu" and ("rakitan" in tok or "gaming" in tok):
        return "pc", "'cpu' = sebutan tower rakitan"
    # Line laptop KUAT dihitung sekali: menang atas kepala komponen,
    # kecuali kepala nama jelas part tunggal (SSD/RAM/... di token
    # pertama = part beneran, mis. "SSD ... Thinkpad" tetap storage).
    strong_hit = bool(tok) \
        and (tok[0] not in COMPONENT_HEADS | STORAGE_NOUNS) \
        and strong_laptop_line(low, tok)
    # 1b. Di kategori komponen -> laptop sekarang (sebelum kepala
    # storage); dari sumber lain, strong_hit dipakai lagi di langkah 3
    # agar item tidak osilasi balik ke komponen.
    if source_cat in COMPONENT_CATS and strong_hit:
        return "laptop", "line laptop kuat di kategori komponen"
    # 0c. Monitor / HP-tablet sebagai kepala -> drop
    if ("monitor" in tok[:4] and re.search(r"\d{2}(\.\d)?\s?(inch|inci|\")", low)) \
            or (tok and tok[0] == "monitor"):
        return None, "monitor di luar taksonomi"
    if any(p.search(" ".join(tok[:5])) for p in PHONE_LINES):
        return None, "hp/tablet di luar taksonomi"
    # Line laptop dihitung duluan: kata benda storage di token 3-4 kalah
    # olehnya ("Thinkpad X13 G3 SSD NVME ..." = laptop), tapi storage di
    # token 1-2 tetap kepala ("SSD NVMe ... Copotan Laptop" = part).
    line_hit = any(p.search(low) for p in LAPTOP_LINES)
    if line_hit and "xfx" in tok and clean_gpu(raw) is not None:
        line_hit = False  # XFX "Swift" = line GPU, bukan Acer Swift
    if not line_hit and any(p.search(low) for p in LAPTOP_LINES_AMBIG) \
            and LAPTOP_EVIDENCE.search(low):
        line_hit = True
    if not line_hit and re.search(r"\b(a1[57]|f1[57]|fa5\d\d|fx5\d\d)\b",
                                  low) \
            and re.search(r"\b\d{4,5}(h|hx|hs)\b", low):
        line_hit = True
    # 2. Kepala storage
    head4 = set(tok[:4])
    if head3 & STORAGE_NOUNS or "solid state" in low[:40] \
            or "hard disk" in low[:40] or (
            head4 & STORAGE_NOUNS and not head4 & {"laptop", "notebook"}
            and not line_hit):
        return "storage", "kata benda storage di kepala"
    if any(p.search(" ".join(tok[:5])) for p in STORAGE_LINES):
        return "storage", "line storage dikenal di kepala"
    # 3. Kepala laptop
    if line_hit or strong_hit:
        return "laptop", "line laptop dikenal"
    if head3 & {"laptop", "notebook"}:
        return "laptop", "token laptop di kepala"
    # 4. Kepala motherboard
    if any(w in tok for w in ("motherboard", "mainboard", "mobo")):
        return "motherboard", "kata motherboard eksplisit"
    mb = clean_motherboard(raw)
    if mb is not None:
        chip = next((t for t in tok if re.fullmatch(
            r"(a|b|h|x|z|trx|wrx)\d{2,3}[a-z]{0,2}", t)), None)
        brand_head = any(t in BOARD_BRANDS for t in tok[:4])
        # Token 'chipset' yg menempel core GPU (Arc B60, RTX A400, ...)
        # adalah model GPU, bukan chipset board.
        prev = tok[tok.index(chip) - 1] if chip is not None \
            and tok.index(chip) > 0 else None
        gpu_model = chip in ARC_MODELS or prev in (
            "arc", "rtx", "gtx", "rx", "quadro") or "arc" in tok[:5]
        if not gpu_model and \
                (brand_head or (chip is not None and tok.index(chip) <= 3)):
            return "motherboard", "chipset board + merek board"
    # 5/6. Pola GPU / CPU di mana pun
    if clean_gpu(raw) is not None:
        return "gpu", "pola chipset gpu"
    if clean_cpu(raw) is not None:
        return "cpu", "pola cpu"
    # 6.5. Storage tanpa kata benda eksplisit: kapasitas TB + PCIe/M.2,
    # atau PCIe + kecepatan MB/s (SSD GAMMIX S70, T-Force G50, ...).
    if (re.search(r"\d+(\.\d+)?\s?tb\b", low)
            and ("pcie" in tok or "m.2" in low or "nvme" in tok)) \
            or ("pcie" in tok and re.search(r"\d+\s?mb/s", low)):
        return "storage", "tanda tangan tb+pcie / pcie+mb/s"
    # 7. Kepala RAM
    if tok and tok[0] in ("ram", "memory", "memori"):
        return "ram", "token ram di kepala"
    # SSD berseri RAM (ADATA GAMMIX S70, Kingston Fury Renegade NVMe,
    # Viper VP4000, T-Force G50): kata benda storage di mana pun menang
    # atas seri modul.
    if any(t in STORAGE_NOUNS for t in tok):
        return "storage", "kata benda storage (seri modul tumpang tindih)"
    if MODULE_SERIES.search(low):
        return "ram", "seri modul ram dikenal"
    if re.search(r"ddr\s?[345]\b", low) and re.search(r"\d{1,3}\s?gb\b", low):
        return "ram", "ddr + kapasitas modul"
    # 8. Fallback longgar
    if any(t in STORAGE_NOUNS for t in tok):
        return "storage", "fallback: kata benda storage"
    if "laptop" in tok or "notebook" in tok:
        return "laptop", "fallback: token laptop"
    if "ram" in tok or re.search(r"ddr\s?[345]\b", low):
        return "ram", "fallback: token ram/ddr"
    return source_cat, "tetap (kepala tak terdeteksi)"


def qa_scan(products: list[dict]) -> list[str]:
    """Scan nama ternormalisasi per kategori; kembalikan daftar pelanggaran."""
    viol: list[str] = []
    sys_markers = {"pc", "komputer", "rakitan", "paket", "fullset",
                   "fullsett", "set", "1set"}
    for p in products:
        name, cat = p["name"], p["category"]
        low = name.lower()
        tk = low.split()
        if cat == "laptop" and tk and tk[0].strip(".,") in (
                "ssd", "ram", "nvme", "hdd"):
            viol.append(f"laptop berkepala part: {name}")
        if cat == "storage" and any(lp.search(low) for lp in LAPTOP_LINES):
            viol.append(f"storage berisi line laptop: {name}")
        # Komponen MURNI di pc: seluruh nama = satu nama komponen persis,
        # atau nama pendek (<=4 token) berpola gpu/cpu TUNGGAL, tanpa
        # penanda sistem apa pun.
        if cat == "pc" and not sys_markers.intersection(tk):
            exact = clean_gpu(name) == name or clean_cpu(name) == name
            single = len(tk) <= 4 and \
                (clean_gpu(name) is None) != (clean_cpu(name) is None)
            if exact or single:
                viol.append(f"pc berisi komponen murni: {name}")
        if cat in ("gpu", "cpu", "motherboard", "ram", "storage") \
                and tk and tk[0] == "laptop":
            viol.append(f"komponen berkepala laptop: {name} [{cat}]")
        if cat in COMPONENT_CATS and strong_laptop_line(low, tk):
            viol.append(f"komponen berisi line laptop kuat: {name} [{cat}]")
    return viol


def rebuild_manifest(products: list[dict]) -> tuple[int, int, list[str]]:
    """Pertahankan entri 'ok' hanya utk id yg masih ada; sisanya fallback."""
    old: dict = {}
    if MANIFEST_PATH.exists():
        old = json.loads(MANIFEST_PATH.read_text())
    old_ok = {pid for pid, e in old.items()
              if isinstance(e, dict) and e.get("status") == "ok"}
    new_ids = {p["id"] for p in products}
    manifest: dict[str, dict] = {}
    for p in sorted(products, key=lambda x: x["id"]):
        pid = p["id"]
        manifest[pid] = old[pid] if pid in old_ok \
            else {"status": "fallback-category"}
    MANIFEST_PATH.write_text(json.dumps(manifest, ensure_ascii=False,
                                        separators=(",", ":")))
    kept = len(old_ok & new_ids)
    return len(old_ok), kept, sorted(old_ok - new_ids)


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
    moves: Counter = Counter()
    drop_reasons: Counter = Counter()
    dropped_examples: list[tuple[str, str, str]] = []
    moved_examples: list[tuple[str, str, str]] = []
    price_drops: list[tuple[str, str, int]] = []
    strong_viol: list[tuple[str, str, str]] = []
    for cat in CAT_ORDER:
        items = current.get(cat)
        if not isinstance(items, list):
            continue
        raw_counts[cat] = len(items)
        for it in items:
            raw_name, price = str(it["model"]), int(it["price"])
            if is_placeholder_price(price):
                dropped += 1
                price_drops.append((raw_name, cat, price))
                continue
            new_cat, note = reclassify(raw_name, cat)
            if cat in COMPONENT_CATS and new_cat not in (None, "laptop") \
                    and strong_laptop_line(strip_segments(raw_name.lower()),
                                           _head_tokens(raw_name)):
                strong_viol.append((raw_name, cat, new_cat))
            if new_cat is None:
                dropped += 1
                drop_reasons[note] += 1
                if len(dropped_examples) < 8:
                    dropped_examples.append((raw_name, cat, note))
                continue
            if new_cat != cat:
                moves[(cat, new_cat)] += 1
                if len(moved_examples) < 10:
                    moved_examples.append((raw_name, cat, new_cat))
            clean = clean_name(raw_name, new_cat)
            if clean is None:
                dropped += 1
                continue
            key = (new_cat, clean.lower())
            g = groups.setdefault(key, {"name": clean, "prices": [],
                                        "retail": None, "sample_raw": raw_name})
            g["prices"].append(price)
            if g["retail"] is None:
                rp = retail_idx.get(new_cat, {}).get(norm_key(raw_name))
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
    print("MATRIKS PINDAH (dari->ke):")
    for (a, b), n in sorted(moves.items()):
        print(f"  {a} -> {b}: {n}")
    print(f"DROP per alasan: {dict(drop_reasons)}")
    for raw_name, frm, note in dropped_examples:
        print(f"  DROP [{frm}] ({note}): {raw_name[:80]}")
    print("CONTOH PINDAH:")
    for raw_name, frm, to in moved_examples:
        print(f"  [{frm}->{to}] {raw_name[:80]}")
    print(f"DROP HARGA PLACEHOLDER: {len(price_drops)}")
    for raw_name, cat, price in price_drops:
        print(f"  DROP-HARGA [{cat}] Rp{price:,}: {raw_name[:80]}")
    viol = qa_scan(products)
    print(f"QA: {len(viol)} pelanggaran (+{len(strong_viol)} mentah "
          f"line-kuat lolos)")
    for v in viol[:15]:
        print(f"  QA! {v}")
    for raw_name, cat, new_cat in strong_viol[:10]:
        print(f"  QA-MENTAH! [{cat}->{new_cat}] {raw_name[:80]}")
    old_ok, kept, lost = rebuild_manifest(products)
    print(f"MANIFEST: id 'ok' lama {old_ok} -> bertahan {kept}, "
          f"hilang {len(lost)}")
    for pid in lost:
        print(f"  HILANG: {pid}")
    top = sorted(products, key=lambda p: -p["variants"])[:5]
    print("TOP dedupe:")
    for p in top:
        print(f"  {p['name']} [{p['category']}] variants={p['variants']} "
              f"rentang {p['price_min']}-{p['price_max']} -> Rp{p['price']:,}")


if __name__ == "__main__":
    main()
