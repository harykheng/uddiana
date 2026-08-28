-- Migration 27: Absen Kunjungan Sales (foto + GPS + jam)
-- Sales sering klaim sudah kunjungan padahal belum. Tabel sales_visits mencatat
-- bukti kunjungan: foto (Supabase Storage bucket privat 'visit-photos', tidak
-- ada UI browse foto di admin — hanya via link WA), lokasi GPS device saat
-- submit, dan jam pakai default now() dari SERVER (bukan device) supaya nggak
-- bisa dipalsukan dari HP sales.
-- Jalankan di Supabase SQL Editor

create table if not exists sales_visits (
  id uuid default uuid_generate_v4() primary key,
  customer_id uuid references customers(id) on delete set null,
  customer_name text not null,
  store_name text,
  sales_name text not null,
  created_by_id uuid references auth.users(id),
  photo_path text not null,
  latitude double precision,
  longitude double precision,
  visited_at timestamptz not null default now()
);

-- Disable RLS (konsisten dengan tabel lain di project ini)
alter table sales_visits disable row level security;

-- Bucket privat untuk foto absen — TIDAK public, hanya bisa diakses via signed URL
insert into storage.buckets (id, name, public)
values ('visit-photos', 'visit-photos', false)
on conflict (id) do nothing;

-- User yang login (sales/admin/super_admin) boleh upload & baca foto absen
drop policy if exists "Authenticated upload visit photos" on storage.objects;
create policy "Authenticated upload visit photos" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'visit-photos');

drop policy if exists "Authenticated read visit photos" on storage.objects;
create policy "Authenticated read visit photos" on storage.objects
  for select to authenticated
  using (bucket_id = 'visit-photos');

-- Setting nomor WA tujuan absen (diisi lewat halaman Pengaturan)
insert into app_settings (key, value)
values ('absen_wa_number', '')
on conflict (key) do nothing;
