-- ============================================================
-- Migration 34: Edit pembelian jadi satu transaksi + harga modal tidak
--               ketimpa PO lama
-- Jalankan di Supabase SQL Editor
-- ============================================================
-- Dua masalah pada alur EDIT PEMBELIAN (purchases.html):
--
-- 1. TIDAK ATOMIK. saveEditPurchase() menjalankan 4 langkah sebagai panggilan
--    terpisah dari browser: lepas stok item lama → hapus purchase_items →
--    insert item baru → update header PO. Kalau koneksi putus setelah langkah 2,
--    stok sudah telanjur berkurang DAN item PO sudah hilang: PO jadi kosong dan
--    stoknya minus sebanyak isi PO itu, tanpa cara otomatis mengembalikannya.
--    Selain itu pelepasan stoknya memakai angka absolut hasil SELECT beberapa
--    saat sebelumnya, jadi penjualan yang terjadi di sela SELECT dan UPDATE
--    ikut tertimpa dan hilang.
--
--    Sekarang seluruh rangkaian dipindah ke fungsi edit_purchase() di bawah.
--    Fungsi plpgsql berjalan dalam satu transaksi — RAISE EXCEPTION atau
--    kegagalan apa pun membatalkan semuanya, tidak ada kondisi setengah jadi.
--    Pelepasan stok juga jadi satu perintah "cek + kurangi" (pola yang sama
--    dengan migration 23/24/33), bukan lagi baca-lalu-timpa.
--
-- 2. HARGA MODAL KETIMPA PO LAMA. increase_stock_on_purchase() menjalankan
--    SET cost = NEW.cost_price tanpa syarat. Jadi begitu PO lama diedit,
--    products.cost mundur ke harga PO itu — padahal mungkin sudah ada PO yang
--    lebih baru dengan harga berbeda. Laba rugi ikut meleset tanpa jejak.
--    Sekarang cost hanya ditulis kalau PO yang bersangkutan memang pembelian
--    TERBARU untuk produk itu.
--
-- Catatan: edit_purchase() juga membawa serta batch_number & expired_date milik
-- baris yang produknya tidak berubah. Form edit PO tidak punya input untuk kedua
-- kolom itu, jadi tanpa ini setiap edit menghapusnya diam-diam.
-- ============================================================


-- ============================================================
-- 1. Harga modal cuma boleh ditulis oleh pembelian TERBARU
-- ============================================================
CREATE OR REPLACE FUNCTION increase_stock_on_purchase()
RETURNS TRIGGER AS $$
DECLARE
  after_stock  integer;
  this_date    date;
  this_created timestamptz;
  newer_exists boolean;
BEGIN
  SELECT purchase_date, created_at INTO this_date, this_created
  FROM purchases WHERE id = NEW.purchase_id;

  -- Adakah pembelian LAIN untuk produk ini yang lebih baru dari PO ini?
  -- Tanggal sama → dibandingkan lewat created_at supaya urutannya tetap pasti.
  SELECT EXISTS (
    SELECT 1
    FROM purchase_items pi
    JOIN purchases p ON p.id = pi.purchase_id
    WHERE pi.product_id  = NEW.product_id
      AND pi.purchase_id <> NEW.purchase_id
      AND p.status <> 'cancelled'
      AND (p.purchase_date > this_date
           OR (p.purchase_date = this_date AND p.created_at > this_created))
  ) INTO newer_exists;

  IF newer_exists THEN
    -- PO ini bukan yang terbaru: stok tetap bertambah, harga modal JANGAN disentuh.
    UPDATE products
    SET stock_quantity = stock_quantity + NEW.quantity
    WHERE id = NEW.product_id
    RETURNING stock_quantity INTO after_stock;
  ELSE
    UPDATE products
    SET stock_quantity = stock_quantity + NEW.quantity, cost = NEW.cost_price
    WHERE id = NEW.product_id
    RETURNING stock_quantity INTO after_stock;
  END IF;

  INSERT INTO stock_movements
    (product_id, product_name, type, quantity, quantity_before, quantity_after, reference_type, reference_id)
  VALUES
    (NEW.product_id, NEW.product_name, 'in', NEW.quantity,
     after_stock - NEW.quantity, after_stock, 'purchase', NEW.purchase_id);

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- ============================================================
-- 2. Edit pembelian dalam SATU transaksi
-- ============================================================
-- p_items: array JSON, tiap elemen
--   { item_id, product_id, product_name, quantity, cost_price, subtotal }
--   item_id = id purchase_items lama (untuk baris yang sudah ada), null untuk baris baru.
CREATE OR REPLACE FUNCTION edit_purchase(
  p_purchase_id uuid,
  p_supplier    text,
  p_date        date,
  p_notes       text,
  p_total       numeric,
  p_items       jsonb
) RETURNS void AS $$
DECLARE
  rel         RECORD;
  it          jsonb;
  after_stock integer;
  avail       integer;
  prod_name   text;
  v_old       jsonb;
  v_key       text;
  v_batch     varchar(100);
  v_expired   date;
