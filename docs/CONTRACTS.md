# CONTRACTS — Seam antar-agent (projekakhirmobile, full-Dart + Supabase)

Sumber kebenaran perilaku: backend Python di repo lama
`~/workspace/WorthGaBang-AndroidVer/backend/` (33 test passed).
Repo ini = clone app Flutter-nya; folder `backend/` SENGAJA tidak ikut.

## Aturan umum (semua agent)

- JANGAN ubah `lib/screens/**`, `lib/models/**`, `lib/providers/**`
  kecuali file yang disebut di kontrakmu. Interface publik service
  yang sudah ada TIDAK berubah tanda tangannya.
- Karpathy: perubahan bedah (surgical), kode minimum, tanpa fitur
  spekulatif. Komentar bahasa Indonesia seperti gaya repo.
- Sumber output golden: jalankan fungsi Python aslinya, jangan
  menebak angka.
- Flutter/Dart TIDAK bisa dijalankan di VM ini (tak ada SDK) —
  verifikasi lokal = ketelitian baca + test Python pembanding;
  verifikasi final = CI GitHub Actions repo ini.

## Porter-Engine → `lib/services/engine/`

Port setia (bukan redesign) dari Python:

| Python | Dart |
|---|---|
| `services/scoring.py` | `engine/scoring.dart` — `scorePrice(...)` |
| `services/benchmark.py` | `engine/benchmark.dart` — passmarkScore, consensusLookup, betterAlternatives, betterAlternativesConsensus, laptopComboScore, getTierLabel, consensusTierLabel, extractVramGb |
| `services/relevance.py` | `engine/relevance.dart` |
| `services/suggest.py` | `engine/suggest.dart` |
| `services/analysis.py` | `engine/analysis_engine.dart` |
| JSON di `assets/data/` | `engine/dataset.dart` — `BenchmarkData.load()` dari rootBundle: benchmark_scores.json, consensus_scores.json, new_price_reference.json, retail_catalog.json |

Seam data (WAJIB persis):

```dart
/// Satu baris listing pasar (mirror kolom raw_listings yang dipakai
/// analysis.py) + unit laptop/komponen untuk mode laptop.
class ListingRow {
  final String title; final int price; final String? source;
  final String? condition; final String? url; final String? specText;
  final String? category; final DateTime? scrapedAt;
}

abstract class ListingsSource {
  Future<List<ListingRow>> pcListings({String? modelNum, required List<String> categories});
  Future<List<Map<String, Object?>>> laptopUnits({required List<String> tokens});
  Future<List<Map<String, Object?>>> pcComponents({required List<String> tokens});
  Future<DateTime?> latestScrapedAt();
}
```

`AnalysisEngine(BenchmarkData data, ListingsSource listings)` mengekspos
hasil yang field-nya 1:1 dengan yang sekarang dikembalikan
`PriceCheckApi` (lihat `lib/services/price_check_api.dart` +
`lib/models/price_check_models.dart` & `bundle_models.dart`):
analyze (pc/laptop), analyzeBundle, search. JANGAN sentuh
`price_check_api.dart` — glue-nya dikerjakan koordinator.

## Porter-Auth-History

- `lib/services/supabase_bootstrap.dart`: `initSupabase()` memakai
  `lib/config/supabase_config.dart`; panggil dari `lib/main.dart`
  sebelum `runApp` (edit main.dart seminimal mungkin).
- Tulis ulang `lib/services/auth_repository.dart` di atas Supabase
  Auth. Metode publik dipertahankan: login, register, restoreSession,
  logout, currentUser, updateCachedUser. `AppUser.id` berubah
  int → String (uuid Supabase) — sesuaikan `lib/models/auth_models.dart`
  + pemakai di providers seperlunya, laporkan semua titik ubah.
  Fallback lokal lama (_loginLocally dkk.) dibuang. Biometrik tidak
  disentuh (tetap gerbang di atas sesi).
- `lib/services/history_sync.dart`: ganti jalur `/api/v1/history`
  menjadi select/insert tabel `analysis_logs` via Supabase client,
  user_id = uuid user login. Semantik B10 dipertahankan: timestamp
  masa depan di-clamp ke sekarang, timestamp naive dianggap UTC.
  Hash-chain lokal (Drift) TIDAK diubah.

## Porter-Chat-SQL

- `supabase/migrations/20261020000001_init.sql`:
  - `profiles` (id uuid PK → auth.users, name text, photo_url text)
    + RLS: user hanya select/update baris sendiri; insert saat register.
  - RLS read-only (SELECT saja) untuk role anon & authenticated pada:
    `raw_listings`, `pc_components`, `laptop_units`. Tabel lain:
    jangan beri policy apa pun (tertutup secara default).
  - `analysis_logs`: tambah kolom `user_uuid uuid`; RLS: select/insert
    hanya baris dengan user_uuid = auth.uid().
  - Fungsi RPC `match_listings(p_model_num text, p_categories text[])`
    RETURNS SETOF raw_listings — mirror prefilter `analysis.py`:
    raw_price 50.000–150.000.000, condition bukan 'issue',
    source in (komponen_retail, tokopedia, facebook,
    facebook_marketplace), ilike %model_num% pada raw_title ATAU
    raw_spec_text, urut scraped_at desc, limit 3000.
- `supabase/functions/bang-worth/index.ts`: port logika chat
  `backend/app/routers/mobile.py` (scope guard `_is_in_scope`,
  `_extract_budget_idr`, `_catalog_context`, prompt & system
  instruction Gemini, model dari config backend lama). Wajib header
  Authorization JWT valid (tolak tanpa login). Grounding data dari
  `retail_catalog.json` + `consensus_scores.json` — salin dua file
  itu ke folder fungsi ini. API key dari env `GEMINI_API_KEY`.
  Respons JSON `{"reply": "..."}` mengikuti `chat_models.dart`.
- `lib/services/chat_api.dart`: `ask()` → `functions.invoke(
  'bang-worth', ...)`; interface `ChatApi`/`ChatReply` tidak berubah.
- `SUPABASE_SETUP.md` di root repo: langkah Dan mengisi config,
  `supabase link`, `db push`, set secret, deploy fungsi, build APK.

## QA-Golden

- Panen nilai kebenaran dari Python: jalankan pytest backend repo
  lama + skrip kecil yang mencetak output fungsi murni
  (scorePrice, passmarkScore, consensusLookup, betterAlternatives*)
  untuk baterai kasus tetap. Simpan sebagai literal di test Dart —
  JANGAN hitung ulang ekspektasi dengan logika yang sama (tautologi).
- Tulis `test/golden/engine_golden_test.dart` pada seam fungsi publik
  engine (kontrak Porter-Engine di atas).
- `.github/workflows/flutter-ci.yml`: flutter analyze + flutter test
  (build APK tetap di workflow existing `build-apk.yml`).
- Laporkan setiap ketidakcocokan porting yang ditemukan ke koordinator.
