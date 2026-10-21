#!/usr/bin/env python3
"""Konversi katalog retail ASLI + benchmark scores (file upload Dan,
dipakai menu cek harga sistem lama) menjadi bahan grounding Dodo.

Prinsip (perintah Dan 2026-10-21):
- retail_catalog.json upload = SUMBER UTAMA (harga toko retail nyata,
  satu harga per produk persis) -> menang atas median marketplace.
- Item katalog Dodo sekarang (hasil panen marketplace) hanya MENGISI
  model yang tidak ada di katalog retail (termasuk kategori laptop/pc
  yang tidak dimiliki katalog retail).
- benchmark_scores.json (PassMark) memperkaya consensus_scores.json:
  hanya untuk model CPU/GPU yang belum punya skor konsensus, diubah
  ke skala 0-100 via PERCENTILE RANK dalam kategorinya (skor mentah
  PassMark tidak sebanding skala konsensus), ditandai n_sources=1.

Input : ~/workspace/user/files/retail_catalog.json
         ~/workspace/user/files/benchmark_scores.json
         assets/data/retail_catalog.json (katalog berjalan)
         supabase/functions/bang-worth/consensus_scores.json
Output : assets/data/retail_catalog.json (diganti, hasil merge)
         supabase/functions/bang-worth/retail_catalog.json (salinan)
         supabase/functions/bang-worth/consensus_scores.json (diperkaya)
"""
import json
import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
UPLOAD_DIR = Path.home() / "workspace/user/files"
FN_DIR = REPO / "supabase/functions/bang-worth"


def norm_key(name: str) -> str:
    s = re.sub(r"[^a-z0-9]+", " ", name.lower())
    return re.sub(r"\s+", " ", s).strip()


# Harga typo/placeholder penjual (pola angka asal ketik) — gerbang sama
# dgn normalize_products.is_placeholder_price: item dibuang.
PLACEHOLDER_PRICES = {1111111, 2323232, 77752777, 123123, 1231234,
                      123456, 999999, 111111, 222222, 1234567}


def is_placeholder_price(price: int) -> bool:
    s = str(price)
    return price in PLACEHOLDER_PRICES \
        or re.fullmatch(r"(\d)\1{5,}", s) is not None \
        or re.fullmatch(r"(123)+|(1234)+", s) is not None


