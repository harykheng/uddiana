-- Migration 21: Catat jelas kalau pembatalan PO ketemu stok yang sudah kurang dari qty PO
-- Sebelumnya trigger restore_stock_on_purchase_cancel() diam-diam nge-nolkan stok
-- (GREATEST(0, ...)) tanpa jejak kalau stok saat ini sudah lebih kecil dari qty PO yang
-- mau dikembalikan (misal karena barangnya sudah kejual/keluar duluan). Selisihnya hilang
-- tanpa catatan, jadi kalau muncul beda pas opname, susah ditelusuri sebabnya.
-- Sekarang stock_movements dari kejadian ini dikasih notes yang jelas nyebut selisihnya.
-- Jalankan di Supabase SQL Editor

CREATE OR REPLACE FUNCTION restore_stock_on_purchase_cancel()
RETURNS TRIGGER AS $$
DECLARE
  item RECORD;
  current_stock integer;
  shortfall integer;
BEGIN
  IF NEW.status = 'cancelled' AND OLD.status != 'cancelled' THEN
    FOR item IN SELECT * FROM purchase_items WHERE purchase_id = NEW.id LOOP
      SELECT stock_quantity INTO current_stock FROM products WHERE id = item.product_id;
      shortfall := item.quantity - current_stock; -- > 0 kalau stok tidak cukup untuk dikurangi penuh

      UPDATE products SET stock_quantity = GREATEST(0, stock_quantity - item.quantity) WHERE id = item.product_id;

      INSERT INTO stock_movements (product_id, product_name, type, quantity, quantity_before, quantity_after, reference_type, reference_id, notes)
      VALUES (
        item.product_id, item.product_name, 'out', item.quantity, current_stock, GREATEST(0, current_stock - item.quantity),
        'purchase_cancel', NEW.id,
        CASE WHEN shortfall > 0
          THEN format('⚠️ Stok sudah kurang dari qty PO — seharusnya -%s tapi cuma bisa -%s (stok cuma %s, dinolkan). Selisih %s pcs perlu dicek manual.', item.quantity, current_stock, current_stock, shortfall)
          ELSE NULL
        END
      );
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
