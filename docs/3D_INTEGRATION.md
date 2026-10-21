# Integrasi 3D — Rakit PC Acak

Dokumen ini menjelaskan arsitektur integrasi 3D pada fitur **Rakit PC Acak**
(`lib/screens/builder_screen.dart`), Lightroom, dan cara memvalidasinya.

---

## 1. Arsitektur

```
BuilderScreen  (state & logika existing, tidak berubah)
    │
    ├── ShakeDetector  →  _build()  →  builderApi.randomBuild()   [data asli]
    │                                   │
    │                                   └──> _pickStageParts()  [pilih 1 set PC utuh acak]
    │
    └── Pc3DStage  (widget visual baru, non-intrusif)
            │
            ├── WglbCatalog.load()          ← assets/3d/prepared/catalog.json
            ├── rootBundle.load()           ← .wglb per part
            ├── Isolate.run() → PcScene.toGlb()   ← rakit GLB runtime
            └── GlbView.memory()            ← render native OpenGL ES
```

### Kenapa bukan WebView / WebGL

Permintaan menyebut "canvas", "CSS/flexbox", "prefers-reduced-motion", dan
"context loss" — itu kosakata web. Di Flutter, padanannya:

| Istilah web                | Padanan Flutter di sini                          |
| -------------------------- | ------------------------------------------------ |
| canvas / DOM               | `GlbView` (Texture native OpenGL ES)             |
| pointer-events             | Gesture dibatasi `GlbGesture.rotate` saja        |
| context loss               | `errorBuilder` → fallback 2D                     |
| prefers-reduced-motion     | `MediaQuery.disableAnimations`                   |
| disposal / memory leak     | `dispose()` widget + cache LRU plugin             |

`glbview` render lewat **Texture native** (bukan `PlatformView`), jadi 3D bisa
berada di dalam `Column`/`ListView` biasa tanpa mengganggu layout. Tidak ada
WebView, tidak ada JavaScript bridge, tidak ada overhead WebView di APK.

---

## 2. Pipeline aset (offline)

Runtime **tidak** bisa mem-parsing Draco. Semua aset mentah di `assets/3d/`
adalah Draco-compressed dan berukuran ±180 MB. Pipeline offline
`tool/prepare_3d.mjs` mengubahnya jadi format ringan:

```
assets/3d/*.glb  (Draco, ±180 MB)
        │
        │ node tool/prepare_3d.mjs
        ▼
  Draco decode
  → terapkan transform node (world matrix) — geometri BuildCores
    ditaruh di matriks node; tanpa ini semua panel menumpuk di origin
  → weld by position (seam vertex digabung)
  → buang shell kecil < 12mm (sekrup/kapasitor — lantai topologi
    simplifier; tak terlihat di skala panggung)
  → Meshopt simplify (budget triangle per kategori; case dikunci
    error rendah supaya kaca lengkung tidak jadi duri)
  → hitung normal
  → SATU transform bersama per set (pusat bbox → origin, skala
    seragam; part TIDAK dipindah sendiri-sendiri)
  → compact (buang vertex tak terpakai)
        ▼
assets/3d/prepared/*.wglb  (flat f32, ±5 MB total)
        + catalog.json v2 (daftar set PC utuh)
```

**Model aset = satu set PC utuh per build** (keputusan produk
2026-10-21): yang diacak di UI adalah set-nya, bukan part-nya, dan
model murni hiasan — tidak mewakili komponen hasil acakan. Karena itu
pipeline hanya memproses kategori komponen PC internal (Motherboard,
GPU, RAM, PSU, CPUCooler, PCCase, CaseFan); kategori setup meja dari
build BuildCores (Chair, Desk, Monitor, Keyboard, Speaker, ...)
dibuang. Set `intel285k` tidak dipakai: build-nya tidak punya
Motherboard/PSU/CPUCooler.

Format `.wglb` (flat, tanpa dependensi runtime):

```
offset 0  : 4 byte  magic 'WGLB'
offset 4  : u32     version (1)
offset 8  : u32     vertexCount
offset 12 : u32     indexCount
offset 16 : f32[]   positions (x,y,z per vertex)
             f32[]   normals  (x,y,z per vertex)
             u32[]   indices
```

`.wglb` dipilih karena **runtime tidak perlu parser GLB**. Parser GLB pure-Dart
di `lib/services/pc_scene.dart` hanya ~150 baris dan bisa diuji; parser bawaan
plugin bisadiesubscribe, tapi format flat lebih mudah diaudit dan ~2× lebih
kecil daripada GLB per part.

### Angka hasil pipeline

