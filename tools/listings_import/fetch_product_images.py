#!/usr/bin/env python3
"""Unduh gambar produk (fase 1: GPU + CPU teratas by variants), konversi WebP,
susun manifest. Resumable: produk dgn status ok/fallback-chipset + file utuh
dilewati. Manifest ditulis inkremental tiap 25 produk diproses.

Sumber gambar: CLI /opt/hatch/bin/image-search (media_url diutamakan).
"""
import json
import re
import subprocess
import sys
import time
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
PRODUCTS_JSON = ROOT / "assets/data/products_normalized.json"
MANIFEST_JSON = ROOT / "assets/data/products_images_manifest.json"
OUT_DIR = ROOT / "product_images/products"
SEARCH_CLI = "/opt/hatch/bin/image-search"

TARGETS = {"gpu": 120, "cpu": 80}  # kategori -> jumlah teratas by variants
HELPER = {"gpu": "graphics card", "cpu": "processor"}
MAX_SIDE = 640
MIN_SIDE = 300
WEBP_Q = 78
UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"


def core_name(p):
    """Nama chipset/model inti utk query fallback."""
    name = p["name"]
    if p["category"] == "gpu":
        m = re.search(
            r"(RTX|GTX|RX|GT|Arc)\s*[A-Z]?\d{3,4}\s*(Ti Super|Ti|Super|XTX|XT|GRE)?",
            name, re.I)
        if m:
            return re.sub(r"\s+", " ", m.group(0)).title().replace("Rtx", "RTX") \
                .replace("Gtx", "GTX").replace("Rx", "RX")
    parts = name.split()
    return " ".join(parts[1:]) if len(parts) > 2 else name


def search_images(query):
    try:
        out = subprocess.run([SEARCH_CLI, query, "--max-results", "5"],
                             capture_output=True, text=True, timeout=60)
        results = json.loads(out.stdout).get("results", [])
    except Exception:
        return []
    urls = []
    for r in results:
        for key in ("media_url", "thumbnail_cdn_url"):
            u = r.get(key)
            if u and u.startswith("http") and u not in urls:
                urls.append(u)
    return urls


def try_download(url, dest_webp):
    """Unduh -> validasi PIL -> konversi WebP. True bila sukses."""
    tmp = dest_webp.with_suffix(".tmp")
    try:
        r = subprocess.run(
            ["curl", "-fsSL", "--connect-timeout", "10", "--max-time", "45",
             "-A", UA, "-H", "Accept: image/png,image/jpeg,image/gif,image/webp,image/*;q=0.5",
             "-H", "Referer: https://www.google.com/", "-o", str(tmp), url],
            capture_output=True, timeout=60)
        if r.returncode != 0:
            return False
        with Image.open(tmp) as im:
            im.load()
            if min(im.size) < MIN_SIDE:
                return False
            im = im.convert("RGB")
            im.thumbnail((MAX_SIDE, MAX_SIDE))
            im.save(dest_webp, "WEBP", quality=WEBP_Q)
        return dest_webp.exists() and dest_webp.stat().st_size > 0
    except Exception:
        return False
    finally:
        tmp.unlink(missing_ok=True)


def save_manifest(m):
    MANIFEST_JSON.write_text(json.dumps(m, indent=1, ensure_ascii=False))


def main():
    products = json.loads(PRODUCTS_JSON.read_text())["products"]
    manifest = {}
    if MANIFEST_JSON.exists():
        manifest = json.loads(MANIFEST_JSON.read_text())
    for p in products:  # semua produk punya entri; default fallback-category
        manifest.setdefault(p["id"], {"status": "fallback-category"})

    targets = []
    for cat, n in TARGETS.items():
        top = sorted((p for p in products if p["category"] == cat),
                     key=lambda p: (-p.get("variants", 0), p["name"]))[:n]
        targets.extend(top)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    done = 0
    for p in targets:
        ent = manifest[p["id"]]
        dest = OUT_DIR / f"{p['id']}.webp"
        if ent.get("status") in ("ok", "fallback-chipset") and dest.exists():
            continue  # resumable
        status, src = "fallback-category", None
        for qi, q in enumerate((f"{p['name']} {HELPER[p['category']]}",
                                f"{core_name(p)} {HELPER[p['category']]}")):
            if qi == 1 and core_name(p) == p["name"]:
                break
            for url in search_images(q):
                if try_download(url, dest):
                    status = "ok" if qi == 0 else "fallback-chipset"
                    src = url
                    break
            if src:
                break
            time.sleep(0.2)
        ent = {"status": status}
        if src:
            ent["file"] = f"products/{p['id']}.webp"
            ent["source"] = src
        manifest[p["id"]] = ent
        done += 1
        print(f"[{done}] {p['category']} {p['name']} -> {status}", flush=True)
        if done % 25 == 0:
            save_manifest(manifest)
    save_manifest(manifest)
    print(f"SELESAI: {done} produk diproses")


if __name__ == "__main__":
    sys.exit(main())
