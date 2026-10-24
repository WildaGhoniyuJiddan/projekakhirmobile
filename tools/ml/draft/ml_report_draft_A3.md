# Laporan ML Harga Wajar (DRAFT — ANGKA DIBUANG)

Laporan ini hasil Fase A2 (perbaikan skrip Fase A). Angkanya DIBUANG dan tidak dipakai untuk keputusan. Latih final diulang dari skrip ini setelah data final, lalu direview Dan sebelum integrasi. Model harus dilatih ulang tiap panen data baru, karena price_models.json adalah asset beku di APK sementara median pembanding di app bersifat live.

- Input: /home/hatch/workspace/projekakhirmobile/tools/listings_import/listings_clean.csv (13573 baris CSV)
- Konsensus generated_at: 2026-10-15; benchmark generated_at: 2026-08-26T12:44:41.952595+00:00
- Dilatih: 2026-10-24T20:55:09+07:00; venv: tools/ml/.venv (pandas, numpy, scikit-learn)
- Perintah: tools/ml/.venv/bin/python tools/ml/train_price_models.py --out tools/ml/draft/... --report tools/ml/draft/... --dump-parity --parity-out tools/ml/draft/...
- Run A4 (file BARU, laporan draft lama tidak ditimpa): gerbang Tier 1 baru (minimal 5% di bawah baseline) + perluasan ekstraksi CPU laptop (bare iX, Core tanpa i, Ultra 3 digit, Apple).

## Definisi kunci grup produk (dari FITUR FINAL)

- gpu = (model, vram); cpu = (model); ram = (ddr, total_gb); storage = (tipe, kapasitas_gb); motherboard = (chipset); laptop = (cpu_sig, gpu_sig).
- Baseline (a): median pool (grup, kondisi) train fold; bila (grup, kondisi) < 3 baris pakai median grup; bila grup < 3 baris pakai median kategori.
- Baseline (b): median kategori train fold (GroupKFold).
- Pemisah evaluasi (a) Fase A2: group_n = jumlah baris grup produk yang sama di train fold, TANPA kondisi dan TANPA rantai fallback (perhitungan baseline (a) sendiri tidak berubah). Segmen group_n < 5 vs >= 5; segmen dengan n < 20 ditandai 'tidak cukup untuk disimpulkan'.
- Gerbang Fase A2: Tier 1 butuh >= 150 baris bersih dan MAE (a) model < MAE (a) baseline. Tier 2 butuh >= 100 baris bersih DAN MAE (b) model <= 0,9 x MAE median kategori (b) (lebih kecil minimal 10%). Gerbang 150 tidak lagi diterapkan ke Tier 2.
- Gerbang A4 (menggantikan syarat Tier 1 A2): Tier 1 butuh >= 150 baris bersih DAN MAE (a) model <= 0,95 x MAE (a) baseline (lebih kecil minimal 5%). Tier 2 TETAP >= 100 baris DAN MAE (b) model <= 0,9 x MAE median kategori (b).
- Aturan pilih skala skor (Fase A2): skala dengan coverage baris < 30% didiskualifikasi bila skala lain >= 30%; di antara yang lolos, Spearman interseksi lebih tinggi menang; bila selisih < 0,05, coverage lebih tinggi menang; bila Spearman tak tersedia, coverage yang menang.

## Hasil per kategori (varian src terpilih)

| kategori | baris bersih | enabled | fallback | varian src | MAE (a) model | MAE (a) baseline | MAPE model | MAPE baseline | MAE (b) model | MAE (b) median kategori |
|---|---|---|---|---|---|---|---|---|---|---|
| gpu | 1549 | False | True | with_src | Rp1.984.217 | Rp1.363.525 | 43.9% | 30.5% | Rp2.086.902 | Rp3.323.324 |
| cpu | 697 | False | True | with_src | Rp807.013 | Rp585.340 | 22.6% | 22.5% | Rp854.997 | Rp1.607.342 |
| ram | 529 | False | True | without_src | Rp1.203.233 | Rp1.197.652 | 53.9% | 57.3% | Rp1.213.938 | Rp1.844.705 |
| storage | 740 | False | True | without_src | Rp822.910 | Rp599.387 | 76.3% | 61.3% | Rp894.691 | Rp995.469 |
| motherboard | 474 | False | False | with_src | Rp540.287 | Rp543.419 | 30.1% | 32.3% | Rp869.554 | Rp897.041 |
| laptop | 1080 | True | True | without_src | Rp2.213.093 | Rp2.944.335 | 22.7% | 33.4% | Rp2.239.641 | Rp4.630.671 |

## Eksperimen source (A3-4, dua varian per kategori)

Varian dengan-src dilatih dengan nilai src asli, tapi DIEVALUASI dengan kolom src baris test diganti rata-rata src train fold (anti-leakage: user app tidak memilih sumber). Keputusan utama = MAE (a); MAE (b) konfirmasi; bila (a) dan (b) bertentangan, pemenang (a) yang dipakai. Gerbang Tier 1/Tier 2 dihitung dari varian terpilih. src_tokopedia_mean di defaults = rata-rata src baris training final kategori itu; di inferensi, fitur src (bila ada) diisi nilai itu.

| kategori | MAE (a) tanpa-src | MAE (a) dengan-src | MAE (b) tanpa-src | MAE (b) dengan-src | terpilih | alasan |
|---|---|---|---|---|---|---|
| gpu | Rp1.993.755 | Rp1.984.217 | Rp2.087.411 | Rp2.086.902 | with_src | (a) dan (b) sepakat |
| cpu | Rp834.483 | Rp807.013 | Rp903.162 | Rp854.997 | with_src | (a) dan (b) sepakat |
| ram | Rp1.203.233 | Rp1.262.615 | Rp1.213.938 | Rp1.277.167 | without_src | (a) dan (b) sepakat |
| storage | Rp822.910 | Rp823.105 | Rp894.691 | Rp897.083 | without_src | (a) dan (b) sepakat |
| motherboard | Rp541.109 | Rp540.287 | Rp866.069 | Rp869.554 | with_src | (a) dan (b) bertentangan, keputusan utama = (a) |
| laptop | Rp2.213.093 | Rp2.248.144 | Rp2.239.641 | Rp2.271.005 | without_src | (a) dan (b) sepakat |

## Pecahan MAE evaluasi (a) menurut group_n (Fase A2)

group_n = jumlah baris grup produk yang sama di train fold (tanpa kondisi, tanpa fallback). Segmen n < 20 ditandai 'tidak cukup untuk disimpulkan'.

| kategori | n group_n < 5 | MAE model < 5 | MAE baseline < 5 | n group_n >= 5 | MAE model >= 5 | MAE baseline >= 5 |
|---|---|---|---|---|---|---|
| gpu | 126 | Rp2.070.523 | Rp3.351.752 | 1423 | Rp1.976.576 | Rp1.187.476 |
| cpu | 79 | Rp994.223 | Rp1.946.710 | 618 | Rp783.081 | Rp411.314 |
| ram | 6 (tidak cukup untuk disimpulkan) | Rp7.428.451 | Rp11.012.642 | 523 | Rp1.131.815 | Rp1.085.052 |
| storage | 41 | Rp1.566.211 | Rp779.975 | 699 | Rp779.311 | Rp588.795 |
| motherboard | 22 | Rp1.490.545 | Rp1.495.146 | 452 | Rp494.035 | Rp497.096 |
| laptop | 647 | Rp2.477.636 | Rp4.211.253 | 433 | Rp1.817.807 | Rp1.051.274 |

## Alasan gerbang per tier

- gpu: Tier 1 enabled=False (alasan: mae_model_a_tidak_lebih_baik_5persen); Tier 2 enabled_fallback=True (alasan: mae_model_b_le_90persen_median_kategori_b).
  - Tier 1 gagal: MAE (a) model Rp1.984.217 vs ambang 0,95 x baseline Rp1.295.348 (butuh <= ambang).
- cpu: Tier 1 enabled=False (alasan: mae_model_a_tidak_lebih_baik_5persen); Tier 2 enabled_fallback=True (alasan: mae_model_b_le_90persen_median_kategori_b).
  - Tier 1 gagal: MAE (a) model Rp807.013 vs ambang 0,95 x baseline Rp556.073 (butuh <= ambang).
- ram: Tier 1 enabled=False (alasan: mae_model_a_tidak_lebih_baik_5persen); Tier 2 enabled_fallback=True (alasan: mae_model_b_le_90persen_median_kategori_b).
  - Tier 1 gagal: MAE (a) model Rp1.203.233 vs ambang 0,95 x baseline Rp1.137.770 (butuh <= ambang).
- storage: Tier 1 enabled=False (alasan: mae_model_a_tidak_lebih_baik_5persen); Tier 2 enabled_fallback=True (alasan: mae_model_b_le_90persen_median_kategori_b).
  - Tier 1 gagal: MAE (a) model Rp822.910 vs ambang 0,95 x baseline Rp569.418 (butuh <= ambang).
- motherboard: Tier 1 enabled=False (alasan: mae_model_a_tidak_lebih_baik_5persen); Tier 2 enabled_fallback=False (alasan: mae_model_b_tidak_lebih_baik_10persen).
  - Tier 1 gagal: MAE (a) model Rp540.287 vs ambang 0,95 x baseline Rp516.248 (butuh <= ambang).
  - Tier 2 gagal: MAE (b) model Rp869.554 vs ambang 0,9 x median kategori Rp807.337 (butuh <= ambang).
- laptop: Tier 1 enabled=True (alasan: mae_model_a_le_95persen_baseline_a); Tier 2 enabled_fallback=True (alasan: mae_model_b_le_90persen_median_kategori_b).

## Pembersihan per kategori (funnel lengkap, urutan A3)

Urutan: mentah -> dedupe hash -> dedupe (seller, raw_title) -> dedupe (seller, judul ternormalisasi) -> filter harga 50rb-150jt -> filter placeholder -> filter bundle A2 -> filter aksesori -> lolos ekstraksi -> setelah IQR (final). Inferensi kondisi tidak membuang baris.

