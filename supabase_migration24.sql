-- Migration 24: Bikin pengurangan stok saat insert stock_transfer_item jadi atomik
-- Trigger decrease_stock_on_transfer() sama seperti decrease_stock_on_invoice_item()
-- sebelum migration23 — SELECT stock_quantity dulu, baru UPDATE terpisah. Kalau ada
-- 2 transfer keluar barang untuk produk yang sama di-insert nyaris bersamaan, dua-duanya
-- bisa baca stok yang sama sebelum salah satu UPDATE selesai, dua-duanya lolos
-- pengecekan "stok cukup", padahal totalnya melebihi stok yang ada → oversell/minus.
-- Sekarang cek + kurangi digabung jadi SATU statement UPDATE...WHERE...RETURNING.
-- Jalankan di Supabase SQL Editor

CREATE OR REPLACE FUNCTION decrease_stock_on_transfer()
RETURNS TRIGGER AS $$
DECLARE
  before_stock integer;
  after_stock  integer;
BEGIN
  SELECT stock_quantity INTO before_stock FROM products WHERE id = NEW.product_id;

  UPDATE products
  SET stock_quantity = stock_quantity - NEW.quantity
  WHERE id = NEW.product_id AND stock_quantity >= NEW.quantity
  RETURNING stock_quantity INTO after_stock;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Stok produk "%" tidak cukup. Tersedia: %, diminta: %',
      NEW.product_name, before_stock, NEW.quantity;
  END IF;

  INSERT INTO stock_movements (product_id, product_name, type, quantity, quantity_before, quantity_after, reference_type, reference_id, notes)
  VALUES (NEW.product_id, NEW.product_name, 'out', NEW.quantity, after_stock + NEW.quantity, after_stock, 'transfer', NEW.transfer_id, NEW.notes);

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
