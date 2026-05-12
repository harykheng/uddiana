-- ============================================================
-- MIGRATION 2: Pembelian, Keluar Barang, Laba Rugi
-- Jalankan di Supabase SQL Editor
-- ============================================================

-- 1. Tambah cost_price di invoice_items (untuk kalkulasi COGS)
ALTER TABLE invoice_items ADD COLUMN IF NOT EXISTS cost_price decimal(15,2) NOT NULL DEFAULT 0;

-- ============================================================
-- 2. Tabel PEMBELIAN (Purchase Orders)
-- ============================================================
CREATE TABLE IF NOT EXISTS purchases (
  id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
  purchase_number text UNIQUE NOT NULL DEFAULT '',
  supplier_name text,
  purchase_date date NOT NULL DEFAULT current_date,
  notes text,
  total_cost decimal(15,2) NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'received' CHECK (status IN ('received', 'cancelled')),
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS purchase_items (
  id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
  purchase_id uuid REFERENCES purchases(id) ON DELETE CASCADE,
  product_id uuid REFERENCES products(id) ON DELETE RESTRICT,
  product_name text NOT NULL,
  quantity integer NOT NULL CHECK (quantity > 0),
  cost_price decimal(15,2) NOT NULL DEFAULT 0,
  subtotal decimal(15,2) NOT NULL DEFAULT 0,
  created_at timestamp with time zone DEFAULT now()
);

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_purchases_updated_at') THEN
    CREATE TRIGGER update_purchases_updated_at
      BEFORE UPDATE ON purchases
      FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  END IF;
END $$;

-- Auto purchase number
CREATE OR REPLACE FUNCTION generate_purchase_number()
RETURNS TRIGGER AS $$
DECLARE
  seq integer;
  year_month text;
BEGIN
  year_month := to_char(now(), 'YYMM');
  SELECT coalesce(count(*), 0) + 1 INTO seq
  FROM purchases WHERE purchase_number LIKE 'PO-' || year_month || '-%';
  NEW.purchase_number := 'PO-' || year_month || '-' || lpad(seq::text, 4, '0');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'auto_purchase_number') THEN
    CREATE TRIGGER auto_purchase_number
      BEFORE INSERT ON purchases
      FOR EACH ROW WHEN (NEW.purchase_number IS NULL OR NEW.purchase_number = '')
      EXECUTE FUNCTION generate_purchase_number();
  END IF;
END $$;

-- Stock naik saat purchase_item diinsert
CREATE OR REPLACE FUNCTION increase_stock_on_purchase()
RETURNS TRIGGER AS $$
DECLARE current_stock integer;
BEGIN
  SELECT stock_quantity INTO current_stock FROM products WHERE id = NEW.product_id;
  UPDATE products SET stock_quantity = stock_quantity + NEW.quantity, cost = NEW.cost_price
  WHERE id = NEW.product_id;
  INSERT INTO stock_movements (product_id, product_name, type, quantity, quantity_before, quantity_after, reference_type, reference_id)
  VALUES (NEW.product_id, NEW.product_name, 'in', NEW.quantity, current_stock, current_stock + NEW.quantity, 'purchase', NEW.purchase_id);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'increase_stock_purchase_trigger') THEN
    CREATE TRIGGER increase_stock_purchase_trigger
      AFTER INSERT ON purchase_items
      FOR EACH ROW EXECUTE FUNCTION increase_stock_on_purchase();
  END IF;
END $$;

-- Stock turun saat purchase dibatalkan
CREATE OR REPLACE FUNCTION restore_stock_on_purchase_cancel()
RETURNS TRIGGER AS $$
DECLARE item RECORD; current_stock integer;
BEGIN
  IF NEW.status = 'cancelled' AND OLD.status != 'cancelled' THEN
    FOR item IN SELECT * FROM purchase_items WHERE purchase_id = NEW.id LOOP
      SELECT stock_quantity INTO current_stock FROM products WHERE id = item.product_id;
      UPDATE products SET stock_quantity = GREATEST(0, stock_quantity - item.quantity) WHERE id = item.product_id;
      INSERT INTO stock_movements (product_id, product_name, type, quantity, quantity_before, quantity_after, reference_type, reference_id)
      VALUES (item.product_id, item.product_name, 'out', item.quantity, current_stock, GREATEST(0, current_stock - item.quantity), 'purchase_cancel', NEW.id);
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'restore_stock_purchase_cancel_trigger') THEN
    CREATE TRIGGER restore_stock_purchase_cancel_trigger
      AFTER UPDATE ON purchases
      FOR EACH ROW EXECUTE FUNCTION restore_stock_on_purchase_cancel();
  END IF;
