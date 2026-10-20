# API Contract — WorthBang Android ↔ FastAPI Backend

> Single source of truth untuk Agent Backend (repo `WorthGaBang`, folder `backend/`)
> dan Agent App (repo `WorthGaBang-AndroidVer`, Flutter).
> Base URL dev: `http://10.0.2.2:8000` (emulator) / `http://<LAN-IP>:8000` (HP fisik).
> Semua request/response JSON. Auth: `Authorization: Bearer <access_token>` kecuali ditandai Public.
>
> ## Revisi 2026-10-12 — Fase 3 (Opsi 1: backend ramping)
> Backend hanya melayani endpoint yang **tidak bisa** dihitung lokal:
> `POST /api/v1/auth/*` (register, login, refresh, logout),
> `GET/POST /api/v1/history`, `POST /api/v1/chat/ask`,
> `POST /api/v1/analyze`, `POST /api/v1/analyze-bundle`,
> `GET /api/v1/suggest/{section}`, `GET /health`, `GET /api/v1/debug/*`.
>
> Endpoint berikut **DICABUT dari backend** dan diimplementasi 100% lokal di Dart:
> wishlist (B2) → Drift; alerts (B3) → Drift + `/api/v1/analyze` untuk cek harga;
> stores (B4) → `assets/data/stores_jakarta.csv`; trend (B5) → statistik katalog lokal;
> builder (B6) → katalog bundled; game (B8) → katalog bundled;
> currency (B9) → langsung ke open.er-api.com + fallback;
> feedback & profile (B9) → SharedPreferences.
> Bagian B2–B6, B8–B9 di bawah ini dipertahankan sebagai dokumentasi historis.

## Konvensi

- Harga dalam **IDR integer** (rupiah, tanpa desimal).
- Timestamp: ISO-8601 UTC (`2026-09-29T10:00:00Z`).
- Verdict dari backend: `"worth it" | "wajar" | "ada opsi lebih baik" | "kemahalan" | "data terbatas"`.
- Error: `{detail: string}` dengan status HTTP yang sesuai (400/401/404/409/422).

---

## A. Endpoint EXISTING (jangan diubah, dipakai ulang)

### POST /api/v1/analyze (Public)
```jsonc
// request
{ "mode": "pc" | "laptop", "query": "RTX 4060", "price": 4500000,
  "component_type": "gpu", "brand": null, "model": null,
  "cpu": null, "gpu": null, "ram_gb": null, "storage_gb": null,
  "screen_size": null, "condition": "any" }   // condition: "any"|"baru"|"bekas"
// response 200
{ "mode": "pc", "query": "RTX 4060", "input_price": 4500000,
  "score": 82.5, "verdict": "wajar", "recommendation": "...",
  "reference_price": 4600000, "price_delta_percent": -2.2,
  "fair_price_low": 4200000, "fair_price_high": 4900000,
  "tier_label": null, "new_reference_price": 5200000,
  "used_reference_price": 4100000, "cross_market_advice": "...",
  "comparisons": [ { "title": "...", "price": 4550000, "source": "tokopedia",
                     "listing_url": "...", "similarity": 0.92, "condition": "baru" } ],
  "alternatives": [ { "name": "RTX 4060 Ti", "score": 12345,
                      "est_price_idr": 6800000, "gain_percent": 18 } ],
  "freshness": { "last_updated_at": "...", "age_seconds": 3600,
                 "label": "1 jam lalu", "is_stale": false, "primary_source": "tokopedia" } }
```
For `mode: "pc"`, `comparisons` also includes matching new products from the bundled retail catalog (`source: "komponen_retail"`, `condition: "new"`, and `listing_url: null`). These catalog products remain available when marketplace listings have not been ingested yet; they are not marketplace listings.
Benchmark alternatives use the submitted `price` as the maximum estimated purchase budget and are ranked by highest verified performance within that budget. PassMark verifies performance when available; consensus-only candidates are used only when the input model has no PassMark score.

### POST /api/v1/search (Public)
Search listings without price scoring or benchmark recommendations. This is the endpoint used by the Cari Produk screen.
```jsonc
// request
{ "mode": "pc", "query": "RTX 4060", "condition": "any" }
// response
{ "query": "RTX 4060", "comparisons": [ { "title": "...", "price": 4550000,
  "source": "komponen_retail", "listing_url": null, "similarity": 0.92,
  "condition": "new" } ] }
```