| kategori | mentah | dedupe hash+judul | dedupe judul normalisasi (buang) | setelah harga | placeholder (buang) | setelah bundle | aksesori (buang) | setelah aksesori | lolos ekstraksi | setelah IQR (final) | alasan buang ekstraksi |
|---|---|---|---|---|---|---|---|---|---|---|---|
| gpu | 2378 | 2343 | 2341 (2) | 2341 | 1 | 2163 | 35 | 2128 | 1672 | 1549 | konsensus_tidak_cocok: 2; model_tidak_ditemukan: 454; vram_tidak_bisa_diimputasi: 7 |
| cpu | 1166 | 1123 | 1122 (1) | 1122 | 1 | 888 | 1 | 887 | 752 | 697 | konsensus_tidak_cocok: 4; model_tidak_ditemukan: 131 |
| ram | 637 | 629 | 629 (0) | 629 | 1 | 592 | 0 | 592 | 559 | 529 | kapasitas/ddr_tidak_ditemukan: 33 |
| storage | 865 | 863 | 862 (1) | 862 | 2 | 820 | 1 | 819 | 788 | 740 | kapasitas_tidak_ditemukan: 11; m2_tanpa_tipe: 3; tipe_tidak_dikenali: 17 |
| motherboard | 633 | 629 | 629 (0) | 629 | 1 | 597 | 0 | 597 | 489 | 474 | chipset_tidak_ditemukan: 108 |
| laptop | 4890 | 4732 | 4727 (5) | 4727 | 2 | 4684 | 139 | 4545 | 1144 | 1080 | cpu_passmark_tidak_cocok: 1970; gpu_konsensus_tidak_cocok: 1; ram/storage_hilang: 1430 |

## Filter placeholder (A3-1)

Diterapkan SETELAH filter rentang (yang dihitung hanya baris lolos rentang tapi dibuang aturan ini). Definisi: nilai persis 123456789, 987654321, 123123; digit berulang yang sama 5+ kali pada seluruh angka harga (regex ^(\d)\1{4,}$, mis. 11111, 555555, 9999999); angka yang digitnya diawali '12345' (12345x, mis. 123456, 1234567, 123450). Dihitung sekali per baris, pola pertama menang (persis > berulang > awalan).

| kategori | persis | berulang | awalan 12345 | total |
|---|---|---|---|---|
| gpu | 0 | 1 | 0 | 1 |
| cpu | 1 | 0 | 0 | 1 |
| ram | 1 | 0 | 0 | 1 |
| storage | 0 | 2 | 0 | 2 |
| motherboard | 1 | 0 | 0 | 1 |
| laptop | 0 | 2 | 0 | 2 |

## Filter bundle/rakitan (Fase A2, MENGGANTIKAN Fase A)

Diterapkan setelah filter placeholder, sebelum filter aksesori, ekstraksi fitur, dan IQR. (a) Penanda frasa HANYA di JUDUL, word boundary (jadi 'paketan' TIDAK memicu 'paket'); daftar akhir: pc rakitan, pc gaming, paket, bundling, set pc ('fullset'/'full set' DIHAPUS). (b) Deteksi pasangan: baris kategori single-komponen (gpu, cpu, ram, storage, motherboard) dibuang bila judulnya memuat dua jenis komponen berbeda (model gpu, model cpu, chipset mobo, spek ram berkonteks RAM/DDR, spek ssd berukuran+token). Laptop DIKECUALIKAN dari aturan pasangan. Baris dihitung sekali (penanda didahulukan).

| kategori | setelah placeholder | buang penanda judul | buang pasangan | setelah bundle |
|---|---|---|---|---|
| gpu | 2340 | 117 | 60 | 2163 |
| cpu | 1121 | 137 | 96 | 888 |
| ram | 628 | 16 | 20 | 592 |
| storage | 860 | 14 | 26 | 820 |
| motherboard | 628 | 8 | 23 | 597 |
| laptop | 4725 | 41 | 0 | 4684 |

### Contoh judul dibuang filter bundle baru (maks 10 per kategori, diurut beragam aturan)

#### gpu (penanda judul)
- [pc gaming] PC GAMING
- [paket] Paket ryzen 5 5600G + B450M DS3H V2 gigabyte
- [pc gaming] PC GAMING RYZEN 5 5600 VGA RADEON RX 6600 FULL SET
- [paket] 63% Amiyo Tablet Anak A15 Pro Max 10.03 Inch Android 13 WiFi RAM 4GB ROM 64GB Tablet Edukasi Anak Parental Control Garansi Resmi Paket Tempered Glass Paket Ultimate Kid Set
#### gpu (pasangan komponen)
- [cpu+gpu+storage] PC ryzen 7 5700x 32gb rtx 2060 ssd 512
- [cpu+gpu] PC RTX 4060 | Ryzen 5 7500F | Komputer Gaming Rendering
- [gpu+ram] PC RTX 4060 TI 8GB, RAM 64GB 3600MHz
- [gpu+ram+storage] Gaming PC i3 12100F RTX 5060 DLSS5 16GB DDR5 RGB NVMe Grafis Render AI Live Stream Valorant GTA
- [cpu+ram] Mobo Gigabyte H410M H V2, Intel Core i3-101005 & RAM PC/Longdim DDR4 8GB 2666Mhz Visipro
- [cpu+motherboard] RYZEN 7 5700x box + B550M STEEL LEGEND GARANSI ON
- [cpu+gpu+ram] PC Office Intel Core I5 12400F 16GB Ram with RX 580 8GB DDR5
- [ram+storage] HP 14 EP1177TU Intel Core 5 -120U Ram 8GB SSD 512GB 14″ W11+OH2024+M365Basic
- [motherboard+ram] 64% [EXCLUSIVE Toni_cu] Itel A100CS 4+8GB RAM / 64GB ROM | 4+8GB RAM / 64GB ROM - Military Grade Durability
- [motherboard+ram+storage] A320M Pro4 motherboard AM4 A320M 4×DDR4 64GB PCI-E 3.0 2×M.2 USB3.1 Micro ATX

#### cpu (penanda judul)
- [paket] Paket Motherboard+Processor AMD B450M
- [pc gaming] PC Gaming Ryzen 7 5700X FEAT RADEON RX 7600
- [bundling] Bundling Intel Core I9 - 12900K + Motherboard Asus ROG Strix Z690-A Gaming Wifi D4
- [paket] Paket ryzen 7 5800x & asrock b550m itx/ac
- [bundling] Part PC Sisa Upgrade Bundling Mobo MSI B560M PRO Box dan Processor Intel Core I5 11400F Box
#### cpu (pasangan komponen)
- [cpu+motherboard] Proc Ryzen 5 5600 tray+ Mobo B550M K Gigabyte (Box) + RAM (opsional)
- [cpu+ram] PC Ryzen 5 5600G Ram 16GB
- [cpu+gpu] GAMING Ryzen 5 5600 RX 5700 XT 8GB
- [cpu+motherboard+ram] Sepaket Processor AMD Ryzen 7 8700F B650M White Ram 16GB RGB DDR5 XPG HSF Deepcool 6,650 Jt Garansi
- [cpu+gpu+ram] PC Office Intel Core I5 12400F 16GB Ram with RX 580 8GB DDR5
- [ram+storage] PC i3 12100F RAM 16GB DDR4 3600Mhz SSD 256gb (No VGA)
- [cpu+ram+storage] komputer Ryzen 5 5600g Ram 16 Nvme 256GB VGA rog strix 1070 8gb Jual Fullset
- [gpu+ram+storage] PC Desktop Intel i5 6500 + GTX 750 | RAM 16GB DDR4 | SSD Fast Boot | Case FSP Tower
- [cpu+storage] PC RYZEN 5 5600G / 16GB / SSD+HDD / PSU 80+ / CASE VENOMRX
- [cpu+motherboard+storage] Bundle AMD Ryzen 5 7500F + MSI B650M-A WIFI + ADATA LEGEND 710 512GB PCIe Gen 3x4 M.2 NVME - Processor Motherboard SSD

#### ram (penanda judul)
- [paket] Paket Parts PC Komputer intel core i3 7100 mobo h110m RAM 8GB DDR4 2600Mhz harga 1,1 jt free kirim
- [pc gaming] RAM PC GAMING TEAMGROUP DELTA T-FORCE DDR4 8GB(4gbx2) RGB MANTAP
- [bundling] PROMO MOTOPAD 60 NEO > RAM 4/128GB ~ BUNDLING KEYBOARD + STYLUSPEN
- [pc gaming] PC GAMING SUPREME RTX 5070 12GB . Intel Ultra 9 285K . RAM DDR5 32GB
- [paket] PAKET MOBO DDR5
#### ram (pasangan komponen)
- [cpu+gpu] PC DESAIN CORE I3 10105F GTX 1050TI 4G RAM 16G
- [cpu+gpu+ram] Jual santai pc Ryzen 3 3200G Ram 16gb Rx 580
- [cpu+motherboard+ram] Core i5 7400 + asus b250 ram 8gb ddr4
- [ram+storage] CPU LENOVO / PC LENOVO M910S CORE I5 GENERASI 6 6600 RAM 8GB SSD 256GB
- [motherboard+ram+storage] Jual Murah Asus X441MA Intel N4000 Ram 8GB SSD 128GB HDD 1TB Mantap
- [motherboard+ram] sepaket procie i5 10400F + Msi B560M PRO WDH Wifi + Ram T-force Single 32GB DDR4 PC 3200
- [gpu+motherboard] Sekenan 12100F, B760 DDR4, Corsair DDR4,RTX 2070
- [ram+storage] Garansi Resmi Axioo Hype 10 intel N4020 Ram 8gb ssd nvme 256gb Fulset
- [ram+storage] Mini PC Lenovo ThinkCentre Seken Murah Core i5 Gen 7400t RAM 8GB ddr4 SSD Sata 240GB Siap Pakai
- [ram+storage] BELI RAM PC SERVER/ SSD SERVER 16 GB DDR4 32 GB DDR4 64 GB DDR4

