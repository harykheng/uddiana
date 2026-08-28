-- Migration 29: Diskon bertingkat (tier 2) di aturan diskon produk
-- Sama seperti item_discount2 di invoice_items (migration28) — cuma berlaku
-- kalau discount_type = 'percent', dihitung compound saat auto-apply ke faktur.
-- Jalankan di Supabase SQL Editor

ALTER TABLE product_discount_rules
  ADD COLUMN IF NOT EXISTS discount_value2 NUMERIC DEFAULT 0;
