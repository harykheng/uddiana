-- Migration 26: View publik read-only untuk katalog produk (domain terpisah)
-- Katalog (diana-kosmetik-katalog) query view ini, BUKAN tabel products langsung,
-- supaya kolom sensitif (cost, stock_quantity, min_stock) tidak pernah ke-expose
-- lewat anon key meskipun anon key katalog sama dengan anon key StokManager.
-- View berjalan dengan hak akses pembuatnya (bukan security_invoker), jadi tetap
-- bisa SELECT walau RLS di tabel products/categories nanti diaktifkan/diperketat.
-- Jalankan di Supabase SQL Editor

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
where p.is_active = true;

grant select on public_catalog_products to anon;
grant select on public_catalog_products to authenticated;