BEGIN
  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Pembelian harus berisi minimal 1 barang.';
  END IF;

  PERFORM 1 FROM purchases WHERE id = p_purchase_id AND status <> 'cancelled';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PO tidak ditemukan atau sudah dibatalkan, jadi tidak bisa diedit.';
  END IF;

  -- Simpan batch & expired item lama SEBELUM dihapus, dikunci per id item.
  SELECT COALESCE(jsonb_object_agg(id::text, jsonb_build_object(
           'product_id', product_id, 'batch_number', batch_number, 'expired_date', expired_date)), '{}'::jsonb)
  INTO v_old
  FROM purchase_items WHERE purchase_id = p_purchase_id;

  -- ── Lepas stok item lama, digabung per produk ──
  -- Cek + kurangi dalam SATU perintah: row lock Postgres menutup celah antara
  -- pengecekan "stok cukup" dan penulisannya.
  FOR rel IN
    SELECT product_id, SUM(quantity)::integer AS qty
    FROM purchase_items WHERE purchase_id = p_purchase_id GROUP BY product_id
  LOOP
    SELECT name INTO prod_name FROM products WHERE id = rel.product_id;

    UPDATE products
    SET stock_quantity = stock_quantity - rel.qty
    WHERE id = rel.product_id AND stock_quantity >= rel.qty
    RETURNING stock_quantity INTO after_stock;

    IF NOT FOUND THEN
      SELECT stock_quantity INTO avail FROM products WHERE id = rel.product_id;
      IF prod_name IS NULL THEN
        RAISE EXCEPTION 'Tidak bisa edit: produk salah satu item sudah tidak ada di daftar produk.';
      END IF;
      RAISE EXCEPTION 'Tidak bisa edit — stok "%" sudah terpakai (PO ini menambah %, stok sekarang cuma %). Barang kemungkinan sudah terjual. Sesuaikan stok manual dulu lewat halaman Produk.',
        prod_name, rel.qty, COALESCE(avail, 0);
    END IF;

    INSERT INTO stock_movements
      (product_id, product_name, type, quantity, quantity_before, quantity_after, reference_type, reference_id, notes)
    VALUES
      (rel.product_id, prod_name, 'adjustment', rel.qty,
       after_stock + rel.qty, after_stock, 'purchase_edit', p_purchase_id,
       'Edit pembelian: lepas stok item lama');
  END LOOP;

  DELETE FROM purchase_items WHERE purchase_id = p_purchase_id;

  -- ── Pasang item baru — trigger increase_stock_on_purchase yang menambah
  --    stok kembali sekaligus mencatat pergerakan 'in' ──
  FOR it IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    IF (it->>'quantity')::integer <= 0 THEN
      RAISE EXCEPTION 'Jumlah barang harus lebih dari 0.';
    END IF;

    -- Bawa serta batch & expired kalau baris ini masih item lama yang produknya tidak diganti
    v_batch := NULL; v_expired := NULL;
    v_key := it->>'item_id';
    IF v_key IS NOT NULL AND v_old ? v_key
       AND (v_old->v_key->>'product_id') = (it->>'product_id') THEN
      v_batch   := v_old->v_key->>'batch_number';
      v_expired := (v_old->v_key->>'expired_date')::date;
    END IF;

    INSERT INTO purchase_items
      (purchase_id, product_id, product_name, quantity, cost_price, subtotal, batch_number, expired_date)
    VALUES
      (p_purchase_id, (it->>'product_id')::uuid, it->>'product_name',
       (it->>'quantity')::integer, (it->>'cost_price')::numeric, (it->>'subtotal')::numeric,
       v_batch, v_expired);
  END LOOP;

  UPDATE purchases
  SET supplier_name = p_supplier,
      purchase_date = p_date,
      notes         = p_notes,
      total_cost    = p_total,
      updated_at    = now()
  WHERE id = p_purchase_id;
END;
$$ LANGUAGE plpgsql;


-- ============================================================
-- VERIFIKASI
-- ============================================================
-- Baris 1 harus: edit_purchase ada.
-- Baris 2 harus: increase_stock_on_purchase mengandung 'newer_exists'.
SELECT 'edit_purchase ada' AS cek,
       EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
               WHERE n.nspname = 'public' AND p.proname = 'edit_purchase') AS hasil
UNION ALL
SELECT 'harga modal dijaga PO terbaru',
       (SELECT pg_get_functiondef(p.oid) LIKE '%newer_exists%'
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = 'increase_stock_on_purchase');