### POST /api/v1/analyze-bundle (Public)
```jsonc
// request
{ "items": [ {"query": "Ryzen 5 5600", "component_type": "cpu", "price": 1800000} ],
  "bundle_price": 8500000, "condition": "any" }   // 1–6 items
// response 200 — BundleResponse (bundle_price, reference_total, score, verdict,
// recommendation, savings_percent, items[])
```

### GET /api/v1/suggest/{section}?q=&limit=&condition= (Public)
- `section`: `pc` | `laptop`; `condition`: `baru|bekas|any`; `q` min 2 char (frontend debounce 300ms).
```jsonc
// response 200
{ "section": "pc", "suggestions": ["RTX 4060 8GB", "RTX 4060 Ti", "..."] }
```

### GET /api/v1/freshness (Public)
```jsonc
// response 200
{ "sources": { "tokopedia": {"label": "2 jam lalu", "is_stale": false, "...": "..."} } }
```

---

## B. Endpoint BARU (dibangun Agent Backend)

### B1 — Auth

#### POST /api/v1/auth/register (Public)
```jsonc
// request
{ "name": "Dan", "email": "dan@example.com", "password": "min8karakter" }
// response 201 → sama seperti login (langsung login)
// response 409 {detail: "Email already registered"}
```

#### POST /api/v1/auth/login (Public)
```jsonc
// request
{ "email": "dan@example.com", "password": "..." }
// response 200
{ "access_token": "jwt...", "refresh_token": "jwt...", "token_type": "bearer",
  "user": {"id": 1, "name": "Dan", "email": "dan@example.com", "photo_url": null} }
// response 401 {detail: "Invalid email or password"}  (jangan bocorkan field mana yang salah)
```

#### POST /api/v1/auth/refresh (Public)
```jsonc
// request
{ "refresh_token": "jwt..." }
// response 200
{ "access_token": "jwt...", "refresh_token": "jwt...", "token_type": "bearer" }
// response 401 → app harus logout paksa
```

#### POST /api/v1/auth/logout (Auth)
- Revoke refresh token server-side. Response 204.

> Aturan: password di-hash **bcrypt server-side** saja. Access token JWT 15 menit, refresh token 7 hari.

### B2 — History & Wishlist

#### GET /api/v1/history (Auth)
```jsonc
// response 200 — newest first
{ "items": [ { "id": 12, "mode": "pc", "query": "RTX 4060", "input_price": 4500000,
               "score": 82.5, "verdict": "wajar", "created_at": "..." } ] }
```

#### POST /api/v1/history (Auth) — B10: backup/sync hash-chain dari app
```jsonc
// request
{ "mode": "pc", "query": "RTX 4060", "input_price": 4500000,
  "score": 82.5, "verdict": "wajar", "created_at": "2026-09-29T10:00:00Z" }  // created_at opsional
// response 201 → item history yang tersimpan (bentuk sama seperti GET)
// Dipakai T6 (sync opsional) & T15 (antrean offline): app push entri hash-chain lokal.
// Catatan validasi: `query`/`verdict` di-strip saat validasi (min_length berlaku
// untuk nilai yang sudah di-strip); `created_at` naive dianggap UTC, aware
// dikonversi ke UTC, timestamp masa depan di-clamp ke waktu server.
// > Follow-up idempotency (belum diimplementasikan): endpoint ini dipakai untuk
// > retry offline-sync, sehingga retry dapat menduplikasi entri identik.
// > Rekomendasi: client kirim idempotency key (mis. UUID per entri lokal) ATAU
// > tambah unique constraint (user_id, created_at, input_query) di DB.
```

#### GET /api/v1/wishlist (Auth) → `{items: [{id, query, mode, target_price?, created_at}]}`
#### POST /api/v1/wishlist (Auth) `{query, mode, target_price?}` → 201 item
#### DELETE /api/v1/wishlist/{id} (Auth) → 204

### B3 — Alerts

#### POST /api/v1/alerts (Auth)
```jsonc
// request
{ "query": "RTX 4060", "mode": "pc", "target_price": 4300000, "condition": "any" }
// response 201
{ "id": 5, "query": "RTX 4060", "target_price": 4300000,
  "current_price": 4600000, "is_active": true }
```
#### GET /api/v1/alerts (Auth) → `{items: [...]}` (tiap item sertakan `current_price`)
#### DELETE /api/v1/alerts/{id} (Auth) → 204