| Set       | Part | Tris   | Bytes   |
| --------- | ---- | ------ | ------- |
| tron      | 9    | 37,4k  | 0,93 MB |
| msi       | 11   | 45,7k  | 1,12 MB |
| white     | 9    | 40,7k  | 1,03 MB |
| piets     | 10   | 38,2k  | 0,93 MB |
| firstpc   | 9    | 38,0k  | 1,04 MB |
| **TOTAL** | **48** | **199,9k** | **5,04 MB** |

Satu scene yang tampil = satu set (maks 45,7k tri). D banding sumber:
180 MB → 5,04 MB (**−97,2 %**).

### Aset mentah tidak ada di repo

`assets/3d/*` mentah (85 GLB Draco, ±180 MB) **dihapus dari repo** dan di-ignore.
Yang tetap di repo hanya `assets/3d/prepared/` (5,04 MB) — itu yang dibundel ke
APK. `.gitignore` memuat:

```gitignore
assets/3d/*
!assets/3d/prepared/
```

Untuk regenerate: unduh GLB BuildCores ke `assets/3d/`, lalu jalankan
`node tool/prepare_3d.mjs`. Pipeline butuh `npm install` di `tool/`.

---

## 3. Reactive state binding

`BuilderScreen` tetap jadi satu-satunya sumber kebenaran:

- `_build()` dipanggil oleh tombol **Rakit Acak** **dan** oleh `ShakeDetector`.
- `_pickStageParts()` memilih SATU set PC utuh acak dari katalog —
  murni hiasan, tidak memetakan `RandomBuild` sama sekali.
- `_stageParts` di-pass ke `Pc3DStage` lewat parameter widget biasa.

Yang **tidak** berubah: `builderApi.randomBuild()`, `ShakeDetector`,
`TiltCard`, `settingsControllerProvider`, dan seluruh logic budget.

Loop animasi 3D (auto-rotate) berjalan **di dalam renderer native** — bukan di
`build()`. Jadi perubahan state UI tidak memicu rebuild widget tree, dan
render 3D tidak memicu `setState`.

`Pc3DStage` hanya memanggil `setState` pada 3 kejadian: scene selesai dirakit,
terjadi error, atau `MediaQuery.disableAnimations` berubah.

---

## 4. Canvas lifecycle & isolation

| Concern | Implementasi |
| ------- | ------------ |
| Non-intrusif | `Pc3DStage` = `SizedBox` + `ClipRRect` + `Stack`. Tidak butuh `Stack`/`Positioned` penuh. |
| Blocking input | Gesture panggung hanya `GlbGesture.rotate` (horizontal). Drag vertikal → scroll list. |
| Blocking form | Panggung berada di bawah field form, bukan di atasnya. Tapping form tidak kena canvas. |
| Disposal | `dispose()` menaikkan epoch (membatalkan scene yang masih jalan) dan melepas referensi cache key. |
| Memory leak | `Isolate.run` mengosongkan cache aset setelah selesai. Scene lama yang tak terpakai dibuang lewat epoch check. |
| Cache GPU | `GlbView.precacheMemory(glb, cacheKey: ...)` — key stable per kombinasi part, jadi scene yang sama tidak di-upload dua kali. |

---

## 5. Performance budget & loading strategy

**Lazy load.** Model baru dirakit setelah `_stageParts` berubah. Sebelum itu,
panggung menampilkan placeholder 2D. Tidak ada aset yang diunduh saat app start.

**Progressive reveal.** Ada 4 state visual:

1. Placeholder (`MonexOrbitLoader` + "Menyiapkan model 3D")
2. Loading rakitan ("Menyusun rakitan…")
3. Viewer aktif
4. Fallback ("3D tidak tersedia" / "WebGL tidak tersedia")

**Aset terkompresi.** Draco ditangani di pipeline offline, bukan runtime. Alasannya
memRunning binary parser Draco di dalam isolate Flutter menambah ~1,2 MB native
library dan kompleksitas; payoff-nya (1,7 MB vs 180 MB) sudah didapat.

**Pixel ratio / frame rate.** `GlbView` menangani render loop native; APK ini
tidak pernah membuat scene >46k triangle dan TEXTURENYA DIHAPUS (lihat
`tool/prepare_3d.mjs` — semua texture dilepas, warna came flat PBR). Ini yang
membuat 60 FPS realistis di kelas perangkat mid-range.

---

## 6. Graceful fallback & accessibility

| Kondisi | Hasil |
| ------- | ----- |
| WebGL tidak tersedia | `errorBuilder` → ikon + "WebGL tidak tersedia" |
| Aset gagal dimuat | `_error` → "3D tidak tersedia" |
| Katalog 3D kosong | Panggung tetap tampil, hanya placeholder |
| `prefers-reduced-motion` aktif | `autoRotate: false`, model diam |
| Shake tanpa sensor | `ShakeDetector` existing tetap jalan, tombol tetap bisa dipakai |

