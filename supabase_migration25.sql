-- Migration 25: Perbaiki akurasi catatan quantity_before/after di increase_stock_on_purchase
-- Bukan bug oversell (nambah stok selalu aman, nggak butuh pengecekan ambang batas),
-- tapi catatan "stok sebelum" di stock_movements bisa sedikit meleset kalau ada 2
-- pembelian untuk produk yang sama di-insert nyaris bersamaan (SELECT dibaca sebelum
-- UPDATE lain yang beriringan selesai). Sekarang pakai UPDATE...RETURNING supaya angka
-- yang dicatat selalu akurat sesuai urutan transaksi yang benar-benar terjadi.
-- Jalankan di Supabase SQL Editor

CREATE OR REPLACE FUNCTION increase_stock_on_purchase()
RETURNS TRIGGER AS $$
DECLARE
  after_stock integer;
BEGIN
  UPDATE products
  SET stock_quantity = stock_quantity + NEW.quantity, cost = NEW.cost_price
  WHERE id = NEW.product_id
  RETURNING stock_quantity INTO after_stock;

  INSERT INTO stock_movements (product_id, product_name, type, quantity, quantity_before, quantity_after, reference_type, reference_id)
  VALUES (NEW.product_id, NEW.product_name, 'in', NEW.quantity, after_stock - NEW.quantity, after_stock, 'purchase', NEW.purchase_id);

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
