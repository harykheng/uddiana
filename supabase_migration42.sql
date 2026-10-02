-- Migration 42: Jadwal Kunjungan Sales (pengganti jadwal mingguan di kertas HVS)
-- Tiap baris = satu toko masuk jalur satu sales di satu hari. Jadwalnya berulang
-- tiap minggu sampai diubah super_admin di jadwal-kunjungan.html.
--
-- Toko WAJIB dikunjungi minggu ini atau tidak TIDAK disimpan di sini — dihitung
-- otomatis di sales.html (tab "Hari Ini") dari faktur:
--   * PO kurang dari 10 hari lalu     → minggu ini tidak perlu didatangi
--   * kecuali every_week = true, atau toko punya tagihan jatuh tempo (datang nagih)
-- Jadi pola "PO → 2 minggu lagi, tidak PO → minggu depan lagi" jalan sendiri tanpa
-- ada yang perlu diisi tiap minggu.
-- Jalankan di Supabase SQL Editor

create table if not exists visit_schedules (
  id uuid default uuid_generate_v4() primary key,
  customer_id uuid not null references customers(id) on delete cascade,
  sales_id uuid not null references user_profiles(id) on delete cascade,
  -- 1 = Senin ... 7 = Minggu (sama dengan ISO day of week)
  day_of_week smallint not null check (day_of_week between 1 and 7),
  -- Toko yang tetap didatangi tiap minggu walaupun minggu lalu sudah PO
  every_week boolean not null default false,
  -- true = toko baru yang ditambahkan sales sendiri dari lapangan, otomatis masuk
  -- jadwal sales itu di hari itu, tapi belum dicek super_admin (label 🆕)
  needs_review boolean not null default false,
  added_by_id uuid references auth.users(id),
  created_at timestamptz not null default now(),
  -- Satu toko boleh di beberapa hari (toko besar Senin & Kamis), tapi tidak dobel
  -- di hari & sales yang sama
  unique (customer_id, sales_id, day_of_week)
);

create index if not exists visit_schedules_sales_day_idx on visit_schedules (sales_id, day_of_week);
create index if not exists visit_schedules_customer_idx on visit_schedules (customer_id);

-- Disable RLS (konsisten dengan tabel lain di project ini)
alter table visit_schedules disable row level security;

-- Target jumlah toko per hari per sales — bisa diubah di jadwal-kunjungan.html
insert into app_settings (key, value)
values ('visit_target_per_day', '12')
on conflict (key) do nothing;

-- Masa uji coba: tab "Hari Ini" di sales.html cuma tampil untuk akun yang dipilih
-- di jadwal-kunjungan.html. '' = belum ke siapa pun, <user id> = satu akun (mis.
-- akun test sales), 'all' = semua sales. Toko baru otomatis masuk jadwal juga
-- cuma untuk akun yang aktif.
insert into app_settings (key, value)
values ('jadwal_tab_visible_for', '')
on conflict (key) do nothing;
