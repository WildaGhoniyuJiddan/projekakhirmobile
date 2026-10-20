# WorthBang Android — Build Plan

> Status: DRAFT — awaiting approval before implementation.
> Source: `prd-worthbang-android.md` (27 user stories, 27 FRs, 13 lecturer requirements).
> Method: mattpocock skills (`wayfinder` decision map → `to-tickets` vertical slices) + coding stack
> (`rtk`, `ts`, `code-review-graph`, `context-mode`, `caveman`).

## 1. Decision Log

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | **Flutter + Dart** (bukan Kotlin native) | Instruksi eksplisit user. PRD §5 non-goal "Android-only native Kotlin" perlu amandemen satu baris: target tetap Android-only, tech stack diganti Flutter. |
| D2 | State management: **Riverpod** | Testable, compose-friendly, standar industri Flutter; padanan ViewModel+StateFlow di PRD. |
| D3 | Network: **Dio + retrofit-style manual client** | Interceptor untuk JWT attach + silent refresh (FR-3). |
| D4 | Local DB: **Drift (SQLite)** | Padanan Room: history hash-chain, wishlist, alerts, cache offline. |
| D5 | Secure storage: **flutter_secure_storage** | Padanan EncryptedSharedPreferences (AES-256) untuk JWT. |
| D6 | Maps: **flutter_map + OpenStreetMap tiles** | Padanan osmdroid; tanpa API key (FR-16). |
| D7 | Sensors: **sensors_plus** | Accelerometer (shake) + gyroscope (tilt card). |
| D8 | Background: **workmanager** + **flutter_local_notifications** | Cek alert 15 menit + notifikasi lokal; tanpa Firebase (FR-23). |
| D9 | Biometric: **local_auth** | Padanan androidx.biometric (FR-4). |
| D10 | Chart: **fl_chart** | Line chart tren 30 hari (US-008). |
| D11 | Backend tetap FastAPI (folder `backend/` di repo ini) | Endpoint analisis existing dipakai ulang; hanya endpoint baru yang dibangun (lihat §4). |
| D12 | Hash chain: `SHA256("$index\|$timestamp\|${json(data)}\|$prevHash")`, genesis `prevHash="GENESIS"` | Sesuai PRD §7; disebut "tamper-evident hash chain (blockchain concept)". |
| D13 | minSdk 26 | Ikut PRD (open question: konfirmasi ke dosen). |

## 2. Architecture

```
lib/
  main.dart                    # entry, flavors
  app/                         # App widget, router (go_router), theme (light/dark)
  core/
    network/                   # Dio client, auth interceptor, ApiResult sealed class
    storage/                   # Drift database, DAOs
    secure/                    # Token storage (flutter_secure_storage)
    sensors/                   # ShakeDetector, TiltController
    notifications/             # NotificationService, WorkManager setup
    hashchain/                 # HashChainService (append, verify)
    utils/                     # formatters (Rp), timezones
  features/
    auth/                      # data/domain/presentation (login, register, biometric)
    price_check/               # home form, autocomplete, result, bundle
    trend/                     # 30-day chart
    search/                    # filter & sort
    history/                   # history list + verify screen
    wishlist/
    stores/                    # LBS map + nearby pricing
    converters/                # currency + time
    game/                      # Tebak Harga
    alerts/                    # price alerts CRUD
    chat/                      # Bang Worth chatbot
    profile/                   # photo, toggles, feedback, logout
  l10n/                        # Bahasa Indonesia strings
```

- Tiap feature: `data/` (models, API, repository) → `domain/` (usecase) → `presentation/` (screens, widgets, providers).
- Satu `ProductCard` widget dipakai di result, wishlist, game (PRD §6).
- Satu `ApiResult` sealed class untuk loading/success/error (PRD §6).

## 3. App Tickets (vertical slices, tracer-bullet)

Legenda: tiap tiket = satu vertical slice utuh (UI → API → lokal → test), demoable sendiri.

| # | Tiket | User stories | Blocked by | Backend dep |
|---|-------|--------------|------------|-------------|
| T0 | Flutter scaffold: project, flavors dev/prod, theme light/dark, l10n id, app icon, go_router + bottom nav shell (4 tab) | US-024 (sebagian) | — | — |
| T1 | Core infra: Dio + auth interceptor + refresh, flutter_secure_storage, Drift schema (history_blocks, wishlist, alerts, cache), WorkManager init | US-002, US-003 | T0 | B1 |
| T2 | Auth flow: register, login, persistent session, biometric unlock, logout | US-001–US-005 | T1 | B1 |
| T3 | Price check inti: form kategori + autocomplete (300ms debounce) + result (verdict badge, median, min–max, jumlah listing, skeleton ≤3s) + simpan ke hash chain | US-006, US-009 | T1 | — (existing) |
| T4 | Bundle check: multi-komponen + running total + verdict per-komponen & overall | US-007 | T3 | — (existing) |
| T5 | Search filter & sort: brand/category/condition/price chips + sort | US-010 | T3 | — (existing) |
| T6 | History offline + Verify hash chain + tamper self-test (debug) | US-013, US-014 | T3 | B2 (opsional sync) |
| T7 | Tren 30 hari: line chart + min/max/avg/% + ringkasan teks (tanpa prediksi) | US-008 | T3 | B5 |
| T8 | Sensor: shake → random build (budget prompt, hint) + tilt 3D card (±15°, low-pass, toggle) | US-011, US-012 | T3 | B6 |
| T9 | LBS: peta flutter_map + toko terdekat + jarak + "cheapest nearby" | US-016, US-017 | T1 | B4 |
| T10 | Konverter: mata uang (IDR/USD/SGD/MYR, cached rates) + waktu (WIB/WITA/WIT/London, countdown) | US-018, US-019 | T1 | B9 (rates) |
| T11 | Wishlist + price alert + worker 15 mnt + notifikasi lokal (tanpa duplikat) | US-015, US-022, US-023 | T1 | B2, B3 |
| T12 | Mini-game Tebak Harga: 5 ronde, skor `max(0,100−\|Δ\|/actual×100)`, high score lokal | US-021 | T3 | B8 |
| T13 | Chatbot "Bang Worth": chat UI + kartu build + simpan ke wishlist (isolated, fase akhir) | US-020 | T1 | B7 |
| T14 | Profile: foto (kamera/galeri, upload multipart, cache), toggle biometric & tilt, feedback (rating + kesan + saran), logout | US-025, US-026, US-005 | T2 | B9 |
| T15 | Offline-first polish: banner offline, "last updated", antrean mutasi offline → sync | US-027 | T6, T11 | — |

