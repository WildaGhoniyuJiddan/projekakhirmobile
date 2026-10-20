# Golden Values — Panen dari Python asli (repo lama)

Dihasilkan 2026-10-20 dengan menjalankan fungsi murni di
`~/workspace/WorthGaBang-AndroidVer/backend/app/services/` memakai venv
Python khusus (skrip sekali pakai). Nilai di file ini adalah SUMBER
literal untuk `engine_golden_test.dart` — jangan hitung ulang.

Baseline pytest backend lama: 33 passed bila `DATABASE_URL` menunjuk
DB segar sebelum import (lihat catatan isolasi di laporan QA-Golden).

## 1. score_price — referensi [4000000, 4500000, 5000000, 5500000, 6000000] (median 5000000), mode pasar

| Kasus | price | score | verdict | reference | delta% | fair_low | fair_high |
|---|---|---|---|---|---|---|---|
| murah_3500000 | - | 96.0 | worth it | 5000000 | -30.0 | 4500000 | 5500000 |
| pas_batas_4500000 | - | 90.0 | worth it | 5000000 | -10.0 | 4500000 | 5500000 |
| median_5000000 | - | 80.0 | wajar | 5000000 | 0.0 | 4500000 | 5500000 |
| wajar_5250000 | - | 75.0 | wajar | 5000000 | 5.0 | 4500000 | 5500000 |
| opsi_5750000 | - | 60.0 | ada opsi lebih baik | 5000000 | 15.0 | 4500000 | 5500000 |
| mahal_7000000 | - | 38.0 | kemahalan | 5000000 | 40.0 | 4500000 | 5500000 |
| ref_kosong | - | 50.0 | data terbatas | 5000000 | 0.0 | 5000000 | 5000000 |
| ref_nol | - | 50.0 | data terbatas | 5000000 | 0.0 | 5000000 | 5000000 |
| ref_kecil_4700000 | - | 74.0 | wajar | 5000000 | -6.0 | 4500000 | 5500000 |
| median_genap_4500000 | - | 80.0 | wajar | 4500000 | 0.0 | 4050000 | 4950000 |

Harga per kasus: murah=3500000, pas_batas=4500000, median=5000000,
wajar=5250000, opsi=5750000, mahal=7000000, ref_kosong=[] @5000000,
ref_nol=[0,0] @5000000, ref_kecil=[4800000,5200000] @4700000,
median_genap=[4000000,5000000] @4500000.

## 2. score_price — mode is_new_reference, referensi [8000000]

| Kasus | price | score | verdict | delta% | fair_low | fair_high |
|---|---|---|---|---|---|---|
| baru_worth_5000000 | 5000000 | 90.8 | worth it | -37.5 | 5200000 | 6400000 |
| baru_wajar_6000000 | 6000000 | 80.0 | wajar | -25.0 | 5200000 | 6400000 |
| baru_opsi_6800000 | 6800000 | 67.5 | ada opsi lebih baik | -15.0 | 5200000 | 6400000 |
| baru_mahal_7600000 | 7600000 | 46.0 | kemahalan | -5.0 | 5200000 | 6400000 |

Rekomendasi (verbatim) per verdict — mode pasar:
- worth it: "Harga berada di bawah median pasar dan layak dipertimbangkan."
- wajar: "Harga masih berada di rentang wajar berdasarkan pembanding yang tersedia."
- ada opsi lebih baik: "Ada pembanding dengan harga lebih rendah; pertimbangkan negosiasi atau opsi lain."
- kemahalan: "Harga berada cukup jauh di atas median pasar."
- data terbatas: "Belum cukup pembanding untuk memberi rekomendasi kuat."

## 3. passmark_score (benchmark_scores.json)

| Query | Tipe | name | score | price_usd | tdp |
|---|---|---|---|---|---|
| RTX 4060 | gpu | GeForce RTX 4060 | 19489 | 479.0 | 115 |
| rtx 4060 ti | gpu | GeForce RTX 4060 Ti | 22599 | 529.0 | 160 |
| RTX 3060 | gpu | GeForce RTX 3060 | 16895 | None | None |
| GTX 1660 Super | gpu | GeForce GTX 1660 SUPER | 12662 | 242.8 | 125 |
| RTX 4090 | gpu | GeForce RTX 4090 | 38043 | 3299.95 | 450 |
| Ryzen 5 5600 | cpu | AMD Ryzen 5 5600 | 21494 | 126.47 | 65 |
| Ryzen 7 7800X3D | cpu | AMD Ryzen 7 7800X3D | 34276 | 319.98 | 120 |
| Komponen Ngawur | gpu | None | - | - | - |
| RTX 4060 | ram | None | - | - | - |

