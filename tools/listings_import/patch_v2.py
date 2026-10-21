#!/usr/bin/env python3
"""Patch DB v1 -> v2: upsert baris yang kategorinya berubah +
insert laptop_units baru. Transport curl. Key dari stdin."""
import csv
import json
import os
import subprocess
import sys
import time
from pathlib import Path

BASE = Path(__file__).parent
API = "https://kvubnpujxiiqhpcrzlso.supabase.co/rest/v1"
CFG = Path("/tmp/.curl_supa_cfg2")
BODY = Path("/tmp/.curl_supa_body2.json")


def load(name):
    with open(BASE / name, encoding="utf-8") as f:
        return {r["listing_hash"]: {k: (v if v != "" else None) for k, v in r.items()}
                for r in csv.DictReader(f)}


def call(method, path, body=None, prefer=None, tries=6):
    args = ["curl", "-sS", "--max-time", "120", "-K", str(CFG),
            "-X", method, API + path, "-w", "\n%{http_code}"]
    if prefer:
        args += ["-H", f"Prefer: {prefer}"]
    if body is not None:
        BODY.write_text(json.dumps(body))
        args += ["-H", "Content-Type: application/json", "--data-binary", f"@{BODY}"]
    last = ""
    for a in range(tries):
        p = subprocess.run(args, capture_output=True, text=True)
        if p.returncode == 0 and "\n" in p.stdout:
            payload, _, code = p.stdout.rpartition("\n")
            if code in ("200", "201", "204"):
                return payload
            last = f"HTTP {code}: {payload[:200]}"
        else:
            last = f"curl rc={p.returncode}: {p.stderr[:150]}"
        print(f"  retry {a + 1}/{tries} {method} {path[:40]}... {last}")
        time.sleep(2 * (a + 1))
    sys.exit(f"gagal: {method} {path}: {last}")


def main() -> None:
    key = sys.stdin.read().strip()
    CFG.write_text(f'header = "apikey: {key}"\nheader = "Authorization: Bearer {key}"\n')
    os.chmod(CFG, 0o600)
    try:
        v1 = load("listings_clean_v1.csv")
        v2 = load("listings_clean.csv")
        changed = []
        for h, r in v2.items():
            if h in v1 and v1[h]["category"] != r["category"]:
                r = dict(r)
                r["raw_price"] = int(r["raw_price"])
                for d in ("is_official_store", "sold_count", "rating"):
                    r.pop(d, None)
                changed.append(r)
        print(f"baris berubah kategori: {len(changed)}")
        id_by_hash = {}
        for i in range(0, len(changed), 100):
            payload = call(
                "POST",
                "/raw_listings?on_conflict=listing_hash&select=id,listing_hash",
                body=changed[i : i + 100],
                prefer="resolution=merge-duplicates,return=representation",
            )
            for p in json.loads(payload):
                id_by_hash[p["listing_hash"]] = p["id"]
        print(f"upsert ok, peta id: {len(id_by_hash)}")

        v1_laptops = {h for h, r in load("laptop_units_clean_v1.csv").items()}
        new_laptops = []
        for h, r in load("laptop_units_clean.csv").items():
            if h in v1_laptops:
                continue
            rid = id_by_hash.get(h)
            if rid is None:
                print("  ! id tak ditemukan untuk", h[:12])
                continue
            new_laptops.append({
                "raw_listing_id": rid, "brand": r["brand"], "model": r["model"],
                "cpu": r["cpu"], "gpu": r["gpu"],
                "ram_gb": int(r["ram_gb"]) if r["ram_gb"] else None,
                "storage_gb": int(r["storage_gb"]) if r["storage_gb"] else None,
                "screen_size": None, "price": int(r["price"]),
                "condition": r["condition"], "source": r["source"],
                "listing_url": r["listing_url"], "scraped_at": r["scraped_at"],
            })
        print(f"laptop_units baru: {len(new_laptops)}")
        for i in range(0, len(new_laptops), 200):
            call("POST", "/laptop_units", body=new_laptops[i : i + 200],
                 prefer="return=minimal")
        hdr = Path("/tmp/.curl_supa_hdr2")
        subprocess.run(["curl", "-sS", "--max-time", "60", "-K", str(CFG),
                        "-H", "Prefer: count=exact", "-H", "Range: 0-0",
                        "-D", str(hdr), "-o", "/dev/null",
                        API + "/laptop_units?select=id"], check=True)
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
