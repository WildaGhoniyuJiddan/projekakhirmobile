# Impor listing marketplace → Supabase

Dataset listing pasar Indonesia hasil panen 20–21 Okt 2026 untuk
`raw_listings` (+ `laptop_units`) proyek Supabase projekakhirmobile.

## Isi

| File | Keterangan |
|---|---|
| `listings_clean.csv` | 3.357 baris siap impor, kolom = skema `raw_listings` |
| `laptop_units_clean.csv` | 681 baris laptop terparse (brand/cpu/gpu/ram/storage dari judul) |
| `queries.tsv` | 131 kueri panen (kueri + kategori awal) |
| `compile_filters.py` | Mentah JSONL → CSV: dedupe, buang ex-mining/WTB/harga sampah |
| `normalize_listings.py` | CSV → bersih: kondisi kanonik, pisah PC rakitan & laptop |
| `import_listings.py` | Impor ke Postgres Supabase (idempoten, ON CONFLICT DO NOTHING) |
| `*_stats.json` | Statistik tiap tahap (audit) |

## Sumber & hasil

- FB Marketplace: 1.592 baris bersih (131/131 kueri)
- Tokopedia: 1.765 baris bersih (40 kueri inti; sisanya long-tail berhenti
  karena throttling, sesuai aturan stop)
- OLX/Shopee/Bukalapak: 0 — egress VM diblokir platform (anti-bot/WAF)

## Aturan bersih-bersih (keputusan Dan)

- **Ex-mining dibuang** (kecuali dinegasikan: "bukan ex mining" tetap lolos)
- Harga di luar Rp50rb–150jt & placeholder dibuang
- Kondisi dinormalkan ke kanonik engine: `new` / `second` / NULL
  (tidak ditebak paksa — NULL dibaca engine sebagai `new`)
- **PC rakitan BUKAN 1 komponen**: listing build utuh (penanda
  rakitan/fullset/paket PC, atau ≥3 grup komponen berspek angka di judul)
  dipindah ke kategori `pc`; laptop yang ketemu via kueri komponen
  dipindah ke kategori `laptop` + diparse ke `laptop_units`

Distribusi final (v2, sudah terimpor & terverifikasi di Supabase):
gpu 1.125, laptop 681, pc 604, cpu 300, storage 249, ram 207,
motherboard 191 — total raw_listings 3.357, laptop_units 681.
Kondisi: second 1.263, new 653, NULL 1.441.

Catatan impor: koneksi Postgres langsung dari VM terblokir proxy, dan
urllib putus-putus untuk respons besar — impor berjalan via PostgREST
HTTPS (service_role) dengan transport curl (`import_via_rest.py`,
`import_laptops3.py`, patch kategori `patch_v2.py`).

## Cara impor ulang

```bash
SUPABASE_DB_URL='postgresql://postgres:<password>@db.<ref>.supabase.co:5432/postgres' \
  python3 import_listings.py
```
