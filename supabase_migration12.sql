-- Migration 12: Tambah price_verified_at ke tabel products
-- Jalankan di Supabase SQL Editor

-- 1. Tambah kolom
ALTER TABLE products
  ADD COLUMN IF NOT EXISTS price_verified_at timestamptz;

-- 2. Backfill: isi berdasarkan faktur yang sudah approved
--    Ambil waktu verified_at terbaru dari faktur approved yang mengandung produk tersebut
UPDATE products p
SET price_verified_at = (
  SELECT MAX(COALESCE(i.verified_at, i.updated_at))
  FROM invoices i
  JOIN invoice_items ii ON ii.invoice_id = i.id
  WHERE ii.product_id = p.id
    AND i.verification_status = 'approved'
)
WHERE EXISTS (
  SELECT 1
  FROM invoices i
  JOIN invoice_items ii ON ii.invoice_id = i.id
  WHERE ii.product_id = p.id
    AND i.verification_status = 'approved'
);