#### storage (penanda judul)
- [pc gaming] PC GAMING R5 3500X GTX 1650 4G RAM 16GB
- [paket] Paket Budle Vst Softeare Toontrack EzDrummer 3 Superior Drummer 3 EZKeys EZBas. 2 EZMix 3+Core Libra
- [paket] PAKET KOMPLIT VST PLUGIN BUDLE PRODUKSI MUSIK UNTUK MIXING & EDITING WIN x64BIT
#### storage (pasangan komponen)
- [ram+storage] SSD NVMe WD SN740 99% + DDR4 8GB 3200Mhz
- [cpu+storage] PC Komputer Intel Core i5 4590, SSD 256Gb Siap Pakai
- [cpu+gpu] PC DESIGN RINGAN INTEL CORE I7 7700 FEAT GTX 970 DDR5
- [gpu+motherboard+ram+storage] Komputer 6 juta Intel i3 10100F RX 580 8GB RAM 16GB SSD 256Gb AIO Dual Wifi B460M Pro4 ARGB
- [gpu+storage] SSD NVMe VENOMRX 256/512GB 3.0x4
- [gpu+ram] PC OFFICE i5 GEN 6 FEAT GTX 750TI 4GB DDR5
- [motherboard+storage] Kingston A400 120GB 240GB 480GB 960GB KC600 SSD 1TB 256GB 512GB 2TB SATA 3 2.5 Internal Solid State Drive HDD Hard Disk HD SSD
- [ram+storage] Asus Expertbook Core i3 gen 13 RAM 8GB DDR5 SSD 512GB Gen 4 Garansi Resmi 2028
- [cpu+gpu] PC DESAIN CORE I3 10105F GTX 1050TI 4G RAM 16G
- [gpu+storage] SSD NVMe VENOMRX 512GB ULTRA 4.0

#### motherboard (penanda judul)
- [paket] Paket AMD Ryzen 5 3400G dan Motherboard Asrock B550M Pro4
- [paket] Paket mobo ddr4
#### motherboard (pasangan komponen)
- [ram+storage] Pc intel i5 12400 ram 16gb ddr4 ssd 512gb second
- [cpu+motherboard] B550m + ryzen 5 5500 (garansi on 2028)
- [cpu+ram] PC DESAIN & Gamer Ryzen 5 3400G Ram 16GB
- [cpu+gpu] PC Gamer Ryzen 5 5500 Feat RTX 3050 6GB
- [cpu+gpu+ram] ULTIMATE AI WORKSTATION & GAMING RIG Ryzen 9 7900 • RTX 5070 12GB • DDR5
- [cpu+motherboard] Motherboard b550 + ryzen 5 5500
- [cpu+motherboard] Sepaket Prosesor AMD Ryzen 5 3400G & MSI B450M-A PRO MAX II
- [cpu+motherboard] RYZEN 5 5600 + ASUS PRIME B450M-A II
- [cpu+motherboard] RYZEN 5 5600 + ASROCK B450M STEEL LEGEND
- [cpu+gpu] Intel Gaming Series | Core i5-12400F • RTX 5050

#### laptop (penanda judul)
- [pc gaming] PC GAMING RYZEN 5 7500F B650M RAM DDR5 32GB KIT SSD NVME GEN4 1TB RTX 4060 8GB PEMBELIAN 2025
- [paket] Paket gaming Processor intel i7 13700HX es
- [bundling] Grosir LENOVO LEGION SLIM 5 16 RTX4070 AMD RYZEN 7 7435HS 64GB 1TB SSD W11 16.0QHD IPS - NON BUNDLING 16GB 1TBSSD
- [pc gaming] PC Gaming Lenovo Dekstop LOQ 17URB8 i7 13700F RTX 3050 8GB 16GB/512GB
- [bundling] Terlaris LENOVO LEGION 5 16 RTX4070 Core I9 14900HX 64GB 1TB SSD W11 16.0QHD IPS - NON BUNDLING 32GB 1TB
- [paket] Terlaris Lenovo Ideapad Gaming 3 Ryzen 5 7535H 8GB 512SSD RTX4050 - Paket Medium RAM 16GB
#### laptop (pasangan komponen)

### Judul yang LOLOS tapi mengandung '+', '&', atau 'paketan' (total 10, beragam kategori, untuk inspeksi Dan)

- [gpu] b360 gaming + intel i7 9700 + intel i5 9400f
- [cpu] AMD CPU Ryzen 5 5600GT Tray + Fan New
- [ram] ram+ddr4+pc
- [storage] ssd+dan+hdd
- [motherboard] motherboard ASRock B560M-ITX/ac + Intel Pentium Gold G6400
- [laptop] Lenovo Legion Slim 5 16APH8 Ryzen 7 7840HS RTX 4050 6GB RAM 16GB SSD 512GB Untuk Gaming & Desain
- [gpu] vga sapphire nitro+ rx 6700xt fullset segel normal
- [cpu] CPU AMD RYZEN 5 3600 ada fan+box 6c/12t 65W
- [ram] Mobo RX7 H110 + i3 8100 + RAM DDR4 8GB 2400 Bonus HSF
- [storage] Ssd gen 3,4 1tb & 2tb

Baris diabaikan (kategori di luar latih, mis. pc): 3004.

## Filter aksesori/salah kategori (A3-2)

Diterapkan setelah filter bundle, dari JUDUL saja (lowercase, hyphen dinormalisasi jadi spasi). Baris dibuang bila judul DIAWALI kata aksesori, ATAU frasa aksesori muncul SEBELUM pola model komponen apa pun (model yang disebut hanya kompatibilitas). Daftar aksesori: fan, kipas, thermal paste, thermal pad, bracket, riser, backplate, waterblock, water block, baterai, charger, adaptor, adapter (varian ejaan adaptor), lcd, keyboard, engsel, casing, enclosure, converter. PENGECUALIAN: spek jumlah fan ('dual fan', 'triple fan', 'single fan', dan pola sejenis) dihapus dulu sebelum dicek, sehingga 'VGA RTX 3060 Dual Fan' lolos sementara 'Kipas VGA RTX 3060' dibuang. Khusus laptop: judul yang diawali ram/ssd/hdd/memory/sodimm dibuang (komponen salah kategori).

| kategori | dibuang aksesori | setelah aksesori |
|---|---|---|
| gpu | 35 | 2128 |
| cpu | 1 | 887 |
| ram | 0 | 592 |
| storage | 1 | 819 |
| motherboard | 0 | 597 |
| laptop | 139 | 4545 |

### Contoh judul dibuang filter aksesori (maks 15 per kategori)

#### gpu
- [aksesori:fan] fan replace untuk vga
- [aksesori:lcd] Lcd Ori Samsung a10s+frame (normal)
- [aksesori:converter] Converter Vention Type C to HDMI Display Adapter
- [aksesori:casing] CASING OLT ZXA10 C320 GPON 1G/10G AC BARU
- [aksesori:fan] Fan kipas Powercolor Fighter Rx 6700 xt 6600 5700 5500 xt 85mm 4pin DIY
- [aksesori:fan] Fan kipas Asrock Rx 6600 6650 xt Challenger 95mm 4pin DIY replacement
- [aksesori:fan] Fan kipas Vga Sapphire Nitro Rx 6600 6650 xt rx6600 Replacement 87cm 6pin
- [aksesori:fan] Fan Msi RTX 3060 3070 ventus 2x RX 6600 6700 xt mech 2x 95 4pin OEM
- [aksesori:fan] Fan kipas vga XFX Rx 6650 6600 xt Speedster QICK 308 75mm 4pin
- [aksesori:fan] Fan kipas Powercolor Red Devil Rx 6600 6650 xt 95 4pin DIY replacement
- [aksesori:fan] Fan vga Sapphire PULSE Rx 6600 6650 Xt 87mm 4pin OEM
- [aksesori:fan] Fan kipas Rx 6650 6600 XT Powercolor Hellhound 95mm 4pin DIY OEM
- [aksesori:fan] Fan kipas vga Powercolor Fighter Rx 6700 6650 6600 5500 5700 xt 85mm 4pin
- [aksesori:fan] Fan Kipas vga Sapphire Rx 6600 6650 Xt 87mm 4pin PULSE Langka
- [aksesori:fan] Fan Kipas Vga 95mm 5pin Asus Dual strix Rx 6600 6650 6700 6750 xt

#### cpu
- [aksesori:fan] FAN HSF AMD AM3+ RYZEN AM3 Original

#### ram

#### storage
- [aksesori:enclosure] Ssd enclosure 1tb

#### motherboard

#### laptop
- [laptop_awal_komponen] Ram laptop 16gb
- [laptop_awal_komponen] RAM Laptop DDR4 Sodimm 4GB
- [laptop_awal_komponen] Ram laptop sodimm ddr4 16gb 3200 Ori copotan merk Samsung ok
- [laptop_awal_komponen] RAM Laptop/SO-DIMM DDR4 16GB 3200Mhz 1.2V ADATA Normal Tested Fullset Packing
- [laptop_awal_komponen] Ram Laptop 16gb ddr4 pc 3200 New
- [laptop_awal_komponen] RAM LAPTOP DDR4 8GB
- [laptop_awal_komponen] Ram 8gb DDR5 5600Mhz Team Group Sodimm Laptop
- [laptop_awal_komponen] RAM Laptop KYO KAIZEN 16 GB
- [laptop_awal_komponen] Ram laptop sodimm ddr5 8giga
- [laptop_awal_komponen] RAM 8GB DDR4 3200 Transcend Normal Copotan Laptop
- [laptop_awal_komponen] Ram Laptop 8gb ddr4 pc 2666 normal copotan
- [laptop_awal_komponen] Ram laptop sodim DDR4 4 GB
- [laptop_awal_komponen] Ram 4gb ddr4 laptop Normal
- [laptop_awal_komponen] Ram laptop ddr4 8gb lifetime
- [laptop_awal_komponen] SSD NVMe M.2 512GB – Bikin Laptop & PC Lebih Cepat, Booting Kilat!

### Judul yang LOLOS tapi mengandung 'fan'/'kipas' (total 10, beragam kategori, bukti pengecualian bekerja)

