-- Migration 14: Batch number & expired date tracking di purchase_items
-- Jalankan di Supabase SQL Editor

ALTER TABLE purchase_items
  ADD COLUMN IF NOT EXISTS batch_number VARCHAR(100),
  ADD COLUMN IF NOT EXISTS expired_date DATE;

-- Index untuk query produk yang akan kadaluarsa
CREATE INDEX IF NOT EXISTS idx_purchase_items_expired_date
  ON purchase_items (expired_date)
  WHERE expired_date IS NOT NULL;
