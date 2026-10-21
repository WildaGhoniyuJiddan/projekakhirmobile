#!/usr/bin/env python3
"""Impor listings via PostgREST (HTTPS) + service_role key.

Dipakai karena koneksi Postgres langsung dari VM terblokir proxy egress.
Key dibaca dari stdin (transient). Idempoten: ignore-duplicates pada
unique listing_hash. Verifikasi: count exact per tabel.
"""
import csv
import json
import os
import sys
import urllib.request
from pathlib import Path

BASE = Path(__file__).parent
REF = "kvubnpujxiiqhpcrzlso"
API = f"https://{REF}.supabase.co/rest/v1"


def rows(name):
    with open(BASE / name, encoding="utf-8") as f:
        for r in csv.DictReader(f):
            yield {k: (v if v != "" else None) for k, v in r.items()}


def req(method, path, key, body=None, extra=None):
    r = urllib.request.Request(API + path, method=method)
    r.add_header("apikey", key)
    r.add_header("Authorization", f"Bearer {key}")
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        r.add_header("Content-Type", "application/json")
    for k, v in (extra or {}).items():
        r.add_header(k, v)
    with urllib.request.urlopen(r, data=data, timeout=120) as resp:
        return resp.status, resp.headers, resp.read().decode()


def post_batches(table, batch_rows, key, on_conflict=None):
    import time
    import urllib.error

    ok = 0
    for i in range(0, len(batch_rows), 500):
        chunk = batch_rows[i : i + 500]
        path = f"/{table}"
        if on_conflict:
            path += f"?on_conflict={on_conflict}"
        last_err = None
        for attempt in range(4):
            try:
                status, _, body = req(
                    "POST", path, key, body=chunk,
                    extra={"Prefer": "resolution=ignore-duplicates,return=minimal"},
                )
                if status not in (200, 201):
                    sys.exit(f"POST {table} batch {i}: HTTP {status} {body[:300]}")
                last_err = None
                break
            except (urllib.error.URLError, ConnectionError, TimeoutError) as e:
                last_err = e
                print(f"{table} batch @{i}: percobaan {attempt + 1} gagal ({e}), retry...")
                time.sleep(3 * (attempt + 1))
        if last_err is not None:
            sys.exit(f"POST {table} batch {i}: menyerah setelah 4x: {last_err}")
        ok += len(chunk)
        print(f"{table}: terkirim {ok}/{len(batch_rows)}")
    return ok


def count(table, key, query=""):
    _, headers, _ = req(
        "GET", f"/{table}?select=id{query}", key,
        extra={"Prefer": "count=exact", "Range": "0-0"},
    )
    return headers["Content-Range"].split("/")[-1]


def main() -> None:
    key = sys.stdin.read().strip()
    if not key.startswith("eyJ"):
        sys.exit("service_role key tidak valid (harus JWT eyJ...)")

    listings = []
    for r in rows("listings_clean.csv"):
        r["raw_price"] = int(r["raw_price"])
        r.pop("is_official_store", None)
        r.pop("sold_count", None)
        r.pop("rating", None)
        listings.append(r)
    post_batches("raw_listings", listings, key, on_conflict="listing_hash")
    print("VERIFIKASI raw_listings total:", count("raw_listings", key))

    # Ambil peta listing_hash -> id untuk laptop_units
    id_by_hash = {}
    offset = 0
    while True:
        _, _, body = req(
            "GET",
            f"/raw_listings?select=id,listing_hash&limit=1000&offset={offset}",
            key,
        )
        page = json.loads(body)
        if not page:
            break
        id_by_hash.update({p["listing_hash"]: p["id"] for p in page})
        offset += len(page)
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
    post_batches("laptop_units", laptops, key)
    print("VERIFIKASI laptop_units total:", count("laptop_units", key))


if __name__ == "__main__":
    main()
