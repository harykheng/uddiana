-- Migration 18: Catatan dari sales saat lapor bayar
ALTER TABLE invoices
  ADD COLUMN IF NOT EXISTS payment_claimed_note TEXT;
