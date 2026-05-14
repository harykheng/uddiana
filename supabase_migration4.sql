-- ============================================================
-- MIGRATION 4: Per-item discount
-- Jalankan di Supabase SQL Editor
-- ============================================================

ALTER TABLE invoice_items ADD COLUMN IF NOT EXISTS item_discount numeric DEFAULT 0;