## 4. Backend Tickets (folder `backend/`, FastAPI)

| # | Endpoint | Dibutuhkan oleh |
|---|----------|-----------------|
| B1 | `/api/v1/auth/*` register/login/refresh/logout — bcrypt server-side, JWT (15 mnt + 7 hari) | T1, T2 |
| B2 | `/api/v1/history`, `/api/v1/wishlist` (GET/POST/DELETE) | T6, T11 |
| B3 | `/api/v1/alerts` (POST/GET/DELETE) | T11 |
| B4 | `/api/v1/stores/nearby?lat=&lng=&radius_km=` + seed CSV toko kota demo | T9 |
| B5 | `/api/v1/trend?query=&days=30` | T7 |
| B6 | `/api/v1/builder/random {budget, use_case}` | T8 |
| B7 | `/api/v1/chat/ask` → Gemini free tier server-side, grounding dari DB harga | T13 |
| B8 | `/api/v1/game/question` + `/submit` | T12 |
| B9 | `/api/v1/currency/rates` (cache 1 jam), `/api/v1/feedback`, `PUT /api/v1/users/me` (multipart) | T10, T14 |
| B10 | `POST /api/v1/history` (Auth) — push riwayat analisis dari app untuk backup/sync hash-chain | T6, T15 |

Endpoint existing yang dipakai ulang tanpa perubahan: `/analyze`, `/analyze-bundle`, `/suggest/{section}`, `/catalog/*`, `/freshness`.

### B10 — `POST /api/v1/history` (Auth) — push riwayat dari app

- **Method + path:** `POST /api/v1/history`
- **Auth:** wajib (JWT `get_current_user`; 401 bila tidak ada/invalid). Entri disimpan dengan `user_id` pemilik token; isolasi antar-user dijamin.
- **Request (JSON):**

  | Field | Tipe | Wajib | Keterangan |
  |---|---|---|---|
  | `mode` | string | ya | `pc` \| `laptop` |
  | `query` | string | ya | 2–255 char |
  | `input_price` | number | ya | > 0 |
  | `score` | number | ya | 0–100 |
  | `verdict` | string | ya | 2–32 char |
  | `created_at` | datetime | tidak | timestamp analisis versi client |

- **Response:** `201` → item history yang tersimpan (bentuk sama seperti `GET /api/v1/history`): `{id, mode, query, input_price, score, verdict, created_at}`, newest-first.
- **Clamp timestamp:** `created_at` dari client yang berada di masa depan di-clamp ke waktu server saat ini.
- **Timezone:** `created_at` tanpa offset timezone (naive) dianggap **UTC**.
- **Kegunaan:** dipakai T6 (sync opsional riwayat lokal) & T15 (antrean offline → push saat online). Detail kontrak field-per-field di `API_CONTRACT.md`.

## 5. Urutan Eksekusi (frontier)

```
T0 → T1 → ┬→ T2 (auth) ──────────────→ T14 (profile)
          ├→ T3 (price check) → T4 → T5
          │                    └→ T6 (history) → T15
          │                    ├→ T7 (trend)      [B5]
          │                    ├→ T8 (sensors)    [B6]
          │                    └→ T12 (game)      [B8]
          ├→ T9 (LBS)                        [B4]
          ├→ T10 (converters)                [B9]
          ├→ T11 (wishlist+alerts)            [B2,B3]
          └→ T13 (chatbot, terakhir)         [B7]
Backend: B1 dulu (gate T1/T2), sisanya paralel per kebutuhan.
```

## 6. Demo Path (≤10 menit, sesuai PRD §6)

biometric login → price check → tilt card → shake random build → Tebak Harga → set price alert → verify hash chain → nearby stores → chatbot (opsional).

## 7. Testing & Review per Tiket

- `implement` skill: tiap tiket dibangun via `tdd` (red-green per slice), `flutter analyze` rutin.
- Setelah tiap tiket: `code-review` dua sumbu (Standards + Spec/PRD).
- Perangkat fisik untuk: biometric, sensor, peta, notifikasi (sesuai acceptance criteria PRD).
- `flutter test` untuk: hash chain (append/verify/tamper), scoring game, konverter.

## 8. Open Questions (butuh jawaban user/dosen)

1. D1: setuju Flutter (amandemen PRD) atau tetap Kotlin native?
2. Backend B1–B10 dikerjakan di repo ini (folder `backend/`) — dipindah dari repo web pada 2026-09-29.
3. minSdk 26 final? (PRD open question)
4. Kota seed data toko untuk demo LBS?
5. Siapa pemilik Gemini API key + kuota free tier?
6. Distribusi demo: debug APK sideload cukup?

## 9. Out of Scope (dari PRD §5)

iOS, Firebase apa pun, WorthCoin/kripto, blockchain desentralisasi, prediksi harga ML, payment, chat antar-user, Play Store release. App tidak scraping sendiri.