def main() -> None:
    retail_up = json.loads((UPLOAD_DIR / "retail_catalog.json").read_text())
    bench_up = json.loads((UPLOAD_DIR / "benchmark_scores.json").read_text())
    current = json.loads((REPO / "assets/data/retail_catalog.json").read_text())

    merged: dict[str, list[dict]] = {}
    stats = {}

    def name_of(it: dict) -> str:
        return str(it.get("model") or it.get("name") or "")

    # --- 1. Basis: katalog retail upload (format item: model+price) ---
    dropped_retail_ph = 0
    for cat in ("gpu", "cpu", "motherboard", "ram", "storage"):
        items = []
        for it in retail_up.get(cat, []):
            if is_placeholder_price(int(it["price"])):
                dropped_retail_ph += 1
                continue
            items.append({"model": it["model"], "price": int(it["price"]), "src": "retail"})
        merged[cat] = items
        stats[cat] = {"retail": len(items), "pengisi": 0}
    if dropped_retail_ph:
        print(f"  gerbang placeholder: {dropped_retail_ph} retail dibuang")

    # Harga kanonik RAM/storage generik -> item jangkar generik.
    for src, cat, prefix in (
        ("ram_canonical", "ram", ""),
        ("storage_canonical", "storage", ""),
    ):
        for label, price in retail_up.get(src, {}).items():
            merged[cat].append({"model": f"{prefix}{label} (generik)", "price": int(price), "src": "retail"})
            stats[cat]["retail"] += 1

    # --- 2. Pengisi: item katalog berjalan yang modelnya belum ada ---
    # Gerbang kewajaran harga: pengisi non-bekas yang harganya < 50%
    # dari harga retail termurah untuk inti seri yang sama (mis.
    # "13100" dari 13100F) dibuang — itu harga rusak/salah scrape,
    # bukan harga pasar (kasus nyata: i3-13100F "NEW" Rp830rb padahal
    # second saja Rp1,45jt). Pengisi bekas ambangnya 30%.
    def digit_cores(name: str) -> set[str]:
        cores = set()
        for tok in re.findall(r"[a-z0-9]+", name.lower()):
            m = re.fullmatch(r"(\d{3,})[a-z]{0,3}", tok)
            if m:
                cores.add(m.group(1))
        return cores

    def model_tokens(name: str) -> set[str]:
        # Token model persis (mis. 13100f, 7800x3d, 5070ti): mengandung
        # >= 3 digit berurutan, panjang >= 4.
        out = set()
        for tok in re.findall(r"[a-z0-9]+", name.lower()):
            if len(tok) >= 4 and re.search(r"\d{3,}", tok):
                out.add(tok)
        return out

    dropped = 0
    for cat, items in current.items():
        if not isinstance(items, list):
            continue
        base_keys = {norm_key(name_of(i)) for i in merged.get(cat, [])}
        retail_by_core: dict[str, int] = {}
        retail_by_token: dict[str, int] = {}
        for bi in merged.get(cat, []):
            for core in digit_cores(bi["model"]):
                if core not in retail_by_core or bi["price"] < retail_by_core[core]:
                    retail_by_core[core] = bi["price"]
            for tok in model_tokens(bi["model"]):
                if tok not in retail_by_token or bi["price"] < retail_by_token[tok]:
                    retail_by_token[tok] = bi["price"]
        bucket = merged.setdefault(cat, [])
        if cat not in stats:
            stats[cat] = {"retail": 0, "pengisi": 0}
        stats[cat].setdefault("dibuang", 0)
        for it in items:
            nm = name_of(it)
            if norm_key(nm) in base_keys:
                continue
            price = int(it["price"])
            if is_placeholder_price(price):
                dropped += 1
                stats[cat]["dibuang"] += 1
                continue
            is_second = "(bekas)" in nm.lower()
            implausible = False
            for core in digit_cores(nm):
                ref = retail_by_core.get(core)
                if ref and price < ref * (0.30 if is_second else 0.50):
                    implausible = True
                    break
            # SKU yang sama persis ada di retail: retail adalah otoritas
            # harga BARU. Pengisi non-bekas < 80% harga retail termurah
            # untuk token model itu dibuang (kemasan tray tidak pernah
            # semurah itu untuk part generasi berjalan).
            if not implausible and not is_second:
                for tok in model_tokens(nm):
                    ref = retail_by_token.get(tok)
                    if ref and price < ref * 0.80:
                        implausible = True
                        break
            if implausible:
                dropped += 1
                stats[cat]["dibuang"] += 1
                continue
            bucket.append({"model": nm, "price": price, "src": "market"})
            stats[cat]["pengisi"] += 1
    print(f"  gerbang kewajaran: {dropped} pengisi tak wajar dibuang")

    total = sum(len(v) for v in merged.values())
    # Kunci meta dipertahankan: engine cek harga membaca
    # ram_canonical/storage_canonical dari file aset yang sama.
    payload = {"generated_at": retail_up.get("generated_at"), **merged}
    for meta_key in ("ram_canonical", "storage_canonical"):
        if meta_key in retail_up:
            payload[meta_key] = retail_up[meta_key]
    out = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
    (REPO / "assets/data/retail_catalog.json").write_text(out)
    (FN_DIR / "retail_catalog.json").write_text(out)
    print(f"KATALOG merge: total {total} item")
    for cat, s in sorted(stats.items()):
        print(f"  {cat}: retail {s['retail']} + pengisi marketplace {s['pengisi']} (dibuang {s.get('dibuang', 0)})")

    # --- 3. Perkaya consensus dengan PassMark (percentile) ---
    cons_path = FN_DIR / "consensus_scores.json"
    cons = json.loads(cons_path.read_text())
    added = {"cpu": 0, "gpu": 0}
    for cat in ("cpu", "gpu"):
        existing = cons.setdefault(cat, {})
        entries = sorted(
            bench_up.get(cat, {}).items(), key=lambda kv: kv[1]["score"]
        )
        n = len(entries)
        for rank, (key, v) in enumerate(entries):
            if key in existing:
                continue
            pct = round(rank / (n - 1) * 100, 2) if n > 1 else 100.0
            tier = "S" if pct >= 90 else "A" if pct >= 75 else "B" if pct >= 55 else "C" if pct >= 35 else "D"
            existing[key] = {
                "name": v["name"],
                "consensus_score": pct,
                "tier": tier,
                "n_sources": 1,
                "agreement": 0,
                "price_usd": v.get("price_usd"),
                "source": "passmark-percentile",
            }
            added[cat] += 1
    cons_path.write_text(json.dumps(cons, ensure_ascii=False, separators=(",", ":")))
    print(f"CONSENSUS diperkaya: +{added['cpu']} CPU, +{added['gpu']} GPU dari PassMark")
    print(f"  total skor: cpu {len(cons['cpu'])}, gpu {len(cons['gpu'])}")


if __name__ == "__main__":
    main()