END $$;

ALTER TABLE purchases DISABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_items DISABLE ROW LEVEL SECURITY;

-- ============================================================
-- 3. Tabel KELUAR BARANG (Stock Transfer / Non-Sales Out)
-- ============================================================
CREATE TABLE IF NOT EXISTS stock_transfers (
  id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
  transfer_number text UNIQUE NOT NULL DEFAULT '',
  transfer_date date NOT NULL DEFAULT current_date,
  reason text NOT NULL,
  notes text,
  status text NOT NULL DEFAULT 'completed' CHECK (status IN ('completed', 'cancelled')),
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS stock_transfer_items (
  id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
  transfer_id uuid REFERENCES stock_transfers(id) ON DELETE CASCADE,
  product_id uuid REFERENCES products(id) ON DELETE RESTRICT,
  product_name text NOT NULL,
  quantity integer NOT NULL CHECK (quantity > 0),
  notes text,
  created_at timestamp with time zone DEFAULT now()
);

-- Auto transfer number
CREATE OR REPLACE FUNCTION generate_transfer_number()
RETURNS TRIGGER AS $$
DECLARE
  seq integer;
  year_month text;
BEGIN
  year_month := to_char(now(), 'YYMM');
  SELECT coalesce(count(*), 0) + 1 INTO seq
  FROM stock_transfers WHERE transfer_number LIKE 'OUT-' || year_month || '-%';
  NEW.transfer_number := 'OUT-' || year_month || '-' || lpad(seq::text, 4, '0');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'auto_transfer_number') THEN
    CREATE TRIGGER auto_transfer_number
      BEFORE INSERT ON stock_transfers
      FOR EACH ROW WHEN (NEW.transfer_number IS NULL OR NEW.transfer_number = '')
      EXECUTE FUNCTION generate_transfer_number();
  END IF;
END $$;

-- Stock turun saat transfer_item diinsert
CREATE OR REPLACE FUNCTION decrease_stock_on_transfer()
RETURNS TRIGGER AS $$
DECLARE current_stock integer;
BEGIN
  SELECT stock_quantity INTO current_stock FROM products WHERE id = NEW.product_id;
  IF current_stock < NEW.quantity THEN
    RAISE EXCEPTION 'Stok produk "%" tidak cukup. Tersedia: %, diminta: %',
      NEW.product_name, current_stock, NEW.quantity;
  END IF;
  UPDATE products SET stock_quantity = stock_quantity - NEW.quantity WHERE id = NEW.product_id;
  INSERT INTO stock_movements (product_id, product_name, type, quantity, quantity_before, quantity_after, reference_type, reference_id, notes)
  VALUES (NEW.product_id, NEW.product_name, 'out', NEW.quantity, current_stock, current_stock - NEW.quantity, 'transfer', NEW.transfer_id, NEW.notes);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'decrease_stock_transfer_trigger') THEN
    CREATE TRIGGER decrease_stock_transfer_trigger
      AFTER INSERT ON stock_transfer_items
      FOR EACH ROW EXECUTE FUNCTION decrease_stock_on_transfer();
  END IF;
END $$;

-- Stock naik kembali saat transfer dibatalkan
CREATE OR REPLACE FUNCTION restore_stock_on_transfer_cancel()
RETURNS TRIGGER AS $$
DECLARE item RECORD; current_stock integer;
BEGIN
  IF NEW.status = 'cancelled' AND OLD.status != 'cancelled' THEN
    FOR item IN SELECT * FROM stock_transfer_items WHERE transfer_id = NEW.id LOOP
      SELECT stock_quantity INTO current_stock FROM products WHERE id = item.product_id;
      UPDATE products SET stock_quantity = stock_quantity + item.quantity WHERE id = item.product_id;
      INSERT INTO stock_movements (product_id, product_name, type, quantity, quantity_before, quantity_after, reference_type, reference_id)
      VALUES (item.product_id, item.product_name, 'in', item.quantity, current_stock, current_stock + item.quantity, 'transfer_cancel', NEW.id);
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'restore_stock_transfer_cancel_trigger') THEN
    CREATE TRIGGER restore_stock_transfer_cancel_trigger
      AFTER UPDATE ON stock_transfers
      FOR EACH ROW EXECUTE FUNCTION restore_stock_on_transfer_cancel();
  END IF;
END $$;

ALTER TABLE stock_transfers DISABLE ROW LEVEL SECURITY;
ALTER TABLE stock_transfer_items DISABLE ROW LEVEL SECURITY;

-- ============================================================
-- SELESAI — Jalankan migration ini lalu refresh aplikasi
-- ============================================================
