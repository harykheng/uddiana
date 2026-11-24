-- ============================================================
-- Migration 49: Katalog online menyembunyikan produk tanpa harga jual
-- ============================================================
-- Form Pembelian (purchases.html) sekarang bisa membuat produk baru langsung
-- dari baris barang, dan harga jualnya boleh menyusul (disimpan 0). Begitu PO
-- disimpan, stok produk itu > 0. Tanpa migration ini produk tsb langsung tampil
-- Rp 0 di link katalog semua toko, karena view public_catalog_products
-- (migration26) cuma menyaring is_active.
--
-- Migration ini menambah syarat `p.price > 0`. Kolom view TIDAK berubah, jadi
-- repo katalog (diana-kosmetik-katalog) tidak perlu diubah.
--
-- SEBELUM DIJALANKAN — cek definisi view yang sedang live:
--   select pg_get_viewdef('public_catalog_products', true);
-- Kalau isinya bukan lagi persis seperti migration26 (misal sudah ditambah
-- filter/kolom lain langsung di SQL Editor), JANGAN jalankan file ini apa
-- adanya — tambahkan saja `and p.price > 0` ke definisi yang live. Blok di
-- bawah membatalkan migration kalau daftar kolom view sudah berbeda.
--
-- Aman dijalankan ulang. Jalankan di Supabase SQL Editor.
-- ============================================================

do $$
declare
  kolom text;
begin
  select string_agg(column_name, ',' order by ordinal_position) into kolom
  from information_schema.columns
  where table_schema = 'public' and table_name = 'public_catalog_products';

  if kolom is distinct from 'id,name,sku,description,price,unit,category_id,category_name' then
    raise exception 'Kolom public_catalog_products berbeda dari migration26 (%). Tambahkan "and p.price > 0" ke definisi view yang live secara manual.', kolom;
  end if;
end $$;

create or replace view public_catalog_products as
select
  p.id,
  p.name,
  p.sku,
  p.description,
  p.price,
  p.unit,
  p.category_id,
  c.name as category_name
from products p
left join categories c on c.id = p.category_id
where p.is_active = true
  and p.price > 0;

grant select on public_catalog_products to anon;
grant select on public_catalog_products to authenticated;
