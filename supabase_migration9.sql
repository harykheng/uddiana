-- Migration 9: Grup Varian untuk Diskon
-- Jalankan di Supabase SQL Editor

-- 1. Tabel grup varian
CREATE TABLE IF NOT EXISTS discount_groups (
  id          UUID    DEFAULT gen_random_uuid() PRIMARY KEY,
  name        TEXT    NOT NULL,
  description TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE discount_groups ENABLE ROW LEVEL SECURITY;
CREATE POLICY "authenticated_all" ON discount_groups
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 2. Anggota grup (many-to-many: grup ↔ produk)
CREATE TABLE IF NOT EXISTS discount_group_members (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  group_id   UUID NOT NULL REFERENCES discount_groups(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES products(id)        ON DELETE CASCADE,
  UNIQUE(group_id, product_id)
);
ALTER TABLE discount_group_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY "authenticated_all" ON discount_group_members
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 3. Tambah kolom group_id ke product_discount_rules & buat product_id opsional
ALTER TABLE product_discount_rules
  ADD COLUMN IF NOT EXISTS group_id UUID REFERENCES discount_groups(id) ON DELETE CASCADE;

-- Hapus constraint NOT NULL dari product_id (jika ada) agar bisa null untuk rule berbasis grup
ALTER TABLE product_discount_rules
  ALTER COLUMN product_id DROP NOT NULL;
