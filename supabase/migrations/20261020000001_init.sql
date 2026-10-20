-- Migrasi awal projekakhirmobile (full-Dart + Supabase).
--
-- ASUMSI: proyek Supabase yang sama dengan backend Python lama, jadi
-- tabel aplikasi (raw_listings, pc_components, laptop_units,
-- analysis_logs, ...) SUDAH ADA. File ini hanya menambah tabel
-- `profiles`, kolom `analysis_logs.user_uuid`, Row Level Security,
-- dan fungsi RPC `match_listings`. Aman dijalankan ulang
-- (idempotent): pakai if-not-exists / drop-policy-if-exists.
--
-- Catatan: koneksi langsung Postgres (backend lama & scraper) memakai
-- role pemilik tabel yang melewati RLS secara default, jadi RLS di
-- sini hanya mengatur akses lewat PostgREST (anon/authenticated).

-- ---------------------------------------------------------------------
-- profiles: 1 baris per user Supabase Auth (id = auth.users.id)
-- ---------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  name text,
  photo_url text,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- User hanya boleh membaca baris profilnya sendiri.
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles
  for select to authenticated
  using (auth.uid() = id);

-- Insert saat register: id baris harus sama dengan uid pendaftar.
drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own" on public.profiles
  for insert to authenticated
  with check (auth.uid() = id);

-- User hanya boleh mengubah baris profilnya sendiri.
drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- ---------------------------------------------------------------------
-- Katalog pasar: read-only (SELECT saja) untuk anon & authenticated.
-- Tanpa policy tulis -> insert/update/delete tertutup secara default.
-- ---------------------------------------------------------------------
alter table public.raw_listings enable row level security;
drop policy if exists "raw_listings_read" on public.raw_listings;
create policy "raw_listings_read" on public.raw_listings
  for select to anon, authenticated
  using (true);

alter table public.pc_components enable row level security;
drop policy if exists "pc_components_read" on public.pc_components;
create policy "pc_components_read" on public.pc_components
  for select to anon, authenticated
  using (true);

alter table public.laptop_units enable row level security;
drop policy if exists "laptop_units_read" on public.laptop_units;
create policy "laptop_units_read" on public.laptop_units
  for select to anon, authenticated
  using (true);

-- ---------------------------------------------------------------------
-- analysis_logs: atribusi per user Supabase (uuid), menggantikan
-- user_id int lama. Baris lama user_uuid-nya NULL -> tidak terlihat
-- oleh user mana pun (hanya pemilik/service role yang bisa).
-- ---------------------------------------------------------------------
alter table public.analysis_logs
  add column if not exists user_uuid uuid;

create index if not exists ix_analysis_logs_user_uuid
  on public.analysis_logs (user_uuid);

alter table public.analysis_logs enable row level security;

drop policy if exists "analysis_logs_select_own" on public.analysis_logs;
create policy "analysis_logs_select_own" on public.analysis_logs
  for select to authenticated
  using (user_uuid = auth.uid());

drop policy if exists "analysis_logs_insert_own" on public.analysis_logs;
create policy "analysis_logs_insert_own" on public.analysis_logs
  for insert to authenticated
  with check (user_uuid = auth.uid());

-- ---------------------------------------------------------------------
-- RPC match_listings: prefilter listing PC, mirror
-- backend/app/services/analysis.py (_pc_comparisons):
--   raw_price 50rb-150jt, condition bukan 'issue' (NULL lolos),
--   source in (komponen_retail, tokopedia, facebook,
--   facebook_marketplace), kategori dari pemanggil, dan bila
--   p_model_num terisi: ilike di raw_title ATAU raw_spec_text.
--   Urut scraped_at desc, limit 3000.
-- p_model_num NULL/kosong = tanpa filter model (sama seperti Python
-- saat query user tidak punya token angka).
-- ---------------------------------------------------------------------
create or replace function public.match_listings(
  p_model_num text,
  p_categories text[]
)
returns setof public.raw_listings
language sql
stable
as $$
  select *
  from public.raw_listings
  where raw_price >= 50000
    and raw_price <= 150000000
    and (condition is null or condition <> 'issue')
    and source in (
      'komponen_retail', 'tokopedia', 'facebook', 'facebook_marketplace'
    )
    and (p_categories is null or category = any (p_categories))
    and (
      p_model_num is null
      or p_model_num = ''
      or raw_title ilike '%' || p_model_num || '%'
      or raw_spec_text ilike '%' || p_model_num || '%'
    )
  order by scraped_at desc
  limit 3000;
$$;

grant execute on function public.match_listings(text, text[])
  to anon, authenticated;
