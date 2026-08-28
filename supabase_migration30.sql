-- Migration 30: Diskon khusus customer (per toko) di aturan diskon produk
-- customer_id NULL = aturan berlaku umum (semua toko, perilaku lama).
-- customer_id diisi = aturan CUMA berlaku buat toko itu. Kalau ada aturan
-- umum & khusus toko yang sama-sama cocok, yang khusus toko diprioritaskan
-- (lihat logic pemilihan "best rule" di invoices.html & sales.html).
-- Jalankan di Supabase SQL Editor

ALTER TABLE product_discount_rules
  ADD COLUMN IF NOT EXISTS customer_id UUID REFERENCES customers(id) ON DELETE CASCADE;