## 4. consensus_lookup (consensus_scores.json)

| Query | Tipe | name | consensus_score | tier | n_sources | agreement | price_usd |
|---|---|---|---|---|---|---|---|
| RTX 4060 | gpu | Nvidia RTX 4060 | 28.97 | C | 7 | 20.45 | 245.0 |
| rtx 4060 ti | gpu | Nvidia RTX 4060-Ti | 85.25 | S | 1 | 0.0 | 340.0 |
| RTX 3060 | gpu | Nvidia RTX 3060 | 75.41 | A | 1 | 0.0 | 280.0 |
| GTX 1660 Super | gpu | None | - | - | - | - | - |
| RTX 4090 | gpu | Nvidia RTX 4090 | 97.12 | S | 8 | 1.44 | 1946.0 |
| Ryzen 5 5600 | cpu | AMD Ryzen 5 5600 | 57.91 | B | 4 | 30.68 | 138.0 |
| Ryzen 7 7800X3D | cpu | AMD Ryzen 7 7800X3D | 78.08 | A | 5 | 21.88 | 320.0 |
| Komponen Ngawur | gpu | None | - | - | - | - | - |
| RTX 4060 | ram | None | - | - | - | - | - |

## 5. better_alternatives (PassMark, usd_to_idr=16000)

- **RTX 3060|6000000**: []
- **RTX 4060|5500000**: []
- **Ryzen 5 5600|2500000**: AMD Ryzen 9 3900X (skor 32475, est Rp2410320, +51%, vram None, tier High End (Heavy Productivity & Gaming))
- **Komponen Ngawur|5000000**: []

## 6. better_alternatives_consensus (usd_to_idr=16000)

- **RTX 3060|6000000**: []
- **RTX 4060|5500000**: Nvidia GTX 1080-Ti (skor 78, est Rp4259200, +169%, vram None, 1 sumber, tier Menengah Atas (Upper Midrange)), Nvidia RTX 3060 (skor 75, est Rp4928000, +160%, vram 12, 1 sumber, tier Menengah Atas (Upper Midrange))
- **Ryzen 5 5600|2500000**: AMD Ryzen 5 5500GT (skor 80, est Rp2376000, +38%, vram None, 1 sumber, tier Menengah Atas (Upper Midrange)), Intel Core i5-12600 (skor 77, est Rp2428800, +34%, vram None, 3 sumber, tier Menengah Atas (Upper Midrange))
- **Komponen Ngawur|5000000**: []

## 7. laptop_combo_score

- **gaming_5600_4060**: score 18395, is_igpu False, tier "Midrange Gaming / Content Creation", gpu GeForce RTX 4060, cpu AMD Ryzen 5 5600H
- **mobile_i5_3050**: score 12542, is_igpu False, tier "Budget Gaming / Fast Productivity", gpu GeForce RTX 3050 6GB, cpu Intel Core i5-12450H
- **igpu_i7_iris**: score 2590, is_igpu True, tier "Ultrabook / Daily Office", gpu Intel Iris Xe, cpu None
- **ngawur**: None

Pasangan input: gaming=("Ryzen 5 5600","RTX 4060"),
mobile=("Core i5-12450H","RTX 3050"), igpu=("Core i7-1165G7","Intel Iris Xe Graphics"),
ngawur=("Komponen Ngawur","GPU Ngawur").

## 8. extract_vram_gb

| String | Hasil |
|---|---|
| RTX 4060 8GB | 8 |
| RTX 3060 | 12 |
| RX 6700 XT | 12 |
| RTX 4070 Ti 16GB | 16 |
| GTX 1650 | 4 |
| RX 6800 | 16 |
| RTX 2060 Super | 8 |
| RTX 4090 | None |
| Kartu Polos | None |

## 9. get_tier_label

| score \| tipe | Label |
|---|---|
| 30000 \| gpu | Enthusiast (4K Ultra Gaming) |
| 15000 \| gpu | Midrange (1080p Ultra / 1440p Mid) |
| 5000 \| gpu | Basic (Office & Casual) |
| 40000 \| cpu | High End (Heavy Productivity & Gaming) |
| 15000 \| cpu | Budget (1080p Gaming & Daily Work) |
| 25000 \| laptop | High End Gaming / Workstation |
| 0 \| gpu | Standard |

## 10. consensus_tier_label

| score | Label |
|---|---|
| 85.0 | Kelas Atas (High End) |
| 65.0 | Menengah Atas (Upper Midrange) |
| 45.0 | Menengah (Midrange) |
| 25.0 | Pemula (Entry Level) |
| 10.0 | Dasar (Basic) |
| None | Standard |
