#!/usr/bin/env python3
"""Impor listings_clean.csv + laptop_units_clean.csv ke Supabase (Postgres).

Kredensial: env SUPABASE_DB_URL (postgresql://postgres:<pw>@db.<ref>.
supabase.co:5432/postgres) — transient, tidak pernah ditulis ke disk.
Idempoten: ON CONFLICT (listing_hash) DO NOTHING untuk raw_listings;
laptop_units di-skip bila raw_listing_id+listing_url sudah ada.
Setelah impor: cetak hitungan verifikasi per tabel/sumber/kategori.
"""
import csv
import os
import sys
from pathlib import Path

import psycopg2
import psycopg2.extras

BASE = Path(__file__).parent


def rows(name):
    with open(BASE / name, encoding="utf-8") as f:
        for r in csv.DictReader(f):
            yield {k: (v if v != "" else None) for k, v in r.items()}


def main() -> None:
    url = os.environ.get("SUPABASE_DB_URL")
    if not url:
        sys.exit("SUPABASE_DB_URL belum diset")
    conn = psycopg2.connect(url)
    conn.autocommit = False
    cur = conn.cursor()

    listings = list(rows("listings_clean.csv"))
    for r in listings:
        r["raw_price"] = int(r["raw_price"])
    psycopg2.extras.execute_values(
        cur,
        """insert into public.raw_listings
           (source, category, raw_title, raw_price, raw_spec_text,
            description, listing_url, listing_hash, condition, seller,
            is_official_store, sold_count, rating, condition_source,
            scraped_at)
           values %s on conflict (listing_hash) do nothing""",
        [
            (
                r["source"], r["category"], r["raw_title"], r["raw_price"],
                r["raw_spec_text"], r["description"], r["listing_url"],
                r["listing_hash"], r["condition"], r["seller"],
                None, None, None, r["condition_source"], r["scraped_at"],
            )
            for r in listings
        ],
        page_size=500,
    )
    print(f"raw_listings: dicoba {len(listings)} baris")

    cur.execute("select id, listing_hash from public.raw_listings")
    id_by_hash = {h: i for i, h in cur.fetchall()}

    laptops = list(rows("laptop_units_clean.csv"))
    vals = []
    for r in laptops:
        rid = id_by_hash.get(r["listing_hash"])
        if rid is None:
            continue
        vals.append((
            rid, r["brand"], r["model"], r["cpu"], r["gpu"],
            int(r["ram_gb"]) if r["ram_gb"] else None,
            int(r["storage_gb"]) if r["storage_gb"] else None,
            None, int(r["price"]), r["condition"], r["source"],
            r["listing_url"], r["scraped_at"],
        ))
    psycopg2.extras.execute_values(
        cur,
        """insert into public.laptop_units
           (raw_listing_id, brand, model, cpu, gpu, ram_gb, storage_gb,
            screen_size, price, condition, source, listing_url, scraped_at)
           values %s""",
        vals,
        page_size=500,
    )
    print(f"laptop_units: dimasukkan {len(vals)} baris")

    conn.commit()
    cur.execute("select count(*) from public.raw_listings")
    print("VERIFIKASI raw_listings total:", cur.fetchone()[0])
    cur.execute(
        "select source, category, count(*) from public.raw_listings "
        "group by 1, 2 order by 1, 2"
    )
    for row in cur.fetchall():
        print(" ", row)
    cur.execute("select count(*) from public.laptop_units")
    print("VERIFIKASI laptop_units total:", cur.fetchone()[0])
    conn.close()


if __name__ == "__main__":
    main()