- [gpu] VGA Colorfull BattleAX RTX 3060 12GB GDDR6 192Bit Dual Fan OC Mulus like new segel garansi 2028 mei
- [cpu] AMD CPU Ryzen 5 5600GT Tray + Fan New
- [motherboard] Mobo Asus prime h270-plus ddr4+proc i3 gen6 + fan
- [laptop] Laptop Asus TUF Gaming F15 FX506HCB, Intel i5-11400H, Gen 11Th, Ram 8Gb/Ram 16Gb/SSD 512Gb DualVga Nvdia GeForce RTX 3050 4Gb+intel UHD Graphics Keyboard Backlight Aura RGB Dual 83-Blade Fan
- [gpu] VGA ASUS TUF GeForce RTX 3060 12GB GAMING | 12GB DDR6 192Bit TRIPLE FAN
- [cpu] New AMD CPU Ryzen 5 5600 Tray No Fan
- [motherboard] Raptor X2000 RGB Fan CPU Cooler.
- [laptop] VGA DELL Alienware RTX 3070 8GB GDDR6 Dualfan mantap GPU Nvidia Geforce
- [gpu] Rtx 5060ti 16gb gainward 3fan
- [cpu] CPU AMD RYZEN 5 3600 ada fan+box 6c/12t 65W

## Inferensi kondisi (A3-3, tanpa drop)

Hanya baris Tokopedia dengan condition kosong yang diinferensi dari JUDUL: memuat second|2nd|bekas|seken|used|preloved|copotan (case-insensitive) -> 'second', selain itu 'new'. Disimpan sebagai kolom turunan condition_inferred di dataframe training (bukan di CSV). Facebook memakai label aslinya; kosong = unknown. Inferensi diterapkan SEBELUM baseline grup+kondisi dan fitur dummy. Di inferensi nanti, kondisi 'any' memakai cond_new_mean dan cond_second_mean dari defaults (bukan 0,0); Dart memakai logika yang sama di fase integrasi.

| kategori | Tokopedia kosong -> second | Tokopedia kosong -> new | cond_new_mean | cond_second_mean | src_tokopedia_mean |
|---|---|---|---|---|---|
| gpu | 10 | 1464 | 0.7624 | 0.2376 | 0.8786 |
| cpu | 2 | 731 | 0.911 | 0.08895 | 0.8737 |
| ram | 0 | 369 | 0.69 | 0.31 | 0.6503 |
| storage | 1 | 476 | 0.7081 | 0.2919 | 0.627 |
| motherboard | 0 | 489 | 0.8966 | 0.1034 | 0.8819 |
| laptop | 3 | 2716 | 0.3361 | 0.6639 | 0.3935 |

## Kecocokan katalog (match rate)

Denominator = baris kategori setelah dedupe + filter harga + filter placeholder + filter bundle + filter aksesori (populasi masuk ekstraksi).
- gpu: konsensus cocok 1672/2128 (78.6%); judul gagal cocok total 2.
- cpu: konsensus cocok 752/887 (84.8%); judul gagal cocok total 4.
- ram: lolos ekstraksi 559/592 (94.4%).
- storage: lolos ekstraksi 788/819 (96.2%).
- motherboard: lolos ekstraksi 489/597 (81.9%).
- laptop: CPU PassMark cocok 2575/4545 (56.7%); GPU (passmark) cocok 1422/4545 (31.3%); baris dengan sig dGPU 1423.

## Coverage CPU PassMark laptop: sebelum vs sesudah (A4)

SEBELUM = run laporan draft lama (20:39, regex lama); SESUDAH = run ini (regex baru). Denominator sama: baris laptop setelah dedupe + filter harga + placeholder + bundle + aksesori (populasi masuk ekstraksi). Baris final = setelah ekstraksi + IQR.

| | CPU cocok | coverage | baris final |
|---|---|---|---|
| SEBELUM | 1679/4545 | 36,9% | 840 |
| SESUDAH | 2575/4545 | 56.7% | 1080 |

Baris diselamatkan pola baru (di antara yang cocok SESUDAH, dihitung saat ekstraksi):

- bare_ix: 504
- core_no_i: 103
- ultra_3: 147
- apple: 142
- total pola baru: 896

Catatan pola: bare iX = 'iX + nomor' tanpa kata Core; Core tanpa i = 'Core 5/7/9 + nomor 3 digit'; ultra_3 = 'Ultra 5/7/9 + nomor 3 digit' (CPU_RE lama menuntut 4-5 digit); Apple = chip M1-M4 hanya bila konteks apple/macbook ada dan kunci eksaknya ada di katalog (kualifikasi pro/max hanya bila langsung mengikuti chip; 'M2 2280' ukuran SSD dilewati). Proksi famili+tier tidak menjangkau kunci 3 digit Core/Ultra karena CPU_RE kunci juga menuntut 4-5 digit — perilaku ini sama di Dart. Pola yang masih di luar cakupan: Ryzen AI, seri N, bare iX tanpa nomor model.

## Sanity fitur skor (Fase A2)

Populasi = baris setelah dedupe + filter harga + filter placeholder + filter bundle + filter aksesori (sebelum ekstraksi fitur). Median harga per model mencampur kondisi (new/second/unknown) — sanity monotonisitas, bukan evaluasi model. Lookup kedua skala memakai port yang sama (probe + squash), jadi perbandingan adil; kunci katalog yang cocok dicetak agar bisa dicek manual.

### GPU (kategori gpu) — skala terpilih: passmark (spearman interseksi lebih tinggi)

