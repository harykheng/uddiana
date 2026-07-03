-- Migration 16: Payment claim oleh sales
ALTER TABLE invoices
  ADD COLUMN IF NOT EXISTS payment_claimed_at     TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS payment_claimed_amount NUMERIC(15,2),
  ADD COLUMN IF NOT EXISTS payment_claimed_method TEXT,     -- 'cash' | 'transfer'
  ADD COLUMN IF NOT EXISTS payment_claimed_by_name TEXT;
