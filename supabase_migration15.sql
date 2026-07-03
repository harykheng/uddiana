-- Migration 15: Tandai faktur yang sudah dicetak
ALTER TABLE invoices
  ADD COLUMN IF NOT EXISTS printed_at  TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS print_count INT NOT NULL DEFAULT 0;
