-- Migration 13: Tambah last_opname_session_id ke tabel products
-- Jalankan di Supabase SQL Editor

-- 1. Tambah kolom
ALTER TABLE products
  ADD COLUMN IF NOT EXISTS last_opname_session_id uuid;

-- 2. Backfill: isi dari opname_items berdasarkan scan terakhir per produk
UPDATE products p
SET last_opname_session_id = (
  SELECT oi.session_id
  FROM opname_items oi
  WHERE oi.product_id = p.id
  ORDER BY oi.scanned_at DESC
  LIMIT 1
)
WHERE EXISTS (
  SELECT 1 FROM opname_items oi WHERE oi.product_id = p.id
);
