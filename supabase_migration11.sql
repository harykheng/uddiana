-- Migration 11: Tabel untuk fitur Scan Stock Opname
-- Jalankan di Supabase SQL Editor

-- 1. Sesi opname
CREATE TABLE IF NOT EXISTS opname_sessions (
  id              uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
  name            text NOT NULL,
  created_by_id   uuid,
  created_by_name text,
  status          text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'closed')),
  notes           text,
  created_at      timestamptz DEFAULT now(),
  closed_at       timestamptz
);
ALTER TABLE opname_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "authenticated_all" ON opname_sessions
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 2. Item yang sudah di-scan per sesi
CREATE TABLE IF NOT EXISTS opname_items (
  id              uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
  session_id      uuid REFERENCES opname_sessions(id) ON DELETE CASCADE,
  product_id      uuid REFERENCES products(id) ON DELETE RESTRICT,
  product_name    text NOT NULL,
  system_stock    integer NOT NULL,
  physical_stock  integer NOT NULL,
  diff            integer NOT NULL, -- physical_stock - system_stock
  scanned_by_id   uuid,
  scanned_by_name text,
  scanned_at      timestamptz DEFAULT now()
);
ALTER TABLE opname_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "authenticated_all" ON opname_items
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Index untuk lookup cepat
CREATE INDEX IF NOT EXISTS idx_opname_items_session ON opname_items(session_id);
CREATE INDEX IF NOT EXISTS idx_opname_items_product ON opname_items(session_id, product_id);
