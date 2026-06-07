-- Migration 8: Diskon per item + tabel aturan diskon produk
-- Jalankan di Supabase SQL Editor

-- 1. Tambah kolom discount_type ke invoice_items
--    item_discount tetap menyimpan nilai (% atau Rp tergantung discount_type)
ALTER TABLE invoice_items
  ADD COLUMN IF NOT EXISTS discount_type VARCHAR(10) DEFAULT 'percent'
  CHECK (discount_type IN ('percent', 'nominal'));

-- 2. Tabel aturan diskon per produk
CREATE TABLE IF NOT EXISTS product_discount_rules (
  id              UUID          DEFAULT gen_random_uuid() PRIMARY KEY,
  product_id      UUID          NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  description     TEXT,                          -- Label, cth: "6 Lusin ke atas"
  min_qty         INTEGER       DEFAULT 0,        -- Min qty (pcs), 0 = tanpa syarat qty
  min_amount      NUMERIC       DEFAULT 0,        -- Min nilai beli (Rp), 0 = tanpa syarat nilai
  discount_type   VARCHAR(10)   NOT NULL CHECK (discount_type IN ('percent', 'nominal')),
  discount_value  NUMERIC       NOT NULL DEFAULT 0,  -- Nilai: angka % atau Rp
  is_active       BOOLEAN       DEFAULT true,
  created_at      TIMESTAMPTZ   DEFAULT NOW()
);

-- 3. RLS
ALTER TABLE product_discount_rules ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated_all" ON product_discount_rules
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Contoh data (opsional — hapus jika tidak perlu):
-- INSERT INTO product_discount_rules (product_id, description, min_qty, discount_type, discount_value)
-- SELECT id, '6 Lusin ke atas', 72, 'percent', 5 FROM products WHERE name ILIKE '%contoh%' LIMIT 1;
