-- ============================================================
-- MIGRATION: Jalankan di Supabase SQL Editor
-- ============================================================

-- 1. Tambah kolom harga shopee di products
ALTER TABLE products ADD COLUMN IF NOT EXISTS price_shopee decimal(15,2) NOT NULL DEFAULT 0;

-- 2. Buat tabel customers
CREATE TABLE IF NOT EXISTS customers (
  id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
  name text NOT NULL,
  store_name text,
  phone text,
  address text,
  notes text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'update_customers_updated_at'
  ) THEN
    CREATE TRIGGER update_customers_updated_at
      BEFORE UPDATE ON customers
      FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  END IF;
END $$;

ALTER TABLE customers DISABLE ROW LEVEL SECURITY;

-- 3. Tambah kolom baru di invoices
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS customer_id uuid REFERENCES customers(id) ON DELETE SET NULL;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS store_name text;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS payment_term text NOT NULL DEFAULT 'cod';
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS price_mode text NOT NULL DEFAULT 'regular';
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS payment_method text;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS payment_date date;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS payment_notes text;

-- 4. Default status invoice jadi pending (belum lunas)
ALTER TABLE invoices ALTER COLUMN status SET DEFAULT 'pending';

-- ============================================================
-- SELESAI
-- ============================================================
