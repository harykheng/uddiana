-- Migration 19: Cegah duplikat scan produk yang sama dalam satu sesi opname
-- Jalankan di Supabase SQL Editor

-- Hapus dulu duplikat lama (kalau ada) sebelum constraint dipasang,
-- simpan yang paling baru (scanned_at terbesar) per (session_id, product_id)
DELETE FROM opname_items a
USING opname_items b
WHERE a.session_id = b.session_id
  AND a.product_id = b.product_id
  AND a.scanned_at < b.scanned_at;

ALTER TABLE opname_items
  ADD CONSTRAINT opname_items_session_product_unique UNIQUE (session_id, product_id);