| model | kunci konsensus | skor konsensus | kunci passmark | skor passmark | n listing | median harga |
|---|---|---|---|---|---|---|
| rtx 3070 | nvidia rtx 3070 | 39.04 | geforce rtx 3070 | 2.208e+04 | 117 | Rp4.475.000 |
| rtx 3060 ti | nvidia rtx 3060-ti | 31.7 | geforce rtx 3060 ti | 2.023e+04 | 117 | Rp4.474.000 |
| gtx 1660 super | - | - | geforce gtx 1660 super | 1.266e+04 | 75 | Rp2.075.000 |
| rx 6700 xt | amd rx 6700-xt | 32.52 | radeon rx 6700 xt | 1.973e+04 | 70 | Rp3.960.000 |
| rtx 5060 | nvidia rtx 5060 | 36.84 | geforce rtx 5060 | 2.064e+04 | 65 | Rp8.100.000 |
| rtx 4060 | nvidia rtx 4060 | 28.97 | geforce rtx 4060 | 1.949e+04 | 64 | Rp5.538.500 |
| rtx 3060 | nvidia rtx 3060 | 75.41 | geforce rtx 3060 | 1.69e+04 | 62 | Rp8.160.500 |
| rtx 3080 | nvidia rtx 3080 | 52.1 | geforce rtx 3080 | 2.499e+04 | 60 | Rp6.725.000 |
| rx 7600 | - | - | radeon rx 7600 | 1.645e+04 | 58 | Rp5.477.500 |
| rtx 4070 super | - | - | geforce rtx 4070 super | 2.995e+04 | 58 | Rp11.470.004 |
| gtx 1650 | nvidia gtx 1650 | 40.98 | geforce gtx 1650 | 7868 | 55 | Rp1.650.000 |
| rtx 3070 ti | nvidia rtx 3070-ti | 43.51 | geforce rtx 3070 ti | 2.317e+04 | 54 | Rp4.805.000 |
| rx 6600 xt | amd rx 6600-xt | 19 | radeon rx 6600 xt | 1.644e+04 | 53 | Rp3.600.000 |
| rtx 5070 | nvidia rtx 5070 | 69.73 | geforce rtx 5070 | 2.866e+04 | 50 | Rp15.977.250 |
| rx 7800 xt | - | - | radeon rx 7800 xt | 2.445e+04 | 48 | Rp9.487.500 |
| rtx 4070 ti | nvidia rtx 4070-ti | 73.84 | geforce rtx 4070 ti | 3.154e+04 | 47 | Rp13.146.000 |
| rtx 3050 | nvidia rtx 3050 | 8.02 | geforce rtx 3050 6gb | 1.074e+04 | 46 | Rp5.249.500 |
| rtx 2060 | nvidia rtx 2060 | 65.98 | geforce rtx 2060 | 1.408e+04 | 46 | Rp2.600.000 |
| rx 6600 | amd rx 6600 | 14.07 | radeon rx 6600 | 1.505e+04 | 41 | Rp2.975.000 |
| arc a380 | - | - | intel arc a380 | 6320 | 35 | Rp3.035.000 |
| rtx 2080 ti | nvidia rtx 2080-ti | 82.79 | geforce rtx 2080 ti | 2.142e+04 | 33 | Rp1.823.700 |
| rtx 4080 | nvidia rtx 4080 | 80.92 | geforce rtx 4080 | 3.443e+04 | 32 | Rp18.975.000 |
| rx 6800 | amd rx 6800 | 83.61 | radeon rx 6800 | 2.206e+04 | 31 | Rp6.475.000 |
| rtx 4070 | nvidia rtx 4070 | 53.74 | geforce rtx 4070 | 2.687e+04 | 29 | Rp10.074.000 |
| rtx 4080 super | - | - | geforce rtx 4080 super | 3.422e+04 | 25 | Rp19.415.000 |
| rx 6650 xt | - | - | radeon rx 6650 xt | 1.711e+04 | 24 | Rp4.270.500 |
| rx 6800 xt | amd rx 6800-xt | 49.56 | radeon rx 6800 xt | 2.508e+04 | 24 | Rp5.397.500 |
| rx 7900 | amd rx 7900-xt | 62.44 | radeon rx 7900m | 2.224e+04 | 20 | Rp9.960.000 |
| rx 7700 xt | - | - | radeon rx 7700 xt | 2.276e+04 | 19 | Rp7.607.000 |
| rtx 2060 super | - | - | geforce rtx 2060 super | 1.646e+04 | 18 | Rp3.017.000 |
| rtx 5060 ti | - | - | geforce rtx 5060 ti 8gb | 2.193e+04 | 15 | Rp11.040.000 |
| rx 9060 xt | - | - | radeon rx 9060 xt 8gb | 1.974e+04 | 15 | Rp8.900.000 |
| rx 580 | amd rx 580 | 47.54 | radeon rx 580 | 8784 | 15 | Rp1.500.000 |
| rx 6750 xt | - | - | radeon rx 6750 xt | 2.069e+04 | 15 | Rp6.529.000 |
| gtx 1650 super | - | - | geforce gtx 1650 super | 1.02e+04 | 10 | Rp1.752.000 |
| arc a750 | - | - | intel arc a750 | 1.265e+04 | 10 | Rp4.002.000 |
| rx 570 | amd rx 5700 | 67.21 | radeon rx 5700 | 1.422e+04 | 8 | Rp1.137.500 |
| rtx 4060 ti | nvidia rtx 4060-ti | 85.25 | geforce rtx 4060 ti | 2.26e+04 | 8 | Rp6.855.500 |
| arc a770 | - | - | intel arc a770 | 1.335e+04 | 8 | Rp6.225.500 |
| rx 7900 xt | amd rx 7900-xt | 62.44 | radeon rx 7900 xt | 2.911e+04 | 7 | Rp8.195.000 |
| rtx 5070 ti | nvidia rtx 5070-ti | 81.56 | geforce rtx 5070 ti | 3.234e+04 | 7 | Rp15.474.000 |
| rx 7600 xt | - | - | radeon rx 7600 xt | 1.735e+04 | 6 | Rp6.137.500 |
| gtx 1060 | nvidia gtx 1060-3gb | 56.56 | geforce gtx 1060 | 1.003e+04 | 5 | Rp1.250.000 |
| gtx 1070 | nvidia gtx 1070 | 63.11 | geforce gtx 1070 | 1.351e+04 | 5 | Rp1.950.000 |
| gtx 1050 ti | nvidia gtx 1050-ti | 40.16 | geforce gtx 1050 ti | 6366 | 5 | Rp1.250.000 |
| rtx 5050 | nvidia rtx 5050 | 23.88 | geforce rtx 5050 | 1.681e+04 | 4 | Rp7.450.000 |
| rx 6500 xt | amd rx 6500-xt | 54.92 | radeon rx 6500 xt | 9624 | 4 | Rp2.038.500 |
| rtx 2080 | nvidia rtx 2080 | 76.64 | geforce rtx 2080 | 1.857e+04 | 3 | Rp849.200 |
| gtx 1660 | nvidia gtx 1660 | 58.2 | geforce gtx 1660 | 1.161e+04 | 3 | Rp1.900.000 |
| gtx 1050 | nvidia gtx 1050 | 31.15 | geforce gtx 1050 | 5051 | 3 | Rp7.000.000 |
| rx 6950 xt | - | - | radeon rx 6950 xt | 2.806e+04 | 3 | Rp7.578.768 |
| arc a310 | - | - | intel arc a310 | 5459 | 3 | Rp1.718.180 |
| rtx 5080 | nvidia rtx 5080 | 92.45 | geforce rtx 5080 | 3.562e+04 | 2 | Rp29.000.000 |
| rx 5500 xt | amd rx 5500-xt | 49.18 | radeon rx 5500 xt | 9055 | 2 | Rp1.800.000 |
| gtx 1660 ti | nvidia gtx 1660-ti | 59.84 | geforce gtx 1660 ti | 1.258e+04 | 2 | Rp8.135.000 |
| rx 560 | amd rx 560 | 18.03 | radeon rx 560 | 3684 | 2 | Rp1.010.000 |
| rx 460 | amd rx 460 | 22.95 | radeon rx 460 | 4097 | 2 | Rp725.000 |
| rx 9070 | - | - | radeon rx 9070 | 2.537e+04 | 2 | Rp11.856.320 |
| rx 9070 xt | - | - | radeon rx 9070 xt | 2.691e+04 | 2 | Rp9.721.000 |
| rtx 2070 | nvidia rtx 2070 | 71.72 | geforce rtx 2070 | 1.606e+04 | 2 | Rp505.153 |
| arc b580 | - | - | intel arc b580 | 1.605e+04 | 2 | Rp6.379.500 |
| rtx a3000 | - | - | rtx a3000 laptop gpu | 1.257e+04 | 1 | Rp17.075.000 |
| gtx 960 | nvidia gtx 960 | 39.34 | geforce gtx 960 | 6148 | 1 | Rp650.000 |
| gtx 1080 | nvidia gtx 1080 | 69.67 | geforce gtx 1080 | 1.561e+04 | 1 | Rp2.200.000 |
| rx 5700 xt | amd rx 5700-xt | 70.49 | radeon rx 5700 xt | 1.605e+04 | 1 | Rp2.400.000 |
| rx 5700 | amd rx 5700 | 67.21 | radeon rx 5700 | 1.422e+04 | 1 | Rp1.900.000 |
| rx 480 | amd rx 480 | 45.9 | radeon rx 480 | 8527 | 1 | Rp1.500.000 |
| rtx 6900 xt | - | - | - | - | 1 | Rp7.500.000 |
| rtx 2050 | - | - | geforce rtx 2050 | 7720 | 1 | Rp101.010 |
| gtx 750 | nvidia gtx 750 | 15.57 | geforce gtx 750 | 3289 | 1 | Rp500.000 |
| gtx 1070 ti | nvidia gtx 1070-ti | 68.03 | geforce gtx 1070 ti | 1.467e+04 | 1 | Rp2.100.000 |
| gtx 750 ti | nvidia gtx 750-ti | 18.85 | geforce gtx 750 ti | 3900 | 1 | Rp750.000 |
| rx 550 | amd rx 550 | 11.48 | radeon rx 550 | 2701 | 1 | Rp800.000 |
| rtx 4050 | - | - | geforce rtx 4050 laptop gpu | 1.422e+04 | 1 | Rp15.700.000 |
| rx 6550 xt | - | - | - | - | 1 | Rp4.547.000 |
| gtx 1080 ti | nvidia gtx 1080-ti | 77.87 | geforce gtx 1080 ti | 1.86e+04 | 1 | Rp10.000.000 |
| rtx 2080 super | - | - | geforce rtx 2080 super | 1.94e+04 | 1 | Rp372.698 |
| rtx 3080 ti | nvidia rtx 3080-ti | 61.03 | geforce rtx 3080 ti | 2.674e+04 | 1 | Rp7.786.000 |
| rtx 3090 | nvidia rtx 3090 | 66.61 | geforce rtx 3090 | 2.649e+04 | 1 | Rp11.975.000 |

### CPU (kategori cpu) — skala terpilih: passmark (spearman interseksi lebih tinggi)

