-- Rakitan Impian (dream builds) + penjangkaran blockchain Polygon Amoy.
--
-- Draft kartu hidup 100% di Postgres (gratis diedit). Saat diterbitkan,
-- Edge Function `publish-build` menyusun teks kanonik kartu (spek
-- WB-DREAM-v1, lihat contracts/README.md), menghitung SHA-256-nya, dan
-- mencatat hash itu ke smart contract DreamBuildRegistry (testnet).
-- Kolom content_hash/tx_hash/published_* adalah catatan penerbitan
-- TERAKHIR; mengedit kartu terbit menaikkan version dan mengembalikan
-- status ke 'draft' tanpa menghapus catatan itu.
--
-- Aman dijalankan ulang (idempotent): if-not-exists / drop-policy-if-exists.

-- ---------------------------------------------------------------------
-- dream_builds: satu kartu Rakitan Impian per baris.
-- ---------------------------------------------------------------------
create table if not exists public.dream_builds (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null,
  name text not null,
  version int not null default 1,
  status text not null default 'draft'
    check (status in ('draft', 'published')),
  content_hash text,
  tx_hash text,
  published_version int,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists ix_dream_builds_owner
  on public.dream_builds (owner_id);

alter table public.dream_builds enable row level security;

-- Pemilik: semua operasi pada kartunya sendiri.
drop policy if exists "dream_builds_owner_all" on public.dream_builds;
create policy "dream_builds_owner_all" on public.dream_builds
  for all to authenticated
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

-- Publik: hanya membaca kartu yang sudah diterbitkan (halaman verifikasi).
drop policy if exists "dream_builds_public_read_published"
  on public.dream_builds;
create policy "dream_builds_public_read_published" on public.dream_builds
  for select to anon, authenticated
  using (status = 'published');

-- ---------------------------------------------------------------------
-- dream_build_items: isi part kartu, satu baris per slot terisi.
-- ---------------------------------------------------------------------
create table if not exists public.dream_build_items (
  id bigint generated always as identity primary key,
  build_id uuid not null references public.dream_builds (id)
    on delete cascade,
  slot text not null,
  part_name text not null,
  price int not null,
  sort int not null default 0
);

create index if not exists ix_dream_build_items_build
  on public.dream_build_items (build_id);

alter table public.dream_build_items enable row level security;

-- Pemilik: semua operasi pada item dari kartu miliknya (lewat join).
drop policy if exists "dream_build_items_owner_all"
  on public.dream_build_items;
create policy "dream_build_items_owner_all" on public.dream_build_items
  for all to authenticated
  using (
    exists (
      select 1 from public.dream_builds b
      where b.id = build_id and b.owner_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.dream_builds b
      where b.id = build_id and b.owner_id = auth.uid()
    )
  );

-- Publik: item dari kartu terbit saja.
drop policy if exists "dream_build_items_public_read_published"
  on public.dream_build_items;
create policy "dream_build_items_public_read_published"
  on public.dream_build_items
  for select to anon, authenticated
  using (
    exists (
      select 1 from public.dream_builds b
      where b.id = build_id and b.status = 'published'
    )
  );
