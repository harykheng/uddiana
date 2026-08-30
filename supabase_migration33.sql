-- ============================================================
-- Migration 33: Perbaiki tiga trigger pengembalian stok (temuan F-05 & F-11)
-- Jalankan di Supabase SQL Editor
-- ============================================================
-- Migration 23, 24 & 25 sudah membuat tiga fungsi PENGURANGAN/PENAMBAHAN stok jadi
-- satu perintah UPDATE...RETURNING yang tidak bisa disela. Tiga fungsi PENGEMBALIAN
-- stok (dipakai saat membatalkan faktur / PO / keluar barang) tidak pernah ikut
-- diperbaiki dan masih memakai pola lama: SELECT dulu, UPDATE belakangan.
--
-- Dua masalah yang ditutup di sini:
--
-- 1. (F-05, paling berbahaya) restore_stock_on_purchase_cancel memakai
--    GREATEST(0, stok - qty). Kalau barang dari PO itu sudah terjual, stok DIPAKSA
--    ke nol dan selisihnya hilang tanpa bisa dilacak. Migration 21 cuma menambahkan
--    catatan peringatan di kolom notes, tidak mencegahnya. Padahal tombol Hapus PO
--    untuk kondisi yang sama justru MENOLAK dengan pesan jelas — dua tombol
--    bersebelahan, perilakunya berlawanan. Sekarang pembatalan ikut menolak.
--
-- 2. (F-11) quantity_before/quantity_after dibaca lewat SELECT terpisah sebelum
--    UPDATE, jadi angka yang tercatat bisa meleset kalau ada transaksi lain untuk
--    produk yang sama berjalan nyaris bersamaan. Sekarang diturunkan dari hasil
--    UPDATE...RETURNING supaya selalu sesuai urutan yang benar-benar terjadi.
--
-- Catatan: RAISE EXCEPTION membatalkan SELURUH transaksi, jadi tidak ada kondisi
-- setengah jadi — kalau satu produk gagal, tidak ada produk lain yang terlanjur
-- berubah dan status PO tetap seperti semula.
-- ============================================================


-- ============================================================
-- 1. Pembatalan PEMBELIAN — menolak, bukan menolkan diam-diam
-- ============================================================
CREATE OR REPLACE FUNCTION restore_stock_on_purchase_cancel()
RETURNS TRIGGER AS $$
DECLARE
  item        RECORD;
  after_stock integer;
  avail       integer;
BEGIN
  IF NEW.status = 'cancelled' AND OLD.status != 'cancelled' THEN
    FOR item IN SELECT * FROM purchase_items WHERE purchase_id = NEW.id LOOP

      -- Cek + kurangi dalam SATU perintah: row lock Postgres menjamin tidak ada dua
      -- transaksi yang sama-sama lolos pengecekan "stok cukup".
      UPDATE products
      SET stock_quantity = stock_quantity - item.quantity
      WHERE id = item.product_id AND stock_quantity >= item.quantity
      RETURNING stock_quantity INTO after_stock;

      IF NOT FOUND THEN
        SELECT stock_quantity INTO avail FROM products WHERE id = item.product_id;
        IF avail IS NULL THEN
          RAISE EXCEPTION 'Tidak bisa batalkan PO: produk "%" sudah tidak ada di daftar produk.',
            item.product_name;
        ELSE
          RAISE EXCEPTION 'Tidak bisa batalkan PO: stok "%" tidak cukup untuk dikembalikan (PO ini menambah %, stok sekarang cuma %). Barang kemungkinan sudah terjual atau keluar. Sesuaikan stok manual dulu lewat halaman Produk.',
            item.product_name, item.quantity, avail;
        END IF;
      END IF;

      INSERT INTO stock_movements
        (product_id, product_name, type, quantity, quantity_before, quantity_after, reference_type, reference_id)
      VALUES
        (item.product_id, item.product_name, 'out', item.quantity,
         after_stock + item.quantity, after_stock, 'purchase_cancel', NEW.id);

    END LOOP;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- ============================================================
-- 2. Pembatalan FAKTUR — angka riwayat jadi akurat
-- ============================================================
-- Menambah stok selalu aman (tidak butuh ambang batas), jadi di sini yang diperbaiki
-- murni akurasi quantity_before/after. Ditambah penjagaan kalau produknya sudah dihapus.
CREATE OR REPLACE FUNCTION restore_stock_on_cancel()
RETURNS TRIGGER AS $$
DECLARE
  item        RECORD;
  after_stock integer;
BEGIN
  IF NEW.status = 'cancelled' AND OLD.status != 'cancelled' THEN
    FOR item IN SELECT * FROM invoice_items WHERE invoice_id = NEW.id LOOP

      UPDATE products
      SET stock_quantity = stock_quantity + item.quantity
      WHERE id = item.product_id
      RETURNING stock_quantity INTO after_stock;

      IF FOUND THEN
        INSERT INTO stock_movements
          (product_id, product_name, type, quantity, quantity_before, quantity_after, reference_type, reference_id)
        VALUES
          (item.product_id, item.product_name, 'in', item.quantity,
           after_stock - item.quantity, after_stock, 'invoice_cancel', NEW.id);
      END IF;

    END LOOP;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- ============================================================
-- 3. Pembatalan KELUAR BARANG — angka riwayat jadi akurat
-- ============================================================
CREATE OR REPLACE FUNCTION restore_stock_on_transfer_cancel()
RETURNS TRIGGER AS $$
DECLARE
  item        RECORD;
  after_stock integer;
BEGIN
  IF NEW.status = 'cancelled' AND OLD.status != 'cancelled' THEN
    FOR item IN SELECT * FROM stock_transfer_items WHERE transfer_id = NEW.id LOOP

      UPDATE products
      SET stock_quantity = stock_quantity + item.quantity
      WHERE id = item.product_id
      RETURNING stock_quantity INTO after_stock;

      IF FOUND THEN
        INSERT INTO stock_movements
          (product_id, product_name, type, quantity, quantity_before, quantity_after, reference_type, reference_id)
        VALUES
          (item.product_id, item.product_name, 'in', item.quantity,
           after_stock - item.quantity, after_stock, 'transfer_cancel', NEW.id);
      END IF;

    END LOOP;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- ============================================================
-- VERIFIKASI — pastikan ketiga fungsi sudah versi baru
-- ============================================================
-- Ketiganya harus mengandung 'RETURNING stock_quantity', dan yang purchase_cancel
-- harus mengandung 'RAISE EXCEPTION' serta TIDAK lagi mengandung 'GREATEST'.
SELECT
  p.proname AS fungsi,
  pg_get_functiondef(p.oid) LIKE '%RETURNING stock_quantity%' AS sudah_atomik,
  pg_get_functiondef(p.oid) LIKE '%RAISE EXCEPTION%'          AS bisa_menolak,
  pg_get_functiondef(p.oid) LIKE '%GREATEST%'                 AS masih_menolkan_diam_diam
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('restore_stock_on_purchase_cancel',
                    'restore_stock_on_cancel',
                    'restore_stock_on_transfer_cancel')
ORDER BY p.proname;