| model | kunci konsensus | skor konsensus | kunci passmark | skor passmark | n listing | median harga |
|---|---|---|---|---|---|---|
| core i3 12100f | intel core i3-12100f | 69.55 | intel core i3-12100f | 1.395e+04 | 54 | Rp1.874.001 |
| ryzen 5 7500f | - | - | amd ryzen 5 7500f | 2.653e+04 | 52 | Rp2.585.500 |
| ryzen 7 5700x | amd ryzen 7 5700x | 65.35 | amd ryzen 7 5700x | 2.656e+04 | 47 | Rp3.113.000 |
| core i7 12700f | intel core i7-12700f | 76.01 | intel core i7-12700f | 3.014e+04 | 44 | Rp5.144.635 |
| core i9 12900k | intel core i9-12900k | 84.44 | intel core i9-12900k | 4.112e+04 | 41 | Rp8.075.000 |
| core i5 14400f | intel core i5-14400f | 66.56 | intel core i5-14400f | 2.546e+04 | 40 | Rp3.219.950 |
| ryzen 5 5600x | amd ryzen 5 5600x | 57.7 | amd ryzen 5 5600x | 2.182e+04 | 39 | Rp2.474.001 |
| core i5 12400f | intel core i5-12400f | 58.7 | intel core i5-12400f | 1.968e+04 | 37 | Rp2.425.000 |
| ryzen 5 5600 | amd ryzen 5 5600 | 57.91 | amd ryzen 5 5600 | 2.149e+04 | 36 | Rp2.074.000 |
| ryzen 5 5600g | amd ryzen 5 5600g | 72.71 | amd ryzen 5 5600g | 1.963e+04 | 36 | Rp2.668.500 |
| ryzen 9 5900x | amd ryzen 9 5900x | 79.41 | amd ryzen 9 5900x | 3.889e+04 | 34 | Rp6.104.500 |
| core i5 13400f | intel core i5-13400f | 65.74 | intel core i5-13400f | 2.49e+04 | 33 | Rp3.185.000 |
| ryzen 5 7600 | amd ryzen 5 7600 | 68.35 | amd ryzen 5 7600 | 2.697e+04 | 32 | Rp3.522.500 |
| core i7 13700f | intel core i7-13700f | 84.28 | intel core i7-13700f | 3.775e+04 | 32 | Rp5.624.500 |
| core i3 13100f | intel core i3-13100f | 72.56 | intel core i3-13100f | 1.466e+04 | 31 | Rp1.825.000 |
| ryzen 5 4600g | - | - | amd ryzen 5 4600g | 1.593e+04 | 28 | Rp1.909.500 |
| ryzen 7 5800x | amd ryzen 7 5800x | 68.61 | amd ryzen 7 5800x | 2.766e+04 | 25 | Rp4.257.000 |
| ryzen 5 7600x | amd ryzen 5 7600x | 60.58 | amd ryzen 5 7600x | 2.827e+04 | 21 | Rp3.665.000 |
| ryzen 9 5950x | amd ryzen 9 5950x | 83.47 | amd ryzen 9 5950x | 4.526e+04 | 9 | Rp7.987.370 |
| ryzen 5 5600gt | amd ryzen 5 5600gt | 55.12 | amd ryzen 5 5600gt | 2.013e+04 | 5 | Rp2.850.000 |
| core i9 12900kf | intel core i9-12900kf | 84.49 | intel core i9-12900kf | 4.05e+04 | 5 | Rp7.533.305 |
| ryzen 5 5500 | amd ryzen 5 5500 | 71.75 | amd ryzen 5 5500 | 1.925e+04 | 4 | Rp1.550.000 |
| ryzen 7 7700 | amd ryzen 7 7700 | 78 | amd ryzen 7 7700 | 3.432e+04 | 4 | Rp4.369.500 |
| ryzen 9 7900x | amd ryzen 9 7900x | 77.73 | amd ryzen 9 7900x | 5.123e+04 | 3 | Rp8.050.000 |
| core i7 14700f | intel core i7-14700f | 88.66 | intel core i7-14700f | 4.131e+04 | 3 | Rp6.050.000 |
| ryzen 7 5700 | amd ryzen 7 5700x | 65.35 | amd ryzen 7 5700 | 2.421e+04 | 3 | Rp2.334.001 |
| ryzen 7 5800xt | amd ryzen 7 5800xt | 60.03 | amd ryzen 7 5800xt | 2.805e+04 | 3 | Rp4.474.000 |
| core i9 12900ks | intel core i9-12900ks | 87.51 | intel core i9-12900ks | 4.337e+04 | 3 | Rp8.374.001 |
| ryzen 7 5700g | amd ryzen 7 5700g | 61.46 | amd ryzen 7 5700g | 2.423e+04 | 2 | Rp8.378.500 |
| core i5 14400 | intel core i5-14400 | 54.42 | intel core i5-14400 | 2.507e+04 | 2 | Rp3.312.500 |
| ryzen 7 3700x | amd ryzen 7 3700x | 71.29 | amd ryzen 7 3700x | 2.238e+04 | 2 | Rp1.422.000 |
| core i3 10105f | - | - | intel core i3-10105f @ 3.70ghz | 8866 | 2 | Rp1.337.500 |
| ryzen 5 3500 | amd ryzen 5 3500 | 59 | amd ryzen 5 3500 | 1.275e+04 | 2 | Rp937.500 |
| ryzen 3 3200g | amd ryzen 3 3200g | 39.02 | amd ryzen 3 3200g | 6974 | 2 | Rp1.125.000 |
| ryzen 5 5500gt | amd ryzen 5 5500gt | 79.97 | amd ryzen 5 5500gt | 1.902e+04 | 2 | Rp2.565.450 |
| core i5 13400 | intel core i5-13400 | 66.55 | intel core i5-13400 | 2.389e+04 | 2 | Rp1.705.000 |
| ryzen 7 2700x | amd ryzen 7 2700x | 61.62 | amd ryzen 7 2700x | 1.742e+04 | 1 | Rp1.350.000 |
| ryzen 5 1600 | amd ryzen 5 1600 | 51.31 | amd ryzen 5 1600 | 1.225e+04 | 1 | Rp500.000 |
| ryzen 5 3500x | amd ryzen 5 3500x | 61.43 | amd ryzen 5 3500x | 1.316e+04 | 1 | Rp5.000.000 |
| ryzen 5 3600 | amd ryzen 5 3600 | 65.05 | amd ryzen 5 3600 | 1.765e+04 | 1 | Rp1.450.000 |
| ryzen 7 8700g | amd ryzen 7 8700g | 73.33 | amd ryzen 7 8700g | 3.148e+04 | 1 | Rp3.700.000 |
| core i5 4570 | intel core i5-4570 | 38.53 | intel core i5-4570 @ 3.20ghz | 5226 | 1 | Rp1.000.000 |
| core i5 4590 | intel core i5-4590 | 40.28 | intel core i5-4590 @ 3.30ghz | 5380 | 1 | Rp250.000 |
| ryzen 7 3800x | amd ryzen 7 3800x | 72.39 | amd ryzen 7 3800x | 2.296e+04 | 1 | Rp2.874.000 |
| core i5 11400f | intel core i5-11400f | 53.71 | intel core i5-11400f @ 2.60ghz | 1.687e+04 | 1 | Rp2.074.000 |
| core i3 14100f | intel core i3-14100f | 73.25 | intel core i3-14100f | 1.54e+04 | 1 | Rp1.490.800 |
| ryzen 5 3600x | amd ryzen 5 3600x | 66.95 | amd ryzen 5 3600x | 1.812e+04 | 1 | Rp1.250.000 |
| ryzen 3 3100 | - | - | amd ryzen 3 3100 | 1.151e+04 | 1 | Rp700.000 |
| ryzen 5 2400g | amd ryzen 5 2400g | 44.88 | amd ryzen 5 2400g | 8719 | 1 | Rp800.000 |
| ryzen 5 1500x | amd ryzen 5 1500x | 49.03 | amd ryzen 5 1500x | 9067 | 1 | Rp4.650.000 |
| ryzen 5 2600 | amd ryzen 5 2600 | 53.91 | amd ryzen 5 2600 | 1.312e+04 | 1 | Rp850.000 |
| ryzen 3 2200g | amd ryzen 3 2200g | 40.93 | amd ryzen 3 2200g | 6706 | 1 | Rp450.000 |
| ryzen 5 9600x | amd ryzen 5 9600x | 70.27 | amd ryzen 5 9600x | 3.008e+04 | 1 | Rp3.250.000 |
| ryzen 5 8400f | amd ryzen 5 8400f | 46.78 | amd ryzen 5 8400f | 2.439e+04 | 1 | Rp1.650.000 |
| core i7 6700 | intel core i7-6700 | 52.47 | intel core i7-6700 @ 3.40ghz | 8033 | 1 | Rp900.000 |
| ryzen 7 9700x | amd ryzen 7 9700x | 84.05 | amd ryzen 7 9700x | 3.696e+04 | 1 | Rp4.100.000 |
| core i5 12400 | intel core i5-12400 | 56.48 | intel core i5-12400 | 1.882e+04 | 1 | Rp2.750.000 |
| ryzen 7 5000 | - | - | - | - | 1 | Rp7.424.000 |
| ryzen 7 8700f | amd ryzen 7 8700f | 73.03 | amd ryzen 7 8700f | 3.088e+04 | 1 | Rp2.790.000 |
| ryzen 5 8500g | amd ryzen 5 8500g | 82.14 | amd ryzen 5 8500g | 2.138e+04 | 1 | Rp3.983.000 |
| ryzen 7 7000 | - | - | - | - | 1 | Rp7.984.000 |
| ryzen 7 78003xd | - | - | - | - | 1 | Rp7.925.000 |
| ryzen 9 9950x | amd ryzen 9 9950x | 94.44 | amd ryzen 9 9950x | 6.571e+04 | 1 | Rp10.689.000 |
| ryzen 9 9000 | - | - | - | - | 1 | Rp13.273.900 |
| ryzen 9 3900x | amd ryzen 9 3900x | 77.72 | amd ryzen 9 3900x | 3.248e+04 | 1 | Rp2.975.000 |
| ryzen 9 3900xt | amd ryzen 9 3900xt | 69.85 | amd ryzen 9 3900xt | 3.247e+04 | 1 | Rp3.965.001 |
| ryzen 9 3950x | amd ryzen 9 3950x | 74.85 | amd ryzen 9 3950x | 3.841e+04 | 1 | Rp5.575.000 |
| core i5 13500 | intel core i5-13500 | 75.97 | intel core i5-13500 | 3.078e+04 | 1 | Rp1.696.240 |
| core i7 14700k | intel core i7-14700k | 87.64 | intel core i7-14700k | 5.195e+04 | 1 | Rp5.674.000 |
| core i7 13700 | intel core i7-13700 | 82.4 | intel core i7-13700 | 3.587e+04 | 1 | Rp5.234.000 |
| core i9 13900k | intel core i9-13900k | 90.23 | intel core i9-13900k | 5.809e+04 | 1 | Rp9.640.000 |
| ryzen 5 3400g | amd ryzen 5 3400g | 47.89 | amd ryzen 5 3400g | 9162 | 1 | Rp1.135.000 |

### GPU laptop (kategori laptop) — skala terpilih: passmark (spearman interseksi lebih tinggi)