### B4 — Stores (LBS)

#### GET /api/v1/stores/nearby?lat=-6.2&lng=106.8&radius_km=10 (Public)
```jsonc
// response 200
{ "stores": [ { "id": 1, "name": "Toko Komputer ABC", "address": "Jl. ...",
                "lat": -6.21, "lng": 106.81, "distance_km": 1.4,
                "prices": {"RTX 4060": 4550000} } ] }
```
> Seed CSV untuk kota demo supaya tidak kosong.

### B5 — Trend

#### GET /api/v1/trend?query=RTX%204060&days=30 (Public)
```jsonc
// response 200
{ "query": "RTX 4060", "days": 30,
  "points": [ {"date": "2026-08-30", "price": 4700000}, "..." ],
  "min": 4400000, "max": 4800000, "avg": 4600000,
  "change_percent": -6.7,
  "summary": "Down 6.7% in the last 30 days — current price is below the period average." }
```
> TIDAK ada prediksi harga masa depan. Deskriptif saja.

### B6 — Random builder

#### POST /api/v1/builder/random (Public)
```jsonc
// request
{ "budget": 10000000, "use_case": "gaming" }   // use_case: gaming|office|editing
// response 200
{ "cpu": {"name": "Ryzen 5 5600", "price": 1850000}, "gpu": {...},
  "ram": {...}, "ssd": {...}, "psu": {...},
  "total": 9800000, "budget": 10000000 }
```

### B7 — Chatbot

#### POST /api/v1/chat/ask (Auth opsional — Public untuk demo)
```jsonc
// request
{ "message": "rakit PC 8 juta buat gaming", "history": [{"role":"user","text":"..."}] }
// response 200
{ "reply": "Berikut rakitan ...",
  "build": { "items": [{"component": "CPU", "name": "Ryzen 5 5600", "price": 1850000}],
             "total": 7950000, "note": "..." } }
```
> Backend yang panggil Gemini (free tier). App TIDAK pernah pegang API key.
> **Scope guard:** chatbot hanya melayani topik aplikasi (komponen PC/laptop, harga &
> kelayakannya, rekomendasi rakitan, cara pakai fitur). Pesan di luar topik langsung
> ditolak tanpa memanggil Gemini:
> ```jsonc
> // request: { "message": "bagi resep rendang dong" }
> // response 200
> { "reply": "Hmm, itu di luar keahlianku 😅 Aku Bang Worth, asisten khusus komponen PC & laptop - tanya soal harga, rakitan, atau perbandingan komponen aja ya!",
>   "build": null }
> ```

### B8 — Game

#### GET /api/v1/game/question (Public)
```jsonc
// response 200
{ "question_id": "q-abc123", "product": "RTX 4060 8GB",
  "specs": "GPU NVIDIA, 8GB GDDR6 ...", "hint": "..." }   // TANPA harga
```
#### POST /api/v1/game/submit (Public)
```jsonc
// request
{ "question_id": "q-abc123", "guess_idr": 4000000 }
// response 200
{ "actual_price": 4600000, "difference": -600000,
  "score": 87 }   // score = round(max(0, 100 - |guess-actual|/actual*100))
```

### B9 — Currency, Feedback, Profile

#### GET /api/v1/currency/rates?base=IDR (Public)
```jsonc
// response 200
{ "base": "IDR", "rates": {"USD": 0.000062, "SGD": 0.000083, "MYR": 0.00029},
  "updated_at": "..." }   // cache backend ≤1 jam
```
#### POST /api/v1/feedback (Auth)
`{ "rating": 5, "kesan": "...", "saran": "..." }` → 201
#### PUT /api/v1/users/me (Auth, multipart)
Form `photo` (file) dan/atau `name` → `{id, name, email, photo_url}`

---

## C. Catatan untuk kedua agent

1. Field baru **hanya boleh tambah opsional** — jangan ubah field existing (kompatibilitas web).
2. Semua teks user-facing di app: Bahasa Indonesia. Error backend boleh Inggris singkat.
3. Pagination: `?limit=&offset=` bila daftar > 50 (history, wishlist).
4. Jika backend belum siap saat app butuh, app pakai `FakeApiClient` yang mengimplementasikan interface yang sama persis dengan kontrak ini.
