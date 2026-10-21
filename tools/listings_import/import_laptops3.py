#!/usr/bin/env python3
"""Fase 2 via curl (urllib putus-putus lewat proxy VM ini).

Upsert 626 baris laptop (ambil id+hash), lalu POST laptop_units.
Key service_role dari stdin -> file config curl /tmp (chmod 600, dihapus
di akhir). Retry per panggilan.
"""
import csv
import json
import os
import subprocess
import sys
import time
from pathlib import Path

BASE = Path(__file__).parent
API = "https://kvubnpujxiiqhpcrzlso.supabase.co/rest/v1"
CFG = Path("/tmp/.curl_supa_cfg")
BODY = Path("/tmp/.curl_supa_body.json")


def rows(name):
    with open(BASE / name, encoding="utf-8") as f:
        for r in csv.DictReader(f):
            yield {k: (v if v != "" else None) for k, v in r.items()}


def call(method, path, body=None, prefer=None, tries=6):
    args = ["curl", "-sS", "--max-time", "120", "-K", str(CFG),
            "-X", method, API + path, "-w", "\n%{http_code}"]
    if prefer:
        args += ["-H", f"Prefer: {prefer}"]
    if body is not None:
        BODY.write_text(json.dumps(body))
        args += ["-H", "Content-Type: application/json",
                 "--data-binary", f"@{BODY}"]
    last = ""
    for a in range(tries):
        p = subprocess.run(args, capture_output=True, text=True)
        out = p.stdout
        if p.returncode == 0 and "\n" in out:
            payload, _, code = out.rpartition("\n")
            if code in ("200", "201", "204"):
                return payload
            last = f"HTTP {code}: {payload[:200]}"
        else:
            last = f"curl rc={p.returncode}: {p.stderr[:200]}"
        print(f"  retry {a + 1}/{tries} {method} {path[:50]}... {last}")
        time.sleep(2 * (a + 1))
    sys.exit(f"gagal total {method} {path}: {last}")


def main() -> None:
    key = sys.stdin.read().strip()
    CFG.write_text(
        f'header = "apikey: {key}"\nheader = "Authorization: Bearer {key}"\n'
    )
    os.chmod(CFG, 0o600)
    try:
        laptop_listings = []
        for r in rows("listings_clean.csv"):
            if r["category"] != "laptop":
                continue
            r["raw_price"] = int(r["raw_price"])
            for d in ("is_official_store", "sold_count", "rating"):
                r.pop(d, None)
            laptop_listings.append(r)
        print(f"baris laptop: {len(laptop_listings)}")
        id_by_hash = {}
        for i in range(0, len(laptop_listings), 100):
            payload = call(
                "POST",
                "/raw_listings?on_conflict=listing_hash&select=id,listing_hash",
                body=laptop_listings[i : i + 100],
                prefer="resolution=merge-duplicates,return=representation",
            )
            for p in json.loads(payload):
                id_by_hash[p["listing_hash"]] = p["id"]
            print(f"peta id: {len(id_by_hash)}")
        laptops = []
        for r in rows("laptop_units_clean.csv"):
            rid = id_by_hash.get(r["listing_hash"])
            if rid is None:
                continue
            laptops.append({
                "raw_listing_id": rid,
                "brand": r["brand"], "model": r["model"], "cpu": r["cpu"],
                "gpu": r["gpu"],
                "ram_gb": int(r["ram_gb"]) if r["ram_gb"] else None,
                "storage_gb": int(r["storage_gb"]) if r["storage_gb"] else None,
                "screen_size": None,
                "price": int(r["price"]), "condition": r["condition"],
                "source": r["source"], "listing_url": r["listing_url"],
                "scraped_at": r["scraped_at"],
            })
        print(f"laptop_units siap: {len(laptops)}")
        for i in range(0, len(laptops), 200):
            call("POST", "/laptop_units", body=laptops[i : i + 200],
                 prefer="return=minimal")
            print(f"laptop_units terkirim: {min(i + 200, len(laptops))}/{len(laptops)}")
        hdr = Path("/tmp/.curl_supa_hdr")
        args = ["curl", "-sS", "--max-time", "60", "-K", str(CFG),
                "-H", "Prefer: count=exact", "-H", "Range: 0-0",
                "-D", str(hdr), "-o", "/dev/null",
                API + "/laptop_units?select=id"]
        subprocess.run(args, check=True)
        cr = [ln for ln in hdr.read_text().splitlines()
              if ln.lower().startswith("content-range")]
        print("VERIFIKASI laptop_units total:",
              cr[0].split("/")[-1].strip() if cr else "?")
        hdr.unlink(missing_ok=True)
    finally:
        CFG.unlink(missing_ok=True)
        BODY.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
