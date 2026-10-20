# PLAN — Migrasi WorthBang: Full Supabase (Pensiun Backend Python)

> Tujuan: aplikasi Flutter bicara LANGSUNG ke Supabase. Tidak ada lagi
> server Python yang harus di-host terpisah. Satu rumah: Supabase
> (Postgres + Auth + Edge Functions) + APK release.
>
> Status: PLAN — belum dieksekusi. Eksekusi per fase, review gate di
> antara fase (pola biasa). Backup wajib sebelum Fase 0.
>
> Tanggal: 2026-10-20. Basis: HEAD `785354a`.

---

## 1. Kondisi sekarang (fakta dari repo)

- Database SUDAH Postgres di Supabase (`DATABASE_URL` di `backend/app/config.py`).
  Yang di luar Supabase cuma lapisan hitung Python (±3.150 baris):
  | File | Baris | Isi |
  |---|---|---|
  | `services/analysis.py` | 1.187 | Mesin analyze (PC + laptop + bundle) |
  | `services/benchmark.py` | 418 | Skor PassMark + konsensus + alternatif |
  | `routers/mobile.py` | 431 | Auth, history, chat (Gemini) |
  | `services/relevance.py` | 391 | Skor relevansi listing |
  | `services/suggest.py` | 315 | Saran pencarian |
  | `main.py` + `auth.py` + `scoring.py` + `security.py` | ±590 | Endpoint, JWT, skor inti, rate limit |
- Endpoint aktif (Fase 3): auth ×4, history ×2, `chat/ask`, `analyze`,
  `analyze-bundle`, `search`, `suggest/{section}`, `health`, `debug`.
- Tabel DB: `raw_listings`, `pc_components`, `laptop_units`,
  `analysis_logs`, `users`, `refresh_tokens`, `wishlist_items`,
  `price_alerts`, `stores`, `scrape_runs`.
- Auth sekarang: custom — bcrypt di tabel `users`, JWT sendiri,
  refresh token di-hash sha256 di `refresh_tokens` (bisa di-revoke).
- Bang Worth: Gemini dipanggil dari Python; API key di env server.
  Scope-guard lokal (`_is_in_scope`) + grounding katalog retail + skor
  konsensus (integrasi 2026-10-15).
- Backend tests: **33 passed** — ini jangkar perilaku; perilakunya
  TIDAK BOLEH berubah setelah migrasi.

## 2. Arsitektur tujuan

```
Flutter APK
 ├─ supabase_flutter ──► Supabase Auth        (ganti auth custom)
 ├─ PostgREST / RPC ───► Postgres Supabase    (listings, history) + RLS
 ├─ Asset lokal ───────► benchmark/konsensus/katalog JSON (dibundel)
 └─ Edge Function ─────► bang-worth (Deno/TS, ±60 baris, pegang
                          GEMINI_API_KEY) ──► Gemini API
```

**Tidak ada Dart server di Supabase** — Supabase tidak meng-host kode
Dart. "Full Supabase" = client Dart + layanan Supabase. Satu-satunya
kode non-Dart yang tersisa: 1 Edge Function TypeScript untuk Gemini
(wajib, lihat Keputusan 2).

## 3. Keputusan yang harus diambil Dan dulu

1. **User existing:** (a) fresh start — tabel `users` custom dibuang,
   user daftar ulang di Supabase Auth; atau (b) impor hash bcrypt
   lama ke Supabase Auth via Admin API (didukung, user tak perlu ganti
   password). Rekomendasi: (a) untuk skala tugas akhir — lebih bersih,
   kecuali data user demo sudah terlanjur banyak.
2. **Gemini:** (a) Edge Function proxy (key aman di secret Supabase) —
   rekomendasi; atau (b) key ditanam di APK (key bisa diekstrak,
   kuota bisa dibakar orang — risiko yang sudah tercatat di audit
   2026-10-09). Tidak ada opsi (c).
3. **Query listing untuk analyze:** mesin analyze sekarang menarik
   s.d. 3.000 baris `raw_listings` lalu menyaring di Python.
   PostgREST membatasi 1.000 baris per request. Pilihan:
   (a) fungsi RPC Postgres `match_listings(...)` yang menyaring
   (ILIKE + kategori) di server, Dart tinggal menilai relevansi —
   rekomendasi, paling hemat bandwidth & paling setia ke perilaku lama;
   atau (b) pagination PostgREST 3× request dari app.
4. **Nasib folder `backend/`:** (a) arsipkan sebagai tag/branch lalu
   hapus dari `main` — rekomendasi; atau (b) biarkan membeku di repo.
   JANGAN hapus tanpa arsip (itu bukti kerja + fallback demo).

## 4. Fase pengerjaan

### Fase 0 — Fondasi Supabase (tanpa menyentuh app)
- Backup: dump skema + data tabel inti; simpan di luar repo.
- Aktifkan Supabase Auth (email/password), samakan kebijakan password.
- RLS: `raw_listings`, `pc_components`, `laptop_units` → read-only
  untuk role `anon`/`authenticated`; tabel tulis (scrape) → service
  role saja.
- Buat RPC `match_listings` (Keputusan 3) bila dipilih.
- Skeleton Edge Function `bang-worth` + secret `GEMINI_API_KEY`.
- **Kriteria lolos:** dari curl/REST client luar app — baca listings
  pakai anon key berhasil, tulis ke `raw_listings` DITOLAK, login
  Auth berhasil.