| model | kunci konsensus | skor konsensus | kunci passmark | skor passmark | n listing | median harga |
|---|---|---|---|---|---|---|
| rtx 3050 | nvidia rtx 3050 | 8.02 | geforce rtx 3050 6gb | 1.074e+04 | 506 | Rp12.999.500 |
| rtx 4050 | - | - | geforce rtx 4050 laptop gpu | 1.422e+04 | 273 | Rp16.800.000 |
| rtx 4060 | nvidia rtx 4060 | 28.97 | geforce rtx 4060 | 1.949e+04 | 168 | Rp17.137.000 |
| rtx 2050 | - | - | geforce rtx 2050 | 7720 | 158 | Rp10.642.500 |
| rtx 3060 | nvidia rtx 3060 | 75.41 | geforce rtx 3060 | 1.69e+04 | 99 | Rp13.000.000 |
| gtx 1650 | nvidia gtx 1650 | 40.98 | geforce gtx 1650 | 7868 | 93 | Rp7.800.000 |
| rtx 5050 | nvidia rtx 5050 | 23.88 | geforce rtx 5050 | 1.681e+04 | 86 | Rp20.999.000 |
| rtx 5060 | nvidia rtx 5060 | 36.84 | geforce rtx 5060 | 2.064e+04 | 56 | Rp27.405.870 |
| rtx 4070 | nvidia rtx 4070 | 53.74 | geforce rtx 4070 | 2.687e+04 | 50 | Rp25.265.445 |
| gtx 1050 | nvidia gtx 1050 | 31.15 | geforce gtx 1050 | 5051 | 43 | Rp6.250.000 |
| rtx 3050 ti | - | - | geforce rtx 3050 ti laptop gpu | 1.006e+04 | 30 | Rp14.507.000 |
| gtx 1050 ti | nvidia gtx 1050-ti | 40.16 | geforce gtx 1050 ti | 6366 | 26 | Rp6.615.450 |
| gtx 1650 ti | - | - | geforce gtx 1650 ti | 7536 | 21 | Rp7.728.000 |
| rtx 2060 | nvidia rtx 2060 | 65.98 | geforce rtx 2060 | 1.408e+04 | 19 | Rp10.475.000 |
| rtx 3070 | nvidia rtx 3070 | 39.04 | geforce rtx 3070 | 2.208e+04 | 17 | Rp16.000.000 |
| gtx 1660 ti | nvidia gtx 1660-ti | 59.84 | geforce gtx 1660 ti | 1.258e+04 | 15 | Rp10.000.000 |
| rtx 5070 | nvidia rtx 5070 | 69.73 | geforce rtx 5070 | 2.866e+04 | 15 | Rp29.600.000 |
| rtx 3070 ti | nvidia rtx 3070-ti | 43.51 | geforce rtx 3070 ti | 2.317e+04 | 11 | Rp18.250.000 |
| rtx 3080 | nvidia rtx 3080 | 52.1 | geforce rtx 3080 | 2.499e+04 | 8 | Rp18.350.000 |
| gtx 1060 | nvidia gtx 1060-3gb | 56.56 | geforce gtx 1060 | 1.003e+04 | 7 | Rp6.825.000 |
| rtx 4080 | nvidia rtx 4080 | 80.92 | geforce rtx 4080 | 3.443e+04 | 4 | Rp38.219.000 |
| rtx 2070 | nvidia rtx 2070 | 71.72 | geforce rtx 2070 | 1.606e+04 | 3 | Rp9.850.000 |
| rtx 5070 ti | nvidia rtx 5070-ti | 81.56 | geforce rtx 5070 ti | 3.234e+04 | 3 | Rp36.250.000 |
| gtx 950 | nvidia gtx 950 | 31.97 | geforce gtx 950 | 5355 | 2 | Rp3.925.000 |
| gtx 1650 super | - | - | geforce gtx 1650 super | 1.02e+04 | 2 | Rp3.337.500 |
| gtx 1660 | nvidia gtx 1660 | 58.2 | geforce gtx 1660 | 1.161e+04 | 2 | Rp10.215.450 |
| rx 6600 | amd rx 6600 | 14.07 | radeon rx 6600 | 1.505e+04 | 1 | Rp9.000.000 |
| rx 560 | amd rx 560 | 18.03 | radeon rx 560 | 3684 | 1 | Rp1.999.999 |
| rx 6700 xt | amd rx 6700-xt | 32.52 | radeon rx 6700 xt | 1.973e+04 | 1 | Rp3.974.950 |
| rtx 4090 | nvidia rtx 4090 | 97.12 | geforce rtx 4090 | 3.804e+04 | 1 | Rp51.000.000 |
| rtx a2000 | - | - | rtx a2000 | 1.342e+04 | 1 | Rp22.500.000 |
| rtx 2070 super | - | - | geforce rtx 2070 super | 1.812e+04 | 1 | Rp12.500.000 |
| rtx a4500 | - | - | rtx a4500 | 2.064e+04 | 1 | Rp27.000.000 |
| gtx 2050 | - | - | - | - | 1 | Rp10.500.000 |
| rx 9070 xt | - | - | radeon rx 9070 xt | 2.691e+04 | 1 | Rp20.990.000 |
| rx 9060 xt | - | - | radeon rx 9060 xt 8gb | 1.974e+04 | 1 | Rp14.009.000 |
| rtx 5090 | nvidia rtx 5090 | 91.07 | geforce rtx 5090 | 3.898e+04 | 1 | Rp99.699.000 |
| rx 6700 | amd rx 6700-xt | 32.52 | radeon rx 6700 | 1.89e+04 | 1 | Rp15.309.000 |
| rtx 3060 ti | nvidia rtx 3060-ti | 31.7 | geforce rtx 3060 ti | 2.023e+04 | 1 | Rp14.975.000 |
| rtx 1000 | - | - | rtx 1000 ada generation laptop gpu | 1.359e+04 | 1 | Rp5.925.000 |
| gtx 960 | nvidia gtx 960 | 39.34 | geforce gtx 960 | 6148 | 1 | Rp4.775.000 |
| rtx a500 | - | - | rtx a5000 | 2.286e+04 | 1 | Rp15.815.000 |
| arc b390 | - | - | intel arc b390 gpu | 8927 | 1 | Rp75.999.000 |

### Spearman(skor, median harga per model)

| kolom | skala | n model cocok | coverage baris | spearman (set sendiri) | spearman (interseksi) |
|---|---|---|---|---|---|
| gpu | konsensus | 52 | 72.7% | 0.3815 | 0.3815 |
| gpu | passmark | 77 | 99.9% | 0.7435 | 0.7982 |
| cpu | konsensus | 64 | 88.5% | 0.7024 | 0.7024 |
| cpu | passmark | 68 | 99.5% | 0.8406 | 0.8342 |
| laptop_gpu | konsensus | 29 | 71.6% | 0.4808 | 0.4808 |
| laptop_gpu | passmark | 42 | 99.9% | 0.752 | 0.8966 |

### 10 GPU populer (cek manual urutan skor)

| model | skor konsensus | skor passmark (G3D) | n listing | median harga |
|---|---|---|---|---|
| rtx 3050 | 8.02 | 1.074e+04 | 46 | Rp5.249.500 |
| rtx 3060 | 75.41 | 1.69e+04 | 62 | Rp8.160.500 |
| rtx 3060 ti | 31.7 | 2.023e+04 | 117 | Rp4.474.000 |
| rtx 4060 | 28.97 | 1.949e+04 | 64 | Rp5.538.500 |
| rtx 4060 ti | 85.25 | 2.26e+04 | 8 | Rp6.855.500 |
| rtx 4070 | 53.74 | 2.687e+04 | 29 | Rp10.074.000 |
| rx 6600 | 14.07 | 1.505e+04 | 41 | Rp2.975.000 |
| rx 6700 xt | 32.52 | 1.973e+04 | 70 | Rp3.960.000 |
| gtx 1650 | 40.98 | 7868 | 55 | Rp1.650.000 |
| gtx 1660 super | - | 1.266e+04 | 75 | Rp2.075.000 |

### Keputusan skala per kolom (diimplementasikan di skrip)

- gpu: pakai passmark (alasan: spearman interseksi lebih tinggi). Coverage konsensus 72.7% vs passmark 99.9%; Spearman interseksi konsensus 0.3815 vs passmark 0.7982.
- cpu: pakai passmark (alasan: spearman interseksi lebih tinggi). Coverage konsensus 88.5% vs passmark 99.5%; Spearman interseksi konsensus 0.7024 vs passmark 0.8342.
- laptop_gpu: pakai passmark (alasan: spearman interseksi lebih tinggi). Coverage konsensus 71.6% vs passmark 99.9%; Spearman interseksi konsensus 0.4808 vs passmark 0.8966.
- Konsekuensi Dart (fase integrasi): kolom yang pilihannya passmark HARUS membaca benchmark_scores.json (G3D untuk GPU, CPU Mark untuk CPU) dengan nama fitur ln_passmark / ln_gpu_passmark; kolom yang pilihannya konsensus tetap membaca consensus_scores.json dengan nama fitur ln_consensus / ln_gpu_consensus. CPU laptop tetap PassMark (keputusan Fase A, tidak diubah di sini).

## Storage: distribusi tipe + investigasi type_hdd

Urutan keputusan klasifikasi (Fase A2): (1) token nvme/pcie yang tidak dinegasikan -> nvme (negasi = bukan/non/no/tanpa yang langsung mendahului atau terhubung tanda hubung; negasi yang sama berlaku untuk sata, dianggap tidak ada); (2) token sata eksplisit -> sata_ssd WALAU ada m.2; (3) ada m.2 tapi tidak ada nvme/pcie/sata -> DIBUANG (m2_tanpa_tipe), token ssd saja tidak menyelamatkan — pilihan ini eksplisit supaya Dan bisa membatalkannya dalam satu kalimat; (4) token ssd tanpa m.2 -> sata_ssd; (5) token hdd/harddisk/hardisk -> hdd; (6) sisanya -> buang.

Distribusi tipe baris storage FINAL: {'nvme': 347, 'sata_ssd': 258, 'hdd': 135}.

Corong baris storage yang mengandung token hdd/harddisk/hardisk (judul ATAU spec): mentah 200, setelah dedupe 200, setelah harga 199, setelah bundle 187, setelah aksesori 187, final (lolos ekstraksi + IQR) 174.

Investigasi type_hdd: baris storage 'hdd murni' (hanya token hdd/harddisk/hardisk, tanpa nvme/pcie/sata/ssd/m.2) setelah bundle = 147; distribusi tipe final = {'nvme': 347, 'sata_ssd': 258, 'hdd': 135}. Dua mekanisme yang mengecilkan hdd: (1) prioritas token — judul keyword-stuffed yang menyebut ssd/nvme/sata sekaligus hdd diklasifikasikan ke tipe prioritas lebih tinggi, bukan hdd; (2) aturan m.2 Fase A2 — judul 'M.2 HDD' tanpa nvme/sata kini dibuang, bukan ditebak. Pada Fase A (data lama) type_hdd kosong karena baris HDD bersih memang hampir tidak ada setelah kedua mekanisme itu; pada data baru ini, angka final di atas yang berlaku.

## Kebocoran ekstraksi (sampel acak, seed 42)

Perluasan regex dari sampel bocor TIDAK diterapkan pada run ini. Alasannya ada di analisis pola di bawah: pola sistematis yang ditemukan adalah keterbatasan yang SAMA di sisi Dart (regex Dart _cpuRe/_modelTokens juga tidak menangani pola itu), sehingga memperluas hanya di Python akan merusak paritas latih/inferensi. Pola-pola itu dicatat sebagai kandidat perbaikan BERSAMA Python+Dart di Fase C, bukan di sini.

### gpu — alasan model_tidak_ditemukan (454 judul total)
- Samsung Galaxy A16 5G 8GB/256GB Extra Bonus - BERGARANSI RESMI
- Radio Tape CD Player Philips Vintage Boombox Stereo Bekas - CD Tape Normal Sound Mantap AZ1565
- samsung a16 8/128 5000mAh lengkap barang mulus
- Samsung A16 4G Ram 8GB Rom 128GB Segel Original
- Samsung Galaxy A08 [4/128GB] - Processor Helio G99+ (6nm) | 6000mAh
- AMD A10-Series A10 7870 A10-7870K A10 7870K 3.9 GHz Quad-Core CPU
- samsung A10 resmi
- GIGABYTE GeForce RTX­­ 4060 WINDFORCE OC 8GB GDDR6
- HANDPHONE - Samsung Galaxy A16 4G Ram 8/128gb
- KREDIT HP OPPO | TANPA DP | SYARAT MUDAH | CICILAN MURAH | AREA JOGJA
- Samsung Galaxy A16 5G dan A16 LTE | NFC | 5000mAh | (6/128GB) ORI SEIN
- Samsung Galaxy Tab A 10 inc
- Ocypus Gamma A40 ARGB
- Samsung A 16 Garansi Resmi SEIN
- New AE10 Drone 8K Dual Camera GPS Obstac Avoidan
- Jual Oppo A16k+charger
- Samsung A16 4G Ram 8/128
- Ocypus Gamma F12 ARGB (Reverse 2x, Forward 2x) Take all
- PreOrder Yeston Amd Radeon Rx 7900Xtx-24Gd6 Sakura Sugar 5 Nano High End
- AMD A10-Series A10-7800 A10 7800 3.5GHz Used Quad-Core CPU AD7800YBI44JA / AD780BYBI44JA Socket FM2+

