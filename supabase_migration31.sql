-- Migration 31: Diskon khusus customer bisa pilih BEBERAPA toko sekaligus
-- Ganti dari kolom tunggal product_discount_rules.customer_id (migration30, 1 toko
-- per aturan) jadi tabel junction many-to-many, mirip pola discount_group_members
-- yang sudah ada. Kosong = aturan umum (semua toko). Diisi 1+ toko = cuma berlaku
-- buat toko-toko itu.
-- Jalankan di Supabase SQL Editor

CREATE TABLE IF NOT EXISTS product_discount_rule_customers (
  rule_id     UUID NOT NULL REFERENCES product_discount_rules(id) ON DELETE CASCADE,
  customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  PRIMARY KEY (rule_id, customer_id)
);

ALTER TABLE product_discount_rule_customers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated_all" ON product_discount_rule_customers
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Migrasikan data lama dari kolom customer_id (kalau migration30 sudah pernah dijalankan)
INSERT INTO product_discount_rule_customers (rule_id, customer_id)
SELECT id, customer_id FROM product_discount_rules
WHERE customer_id IS NOT NULL
ON CONFLICT DO NOTHING;

-- Kolom lama sudah tidak dipakai lagi (diganti tabel junction di atas)
ALTER TABLE product_discount_rules DROP COLUMN IF EXISTS customer_id;
