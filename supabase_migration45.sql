-- ============================================================
-- Migration 45: Nilai barang di Keluar Barang (stock-out.html)
-- ============================================================
-- Tiap baris stock_transfer_items menyimpan harga modal produk SAAT barang
-- keluar (cost_price). Nilai = quantity × cost_price. Disimpan, bukan dihitung
-- dari products.cost sekarang, supaya nilai keluar barang lama tidak ikut
-- berubah kalau harga modal naik/turun belakangan.
--
--   1. Kolom stock_transfer_items.cost_price
--   2. Trigger BEFORE INSERT: isi cost_price dari products.cost (browser tidak
--      perlu tahu harga modal — admin biasa memang tidak melihatnya)
--   3. Backfill baris lama: harga modal pada tanggal keluar dari
--      product_cost_logs (migration36) kalau ada, kalau tidak pakai harga modal
--      produk saat ini (perkiraan)
--
-- Aman dijalankan ulang.
-- ============================================================

ALTER TABLE stock_transfer_items ADD COLUMN IF NOT EXISTS cost_price decimal(15,2);

CREATE OR REPLACE FUNCTION fill_transfer_item_cost()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.cost_price IS NULL THEN
    SELECT COALESCE(cost, 0) INTO NEW.cost_price FROM products WHERE id = NEW.product_id;
    NEW.cost_price := COALESCE(NEW.cost_price, 0);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS fill_transfer_item_cost_trigger ON stock_transfer_items;
CREATE TRIGGER fill_transfer_item_cost_trigger
  BEFORE INSERT ON stock_transfer_items
  FOR EACH ROW EXECUTE FUNCTION fill_transfer_item_cost();

-- Backfill
DO $$
BEGIN
  IF to_regclass('public.product_cost_logs') IS NOT NULL THEN
    -- Harga modal pada saat keluar:
    --   * perubahan terakhir SEBELUM transfer → new_cost-nya
    --   * kalau tidak ada (transfer lebih tua dari log), perubahan pertama
    --     SESUDAH transfer → old_cost-nya (= harga sebelum diubah)
    --   * selain itu harga modal produk sekarang
    UPDATE stock_transfer_items sti
    SET cost_price = COALESCE(
      (SELECT l.new_cost FROM product_cost_logs l
        WHERE l.product_id = sti.product_id AND l.changed_at <= st.created_at
        ORDER BY l.changed_at DESC LIMIT 1),
      (SELECT COALESCE(l.old_cost, l.new_cost) FROM product_cost_logs l
        WHERE l.product_id = sti.product_id AND l.changed_at > st.created_at
        ORDER BY l.changed_at ASC LIMIT 1),
      (SELECT p.cost FROM products p WHERE p.id = sti.product_id),
      0)
    FROM stock_transfers st
    WHERE st.id = sti.transfer_id AND sti.cost_price IS NULL;
  END IF;

  UPDATE stock_transfer_items sti
  SET cost_price = COALESCE((SELECT p.cost FROM products p WHERE p.id = sti.product_id), 0)
  WHERE sti.cost_price IS NULL;
END $$;
