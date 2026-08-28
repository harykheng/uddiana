-- Migration 28: Diskon bertingkat per item (contoh: 20%+5%)
-- item_discount tetap tier pertama, item_discount2 tier kedua (opsional).
-- Cuma berlaku kalau discount_type = 'percent' — dihitung compound/bertingkat
-- (bukan dijumlah): harga setelah diskon = harga * (1 - d1/100) * (1 - d2/100).
-- Jalankan di Supabase SQL Editor

ALTER TABLE invoice_items
  ADD COLUMN IF NOT EXISTS item_discount2 NUMERIC DEFAULT 0;