Fallback **tidak pernah membuat crash**: semua jalur error berakhir di
`_Fallback2D`, dan `Pc3DStage` tidak pernah melempar exception ke atas.

---

## 7. Checklist validasi objektif

### 7.1 Otomatis (sudah dijalankan)

| # | Item | Cara ukur | Target | Hasil |
| - | ---- | --------- | ------ | ----- |
| A1 | Analisis statis | `flutter analyze --no-pub` | 0 issue | ✅ 0 issue |
| A2 | Regresi suite penuh | `flutter test --no-pub` | semua hijau | ✅ 134/134 hijau |
| A3 | GLB runtime valid | `parseGlb()` plugin pada GLB rakitan | parse sukses | ✅ test `pc_assets_test.dart` |
| A4 | Normalizer | panjang normal | 1,0 ±0,01 | ✅ |
| A5 | Budget triangle scene | jumlah tri | < 60k | ✅ satu set maks 45,7k (tes per set) |
| A6 | Budget ukuran aset | `du assets/3d/prepared` | < 6 MB | ✅ 5,04 MB (5 set PC utuh) |
| A7 | APK release | `flutter build apk --release` | build sukses | ✅ 66,0 MB, plugin native compile |
| A8 | Overflow 320 px | `test/monex/monex_overflow_test.dart` | 0 overflow | ✅ |
| A9 | Aset 3D di APK | `unzip -l app-release.apk` | hanya `prepared/` | ✅ 1.695.899 B; raw 0 B |
| A10 | Raw 3D di repo | `git ls-tree -r origin/main` | 0 file mentah | ✅ 17 file, semua `prepared/` |
| A11 | Ukuran repo | `du -sh .git` | < 40 MB | ✅ 27 MB (dari 101 MB) |

### 7.2 Manual (perlu perangkat)

| # | Item | Cara ukur | Target | Status |
| - | ---- | --------- | ------ | ------ |
| M1 | Frame rate idle | `adb shell dumpsys gfxinfo <pkg> framestats` | 60 FPS, < 5 % jank | ☐ |
| M2 | Frame rate saat shake |同上 sambil goyang 10× | 55+ FPS | ☐ |
| M3 | Waktu ke model pertama | logcat timestamp → scene tampil | < 1,5 s | ☐ |
| M4 | Ukuran APK delta | `flutter build apk --release` vs baseline | < +2 MB | ☐ |
| M5 | Reduced motion | aktifkan "Remove animations" di Developer Options | model diam | ☐ |
| M6 | WebGL fallback | matikan GPU / emulator tanpa GPU | pesan fallback, app tetap jalan | ☐ |
| M7 | Scroll & tap form | scroll list sambil drag di area panggung | tidak ada gesture ditahan | ☐ |
| M8 | Stress test | 20× shake cepat + scroll + ubah budget | tidak freeze, tidak leak | ☐ |
| M9 | Memory | `adb shell dumpsys meminfo <pkg>` setelah 20× shake | < +50 MB native | ☐ |

### 7.3 Stress test interaksi (skrip)

```bash
# 20x shake cepat + interaksi UI
for i in $(seq 1 20); do
  adb shell input keyevent KEYCODE_T  # fokus tombol
  adb shell am broadcast -a com.worthbang.worthbang.SHAKE
  adb shell input swipe 300 400 300 100 100
done
adb shell dumpsys meminfo com.worthbang.worthbang | grep -E "TOTAL|Native Heap"
adb shell dumpsys gfxinfo com.worthbang.worthbang | grep -E "Janky|Total frames"
```

---

## 8. File yang disentuh

**Baru**

- `lib/services/wglb.dart` — format `.wglb` + katalog
- `lib/services/pc_scene.dart` — composer GLB pure Dart
- `lib/widgets/pc_3d_stage.dart` — widget panggung
- `tool/prepare_3d.mjs` — pipeline aset offline
- `test/three_d/pc_scene_test.dart` — unit test composer
- `test/three_d/pc_assets_test.dart` — verifikasi aset nyata
- `test/three_d/pc_3d_stage_test.dart` — test widget panggung

**Diubah**

- `lib/screens/builder_screen.dart` — panggung 3D ditambahkan, logic existing utuh
- `lib/screens/price_check_screen.dart` — fix overflow 320 px (Dropdown `isExpanded`)
- `pubspec.yaml` — `glbview` + registrasi `assets/3d/prepared/`

**Tidak disentuh**

- Backend, API contract, database, auth, provider, repository, CI.
- `lib/utils/router.dart` — route & guard tidak berubah.
