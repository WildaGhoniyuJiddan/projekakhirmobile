# SUPABASE_SETUP — Menyiapkan Backend Supabase WorthBang

Versi full-Dart ini tidak memakai server Python lagi. Backend-nya
Supabase: Postgres (data + RLS + RPC), Auth, dan satu Edge Function
(`bang-worth`) untuk chatbot Gemini. Ikuti langkah berurutan.

## 1. Cek proyek Supabase

1. Buka https://supabase.com/dashboard — gunakan proyek yang sama
   dengan backend lama (tabel `raw_listings`, `pc_components`,
   `laptop_units`, `analysis_logs` harus sudah ada di dalamnya;
   migrasi di repo ini hanya menambah RLS, tabel `profiles`,
   kolom `user_uuid`, dan RPC `match_listings`).
2. Di **Project Settings → API**, catat **Project URL** dan
   **anon public key**. Anon key aman dibundel di APK (proteksi
   data ada di RLS). Yang TIDAK boleh masuk APK/repo:
   service-role key & API key Gemini.

## 2. Isi konfigurasi aplikasi

App membaca konfigurasi lewat `--dart-define` (lihat
`lib/config/supabase_config.dart`), jadi tidak ada file yang perlu
diedit:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-public-key>
```

## 3. Pasang Supabase CLI & login

```bash
npm install -g supabase   # atau cara lain di https://supabase.com/docs/guides/cli
supabase login
```

## 4. Link proyek & terapkan migrasi SQL

Dari root repo ini:

```bash
supabase link --project-ref <project-ref>
supabase db push
```

`db push` menerapkan `supabase/migrations/20261020000001_init.sql`:
RLS read-only untuk tabel katalog, RLS `analysis_logs` per user,
tabel `profiles`, dan fungsi RPC `match_listings`.

## 5. Set secret Gemini & deploy Edge Function

```bash
supabase secrets set GEMINI_API_KEY=<api-key-gemini-kamu>
# Opsional, default-nya gemini-1.5-flash:
# supabase secrets set GEMINI_MODEL=gemini-1.5-flash

supabase functions deploy bang-worth
```

Fungsi `bang-worth` memverifikasi JWT user (wajib login), menjalankan
scope-guard topik, lalu memanggil Gemini dengan data grounding dari
`retail_catalog.json` + `consensus_scores.json` yang dibundel di
folder fungsi.

## 6. Uji cepat

1. Jalankan app (langkah 2), login/register.
2. Buka chat Bang Worth, tanya misalnya "rakit PC gaming 10 juta" —
   harus dijawab rekomendasi. Tanya di luar topik (mis. resep) —
   harus ditolak sopan.

## 7. Build APK release

```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-public-key>
```