### Fase 1 — Auth pindah ke Supabase Auth
- Tambah `supabase_flutter`; `AuthRepository` ditulis ulang di atas
  Supabase Auth (register/login/logout/refresh otomatis oleh SDK).
- Biometrik & session lokal tetap seperti sekarang (di atas sesi
  Supabase). `TokenStorage` custom + interceptor refresh di
  `dio_api_client.dart` pensiun.
- Profil (nama/foto) → tabel `profiles` (id = uuid `auth.users`) + RLS
  hanya pemilik.
- **Kriteria lolos:** register → login → logout → login lagi jalan di
  emulator; token tidak ada lagi yang dikelola manual; test auth
  Flutter hijau.

### Fase 2 — History & sinkronisasi
- `analysis_logs`: tambah kolom user uuid; RLS per-user
  (select/insert hanya baris milik sendiri).
- Sync hash-chain lokal (Drift) → insert ke `analysis_logs`
  menggantikan `POST /api/v1/history`. Semantik B10 dipertahankan
  (timestamp difuture di-clamp, naive = UTC).
- **Kriteria lolos:** analisis offline tercatat lokal; saat online
  tersinkron; user A tidak bisa membaca riwayat user B (dibuktikan
  dengan 2 akun uji).

### Fase 3 — Mesin analyze diporting ke Dart (fase terbesar)
- Port berurutan, satu file Python → satu modul Dart:
  `scoring.py` → `benchmark.py` (PassMark + konsensus) →
  `relevance.py` → `analysis.py` (PC, laptop, bundle) →
  `suggest.py` → `search`.
- Dataset JSON (`benchmark_scores.json`, `consensus_scores.json`,
  `retail_catalog.json`, `new_price_reference.json`) dibundel
  sebagai asset Flutter (pola yang sama seperti stores CSV).
- Listings: via RPC/PostgREST (Keputusan 3), BUKAN dibundel —
  datanya data pasar yang terus diperbarui scraper.
- **Jangkar perilaku:** 33 test backend diterjemahkan jadi golden
  test Dart (input sama → skor/verdict/alternatif sama), termasuk
  kasus nyata: RTX 4060, Ryzen 5 5600, laptop combo.
- **Kriteria lolos:** semua golden test hijau; hasil analyze di app
  identik dengan backend lama untuk baterai kasus uji yang sama.

### Fase 4 — Bang Worth via Edge Function
- Port `_is_in_scope`, `_extract_budget_idr`, `_catalog_context`
  ke Edge Function `bang-worth` (TS). Grounding memakai
  `retail_catalog.json` + `consensus_scores.json` yang disimpan di
  Supabase Storage / dibundel ke fungsi.
- App memanggil fungsi via `supabase.functions.invoke` dengan JWT
  user → chat otomatis ter-gate auth (menutup temuan audit lama:
  `chat/ask` terbuka publik & bakar kuota).
- **Kriteria lolos:** tanya komponen → jawaban menyebut skor
  konsensus; tanya di luar topik → ditolak sopan; tanpa login →
  fungsi menolak.

### Fase 5 — Pensiun backend Python
- Lepas `price_check_api.dart`/`dio_api_client.dart` dari base URL
  `10.0.2.2:8000`; tidak ada lagi URL server di app selain proyek
  Supabase.
- Arsipkan `backend/` (Keputusan 4), update `API_CONTRACT.md`,
  `PLAN.md`, `CHANGELOG.md`; deploy = build APK release saja.
- **Kriteria lolos:** app full jalan dengan backend Python DIMATIKAN;
  `flutter test` + GitHub Actions APK hijau.

## 5. Pemetaan 13 kriteria PAM (tidak boleh ada yang gugur)

| Kriteria | Sesudah migrasi |
|---|---|
| Login terenkripsi | Supabase Auth (bcrypt + TLS) |
| Biometrik | Tetap lokal di atas sesi Supabase |
| SQLite + sinkronisasi backend | Drift lokal ↔ `analysis_logs` Supabase |
| LBS peta toko | Tidak berubah (lokal) |
| Chatbot AI (Bang Worth) | Edge Function → Gemini, ter-gate login |
| Analisis harga + skor tren | Mesin Dart lokal + data Supabase |
| Hash-chain SHA-256 | Tetap lokal; backup ke Supabase |
| Kurs, sensor, game, alert, wishlist, dll | Sudah lokal sejak Fase 3 (2026-10-12), tidak berubah |

## 6. Risiko & mitigasi

| Risiko | Mitigasi |
|---|---|
| RLS salah → data bocor / terkunci | Uji policy pakai anon key + 2 akun uji di Fase 0 & 2 sebelum app disambungkan |
| Perilaku analyze berubah diam-diam saat porting | Golden test dari 33 test backend (Fase 3) — tidak ada porting tanpa test pembanding |
| Limit 1.000 baris PostgREST | RPC `match_listings` (Keputusan 3a) |
| Edge Function cold start lambat | Fungsi dibuat ramping; timeout chat di app dinaikkan wajar |
| Kuota Supabase free tier (DB 500MB, bandwidth) | `raw_listings` sudah ada & stabil; pantau usage setelah Fase 2 |
| Demo butuh fallback | `backend/` diarsipkan utuh (Keputusan 4) — bisa dihidupkan lagi dalam menit |

## 7. Yang SENGAJA tidak dikerjakan

- Rewrite scraper/ingest (job tulis ke DB tetap jalan terpisah,
  memakai service role — bukan urusan app).
- Mengubah UI/tema Monex, fitur 3D, atau fitur lokal lain.
- Mengubah dataset konsensus & metode skornya.
