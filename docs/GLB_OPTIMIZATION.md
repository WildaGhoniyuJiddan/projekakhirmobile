# Optimasi GLB — tanpa merusak bentuk & tekstur

Skrip: `tool/optimize_glb.mjs`
Output: `tool/output/optimized/` (satu folder datar, file asli tidak pernah ditimpa)
Laporan: `tool/output/optimized/optimize_report.json`

## Struktur folder

```text
assets/3d/                    # sumber mentah (±188 MB, diabaikan Git)
  buildcores-*/               #   folder per pack
  prepared/                   #   payload runtime app (ikut repo)

tool/
  optimize_glb.mjs            # skrip optimizer
  output/
    optimized/                #   85 hasil .glb, datar, + optimize_report.json
    .tmp/                     #   file kerja (dihapus setelah tiap file)
```

Output sengaja **datar** (tanpa subfolder). Nama file diberi prefix folder asal
supaya tetap unik: ada `67313ca98210dfc03eb2efe2_low.glb` di dua folder berbeda,
dan tanpa prefix satu akan menimpa yang lain.

```text
buildcores-build-2026-intel-285k-sfs52_vuJ-glb/build-2026-intel-285k-sfs52_vuJ/65482c80477e815da41f25ff_low.glb
  -> build-2026-intel-285k-sfs52_vuJ-glb--65482c80477e815da41f25ff_low.glb
```

Field `rel` di laporan menyimpan path sumber; field `out` menyimpan nama file output.

## Jalankan

```bash
cd D:/Kuliah/Mobile/WorthGaBang-AndroidVer

# Semua GLB di assets/3d
node tool/optimize_glb.mjs

# Satu file
node tool/optimize_glb.mjs "assets/3d/buildcores-ghost-parts-glb/ghost-parts/ghost_ddr5.glb"

# Dry run (tidak menulis file, hanya laporan)
node tool/optimize_glb.mjs --dry-run
```

## Aturan yang diterapkan

| # | Aturan | Implementasi |
|---|--------|--------------|
| 1 | Tidak kurangi poligon | Tidak ada `simplify()` / `decimate()`. `weld()` hanya merge vertex **bitwise-identik di semua atribut** (POSITION+NORMAL+TANGENT+TEXCOORD_0/1/2) — lossless, tidak ada toleransi posisi. |
| 2 | Kompresi geometri high-precision | `KHR_mesh_quantization` via `quantize()`: POSITION 14 bit, NORMAL 10 bit, TEXCOORD 12 bit. **Bukan Draco** (lihat catatan di bawah). |
| 3 | Tekstur tajam & ringan | KTX2 → PNG (`basisu -unpack`) → WebP `quality: 85`. Resize hanya kalau > 1024px. Tekstur < 1024px tidak diubah. |
| 4 | Pembersihan aman | `dedup()` (ACCESSOR+TEXTURE saja), `prune({keepAttributes:true})`, `resample()` bila ada animasi. |
| 5 | Tidak menimpa asli | Semua output masuk `tool/output/optimized/`. |

## Kenapa BUKAN Draco

Draco compressing byte geometri tanpa mengurangi triangle — sesuai permintaan. Tapi renderer
`glbview` yang dipakai app **menolak file ber-Draco** di level primitive:

```dart
// glbview-0.3.3/lib/src/glb_parser.dart
if (primitive.getExtensions()['KHR_draco_mesh_compression']) {
  throw Exception('Compressed geometry is not supported');
}
```

Draco juga tidak bisa dipakai karena `quantize()` menaruh skala ke node transform, sementara
`glbview` membaca `KHR_mesh_quantization` tanpa menerapkan `scale`/`offset` per accessor.
Hasilnya mesh bisa jadi "kotak kasar" persis seperti keluhan awal.

`KHR_mesh_quantization` dipilih sebagai gantinya: presisi tinggi (14/10/12 bit), tidak ada
decoder tambahan di app, dan glbview membacanya dengan benar.

## Kenapa ukuran output bisa lebih besar dari sumber

Dua sebab, keduanya konsekuensi dari aturan yang diminta:

1. **6 file sumber ber-Draco** (+18,3 MB total). Draco dihapus supaya `glbview` bisa
   membaca filenya. File yang tadinya terkompresi byte jadi uncompressed — tidak ada
   cara lain selama Draco dilarang.

2. **NORMAL dinaikkan 8 bit → 10 bit** (+14,2 MB total di 79 file lain). Ini persis
   ambang presisi yang diminta. Naiknya linear: 1 byte per vertex.

Kalau ukuran jadi prioritas, opsinya: turunkan `quantizeNormal` ke 8, atau pakai Draco
dan ganti renderer. Dua-duanya bertentangan dengan aturan saat ini.

## Akar masalah "bentuk jadi kotak kasar" + "tekstur blur"

Dua hal terpisah:

1. **Geometri rusak** — `weld()` berbasis toleransi posisi menyatukan vertex seam yang
   UV-nya berbeda, dan `quantize()`/`dequantize` yang salah urut bisa menggeser posisi.
   Fix: weld bitwise-identik saja, plus guard yang membandingkan bounding box
   **dalam koordinat dunia** sebelum/sesudah.

2. **Tekstur hilang, bukan blur** — 665 dari 681 tekstur sumber berformat **KTX2**
   (`KHR_texture_basisu`). `glbview` **tidak bisa decode KTX2 sama sekali** — ia skip
   tekstur itu, jadi model tampil tanpa material. Fix: konversi KTX2 → WebP.

## Guard (optimasi dibatalkan otomatis kalau ada yang rusak)

Setiap file diperiksa sebelum ditulis:

| Guard | Ambang | Arti |
|-------|--------|------|
| Triangle count | harus identik | tidak ada poligon hilang |
| Bounding box drift | ≤ 0,1% | bentuk tidak bergeser / jadi kotak |
| UV sample count | harus identik | indeks mesh sinkron |
| UV mean drift | ≤ 0,2% | tekstur tidak melenceng |

Guard menolak file, bukan memaksa lolos. File yang ditolak **tidak** ditulis ke output.

Bounding box dihitung di **koordinat dunia** (matrix node ikut dikalikan), karena
`quantize()` memindahkan skala dari accessor ke node transform. Bounding box lokal
akan memberi drift palsu sampai 58% pada file yang sebenarnya utuh.

## API yang dipakai (gltf-transform v4)

`dedup()` v4 memakai opsi `propertyTypes` (bukan `include`). `weld()` v4 sudah tanpa
toleransi posisi — hanya merge vertex identik. `prune()` perlu `keepAttributes: true`,
kalau tidak ia membuang accessor yang tak dirujuk indeks sehingga indeks dan UV tidak sinkron.

`Accessor` di v4 tidak punya `getX()`/`getY()`. Untuk nilai ternormalisasi (accessor
quantized) pakai `getScalar()` + skala manual per `getComponentType()`:
`5120`→1/127, `5121`→1/255, `5122`→1/32767, `5123`→1/65535.

`doc.disposeExtension('KHR_draco_mesh_compression')` harus dipanggil **berdasarkan daftar
document-level**, bukan `primitive.getExtension()` — yang sudah null setelah Draco
ter-decode saat read.

## Verifikasi

`test/three_d/optimized_glb_test.dart` mem-parse hasil output dengan parser resmi
`glbview` — sama persis yang dipakai app saat runtime. Test juga memastikan tidak ada
output yang memakai Draco atau meshopt.

```bash
flutter test --no-pub test/three_d/optimized_glb_test.dart
```