### laptop — alasan cpu_passmark_tidak_cocok (1970 judul total)
- LAPTOP VIVOBOOK PRO 14 M3401Q |PROCESSOR AMD RYZEN 5 |RTX 3050 |RAM 8GB |SSD 512GB
- Laptop tipis Asus Vivobook E410K intel n4500 Ram 4gb ssd nvme 512gb NumberPad segel
- Kingston KCP556SS8/16 RAM Sodimm 16GB DDR5 5600MHz - RAM Memory Module Laptop Mini PC
- Asus Vivobook M415DAP AMD Athlon Gold 3150U RAM 4GB SSD 512GB FHD Bakclit
- ASUS TUF Gaming GT502 ATX Case
- Bestoss M2 NVME SSD Speed 2000MB/s 128GB 256GB 512GB 1TB M.2 PCIe 3.0 Solid State Drives for Notebook
- Sale4Per8 /16GB LAPTOP Desktop RAM PUSKILL DDR3 DDR3L DDR4 PC3L
- Laptop Acer Aspire 3 Amd Athlon Silver 3050U
- Asus A416J i3 Gen 10 ram 4/512gb
- Harddisk 1Tb Seagate copotan laptop sentinel 100%
- [Bekas] Laptop Lenovo Thinkpad T14 / T14S / L14 / L15 / T15 Core i5/i7 - Layar 14" Inch BERGARANSI
- ASUS A416JAO Grey Core i3-1005G1 Ram 8 SSD 256 FHD Backlit Laptop Baterai Layar
- INFINIX INBOOK I5 14.0 FHD 8GB 512GB SSD KEYB BACKLIGHT !!
- LENOVO IDEAPAD GAMING 3i 15IAH7 RTX 3050 16GB RAM 512GB SSD FHD 165 Hz || not Legion LOQ 15
- TEAMGROUP Team-Elite DDR4 8GB 3200MT/s Ram Laptop
- Laptop Lenovo Loq 15 12450HX RTX 3050
- LENOVO Yoga Slim 7 14AKP10 14 TOUCH RYZEN AI 5 340 16GB 512GB W11+OHS 14" 2.8K OLED 120HZ
- 51% [Toshiba Japan] KIOXIA Exceria Basic SSD NVMe 1TB PCIe 4.0 x4 Up to 7200MB/s M.2 2280 Internal SSD M2 NVMe - Garansi 5 tahun compatible cocok untuk PC laptop
- M.2 990 pro 4TB 2TB 1TB Hard drive disk NVME 2.5 inch ssd TLC 5600MB/s internal Solid State Drives for laptop and desktop
- Harddisk Laptop WD Blue 1TB

### Pola di dalam judul bocor (hitung prioritas, satu judul satu pola)

GPU model_tidak_ditemukan: lainnya: 211; mini_pc: 2; ponsel/tablet/dll: 238; sufiks_xtx: 3.

Laptop cpu_passmark_tidak_cocok: apple_m1_m2: 34; bare_ix_tanpa_core: 124; core_tanpa_i: 1; lainnya: 1728; ryzen_ai: 36; seri_n: 6; tanpa_angka_model: 41.

## Judul GPU/CPU yang gagal cocok (maks 15 per kategori)

### gpu (2 judul gagal total)
- Vga rtx 6900 xt 16gb MSI gaming x trio
- Powercolor RX 6550xt hellhound sakura | vga rx6650xt fan pink edition

### cpu (4 judul gagal total)
- AMD RYZEN 7 5800X3D | Ryzen 7 5000 Series AM4 Anniversary Edition
- AMD Ryzen 7 7800X3D Gaming Processor | Ryzen 7 7000 Series 8-Core AM5
- AMD RYZEN 7 78003XD Gaming Processor Ryzen 7 7800 X3D AM5 CPU
- AMD Ryzen 9 9950X3D Gaming Processor | Ryzen 9 9000 Series AM5

## Penyimpangan dari brief / keputusan yang dikunci

- Pencocokan konsensus dari token model berspasi dulu, bukan judul mentah (judul mentah terbukti gagal karena prefix vendor di kunci katalog).
- CPU laptop konsisten skala PassMark (cpu_mobile, lalu cpu desktop, lalu proksi famili+tier resolveCpuLaptop); GPU laptop tetap konsensus; tiap kolom satu skala.
- Baris laptop dengan sig dGPU ditemukan tapi konsensus gagal dibuang (ln_gpu tidak terdefinisi). Baris laptop tanpa sig dGPU dianggap has_dgpu=0, ln_gpu=0.0.
- Grup dari fitur final (setelah imputasi); RAM 2x8GB masuk grup 16GB; storage 1TB masuk grup 1000GB.
- IQR memakai persentil linear numpy, bukan metode indeks engine Dart (sisi latih, bukan port engine).
- Storage kategori memakai parse GB/TB umum; storage laptop memakai port _extractStorageFromText (daftar ukuran tetap) agar selaras dengan helper inferensi.
- VRAM diimputasi median per model; speed RAM diimputasi median per DDR (fallback median global). defaults di JSON berisi median kategori (vram) dan median global + per-DDR (speed).
- sigma_log = std residual out-of-fold evaluasi (a), bukan residual training.
- Storage tanpa kata tipe dibuang dan dihitung; prioritas tipe nvme > sata_ssd > hdd; is_sodimm hanya dari token sodimm/so-dimm; motherboard tanpa usaha ekstra (chipset + kondisi saja), gerbang yang memutuskan.
- Filter bundle/rakitan Dan diterapkan setelah filter harga, sebelum ekstraksi dan IQR (penanda frasa + kombo judul GPU+CPU+RAM, kecuali laptop untuk kombo).
- vram_gb mentah (bukan ln); kapasitas ram/storage/laptop pakai ln; speed_mhz mentah; ddr_gen numerik.
- Fase A2: skala skor per kolom dipilih dari sanity (aturan di atas) dan diimplementasikan di skrip; nama fitur ln mengikuti skala (ln_consensus vs ln_passmark).
- Fase A2: klasifikasi storage memakai urutan nvme/pcie (negasi-aware) > sata eksplisit > m.2 saja dibuang > ssd > hdd > buang; 'm.2' tanpa tipe tidak ditebak.
- Fase A2: filter bundle menggantikan Fase A — penanda hanya di judul dengan word boundary (tanpa fullset/full set) + deteksi pasangan dua komponen berbeda; laptop dikecualikan dari pasangan.
- Fase A2: pemisah evaluasi (a) memakai group_n tanpa kondisi/fallback; baseline (a) tidak berubah.
- Fase A2: gerbang Tier 2 = >= 100 baris DAN MAE (b) model <= 0,9 x MAE median kategori (b); gerbang 150 hanya untuk Tier 1.
- Fase A2: tidak ada perluasan regex dari sampel bocor; pola sistematis (bare iX, Core tanpa i, seri N, sufiks XTX) adalah keterbatasan bersama Dart, kandidat perbaikan bersama di Fase C.
- Fase A2: fixture parity ditulis ke path draft (ml_parity_draft.json), bukan test/fixtures; fixture draft memuat 3 kasus tipe storage khusus.
- A3: urutan pipeline final = dedupe hash -> dedupe (seller, raw_title) -> dedupe (seller, judul ternormalisasi) -> filter harga -> filter placeholder -> filter bundle A2 -> filter aksesori -> inferensi kondisi (tanpa drop) -> drop ekstraksi -> IQR -> latih varian -> evaluasi + gerbang A2-6.
- A3-1: harga placeholder dibuang setelah filter rentang (persis 123456789/987654321/123123, digit berulang 5+, awalan 12345).
- A3-2: filter aksesori dari judul saja (daftar di atas); spek jumlah fan dikecualikan; laptop diawali ram/ssd/hdd/memory/sodimm dibuang.
- A3-3: inferensi kondisi hanya Tokopedia kosong dari judul; defaults memuat cond_new_mean, cond_second_mean, src_tokopedia_mean; kondisi 'any' di inferensi memakai kedua cond mean (fungsi resolve_condition_dummies/predict_price di skrip).
- A3-4: dua varian src per kategori; varian dengan-src dievaluasi dengan mean-fill train fold; pilihan per kategori utama MAE (a), (b) konfirmasi; gerbang dari varian terpilih; skema JSON bertambah src_variant, src_variant_reason, dan MAE kedua varian.
- Perbaikan kapasitas desimal: '2.0TB' kini dibaca 2000 (dulu salah dibaca 0TB dan membuat log(0) crash kategori storage); guard cap/total/ram/storage <= 0 kini dibuang sebagai tidak ditemukan, bukan crash. Perubahan ini harus di-port bersama ke Dart di Fase C agar paritas latih/inferensi terjaga.
- A4: gerbang Tier 1 = >= 150 baris DAN MAE (a) model <= 0,95 x baseline; Tier 2 tetap 0,9 x median (b). Alasan gerbang baru: mae_model_a_le_95persen_baseline_a / mae_model_a_tidak_lebih_baik_5persen.
- A4: ekstraksi CPU laptop diperluas (bare iX, Core tanpa i, Ultra 3 digit, Apple kunci eksak); sisi Dart disiapkan sebagai file draft tools/ml/draft/dart_laptop_cpu_parse_draft.dart, BELUM diterapkan ke lib/ (diterapkan di Fase C).
- A4: laporan dan JSON baru berekstensi A3 (ml_report_draft_A3.md, price_models_draft_A3.json, ml_parity_draft_A3.json); fixture parity baru = kasus kategori lama + kasus CPU laptop baru; file lama tidak ditimpa.
