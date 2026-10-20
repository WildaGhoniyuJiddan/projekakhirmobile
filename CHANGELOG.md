# Changelog — WorthBang Android

Semua perubahan penting pada proyek ini dicatat di file ini.

## 2026-10-15 — Integrasi dataset konsensus multi-sumber ke backend

`backend/app/data/consensus_scores.json` baru (609 CPU + 123 GPU, 108KB):
skor konsensus 0–100 (percentile equal-weight antar sumber benchmark),
tier, jumlah sumber, agreement. Dibangun dari
`datasets/merged/benchmark_consensus.csv`.

Backend sekarang memakai skor konsensus bila tersedia, fallback ke PassMark:
- `benchmark.py`: `consensus_lookup()` + `better_alternatives_consensus()`
  + `consensus_tier_label()` (label Indonesia: Kelas Atas/Menengah Atas/...)
- `analysis.py`: tier_label dan advice alternatif pakai konsensus dulu
  ("skor konsensus 85/100 (4 sumber)")
- Chatbot Bang Worth: `_catalog_context` menempelkan skor konsensus ke tiap
  komponen di grounding ("[skor konsensus 97/100, 8 sumber]") agar jawaban
  LLM berdasar data multi-sumber, bukan pengetahuan umum.
- Backend tests: 28 passed.

## 2026-10-12 — Fase 3: backend ramping + fitur lokal Dart (Opsi 1)

Backend (`backend/`) dipangkas ke endpoint yang tidak bisa dihitung lokal:
auth ×4, history ×2, `POST /api/v1/chat/ask`, `POST /api/v1/analyze`,
`POST /api/v1/analyze-bundle`, `GET /api/v1/suggest/{section}`, `/health`,
`/api/v1/debug/*`. Yang dicabut: wishlist, alerts, stores/nearby, trend,
builder/random, game ×2, currency/rates, feedback, users/me, files,
plus endpoint web-legacy (catalog/*, freshness, ingest, /test).
5 modul service yatim dihapus: `ingestion`, `normalizer`, `listing_quality`,
`coverage`, `parsing`. Backend tests: 28 passed.

Di Flutter, fitur yang dicabut diimplementasi 100% lokal tanpa ubah UI:
wishlist & alerts → tabel Drift yang sudah ada; alert checker tetap memakai
`/api/v1/analyze` untuk harga pasar; stores → `assets/data/stores_jakarta.csv`
+ haversine; builder → port 1:1 alokasi `_ALLOCATIONS` dari katalog bundled;
game → katalog bundled + rumus skor identik; currency → langsung ke
open.er-api.com dengan fallback; trend → statistik nyata katalog (tanpa
grafik time-series palsu); profile & feedback → SharedPreferences.
Flutter tests diperbarui (alert_check, sync).

## 2026-10-12 — Scope guard chatbot Bang Worth

`POST /api/v1/chat/ask` sekarang dibatasi ruang lingkupnya: hanya menjawab topik
aplikasi (komponen PC/laptop, harga & kelayakannya, rekomendasi rakitan, cara pakai
fitur). Dua lapis pertahanan: pre-filter keyword lokal `_is_in_scope()` (pesan
off-topic langsung ditolak tanpa memanggil Gemini, hemat kuota) + `systemInstruction`
ke Gemini (sekaligus menutup celah prompt injection via riwayat chat). Hint input
chat di app diubah menjadi "Tanya soal komponen PC/laptop…".

## 2026-09-29 — Backend tickets B1–B10 selesai

Endpoint `/api/v1/*` dibangun di repo `WorthGaBang` (folder `backend/app/routers/mobile.py`);
spesifikasi lengkap ada di `API_CONTRACT.md`. App ticket T0 & T1 juga mulai dikerjakan.

| Ticket | Judul | Status |
|--------|-------|--------|
| T0 | Flutter scaffold: project, flavors, theme light/dark, l10n id, icon, go_router + bottom nav 4 tab | ✅ Selesai |
| T1 | Core infra: Dio auth interceptor, secure storage, Drift schema, WorkManager init | ✅ Selesai |
| B1 | Auth: register/login/refresh/logout (bcrypt + JWT 15 mnt / 7 hari) | ✅ Selesai |
| B2 | History & wishlist: GET/POST/DELETE `/api/v1/history`, `/api/v1/wishlist` | ✅ Selesai |
| B3 | Alerts: POST/GET/DELETE `/api/v1/alerts` | ✅ Selesai |
| B4 | Stores LBS: GET `/api/v1/stores/nearby` + seed CSV toko kota demo | ✅ Selesai |
| B5 | Tren harga: GET `/api/v1/trend?query=&days=30` (deskriptif, tanpa prediksi) | ✅ Selesai |
| B6 | Random builder: POST `/api/v1/builder/random {budget, use_case}` | ✅ Selesai |
| B7 | Chatbot: POST `/api/v1/chat/ask` (Gemini server-side, grounding DB harga) | ✅ Selesai |
| B8 | Mini-game Tebak Harga: GET `/api/v1/game/question` + POST `/api/v1/game/submit` | ✅ Selesai |
| B9 | Currency rates (cache 1 jam), feedback, PUT `/api/v1/users/me` (multipart) | ✅ Selesai |
| B10 | History push: POST `/api/v1/history` — backup/sync entri hash-chain dari app | ✅ Selesai |
