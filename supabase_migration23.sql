-- Migration 23: Bikin pengurangan stok saat insert invoice_item jadi atomik
-- Sebelumnya trigger decrease_stock_on_invoice_item() SELECT stock_quantity dulu,
-- baru UPDATE terpisah. Kalau ada 2 faktur untuk produk yang sama di-insert nyaris
-- bersamaan (dalam hitungan milidetik — misal 2 sales submit faktur bareng), dua-duanya
-- bisa baca stok yang sama SEBELUM salah satu UPDATE selesai, dua-duanya lolos
-- pengecekan "stok cukup", padahal totalnya melebihi stok yang ada → oversell/minus.
-- Sekarang cek + kurangi digabung jadi SATU statement UPDATE...WHERE...RETURNING,
-- supaya row lock Postgres menjamin tidak ada dua transaksi yang bisa lolos bersamaan.
-- Jalankan di Supabase SQL Editor

CREATE OR REPLACE FUNCTION decrease_stock_on_invoice_item()
RETURNS TRIGGER AS $$
DECLARE
  prod_name text;
  before_stock integer;
  after_stock integer;
BEGIN
  SELECT name, stock_quantity INTO prod_name, before_stock
  FROM products WHERE id = NEW.product_id;

  UPDATE products
  SET stock_quantity = stock_quantity - NEW.quantity
  WHERE id = NEW.product_id AND stock_quantity >= NEW.quantity
  RETURNING stock_quantity INTO after_stock;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Stok produk "%" tidak cukup. Stok tersedia: %, diminta: %',
      prod_name, before_stock, NEW.quantity;
  END IF;

  INSERT INTO stock_movements
    (product_id, product_name, type, quantity, quantity_before, quantity_after, reference_type, reference_id)
  VALUES
    (NEW.product_id, NEW.product_name, 'out', NEW.quantity,
     after_stock + NEW.quantity, after_stock, 'invoice', NEW.invoice_id);

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
