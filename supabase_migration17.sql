-- Migration 17: Tambah kolom tanggal bayar pada payment claim dari sales
ALTER TABLE invoices
  ADD COLUMN IF NOT EXISTS payment_claimed_date DATE;
