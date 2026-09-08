-- ============================================================
-- Migration 36: Log perubahan harga modal (products.cost)
-- Jalankan di Supabase SQL Editor
-- ============================================================
-- Sebelumnya harga modal cuma disimpan sebagai satu angka "kondisi sekarang".
-- Kalau ditanya "produk ini harga modalnya sudah sempat naik belum?" atau
-- "ini pernah diubah orang nggak?", nggak ada jawabannya — angka lama hilang
-- begitu ketimpa.
--
-- Sekarang tiap perubahan products.cost dicatat ke product_cost_logs, lewat
-- TRIGGER di tabel products. Ditaruh di database (bukan di kode halaman) supaya
-- SEMUA jalur perubahan ikut tercatat tanpa kecuali:
--   - insert purchase_items (trigger increase_stock_on_purchase)
--   - edit_purchase() (migration34)
--   - Edit produk / Update Harga Massal / Import CSV di products.html
--   - UPDATE manual dari Supabase SQL Editor
-- ============================================================


-- ============================================================
-- 1. Tabel log
-- ============================================================
CREATE TABLE IF NOT EXISTS product_cost_logs (
  id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
  product_id uuid REFERENCES products(id) ON DELETE CASCADE,
  product_name text,
  old_cost decimal(15,2),          -- NULL = baris awal (produk baru dibuat / backfill)
  new_cost decimal(15,2) NOT NULL,
  -- 'create' | 'purchase' | 'purchase_edit' | 'manual' | 'awal' (backfill)
  source text NOT NULL DEFAULT 'manual',
  reference_id uuid,               -- purchase_id kalau source-nya pembelian
  changed_by uuid,                 -- auth.uid(), NULL kalau diubah dari SQL Editor
  changed_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_product_cost_logs_product
  ON product_cost_logs (product_id, changed_at DESC);

ALTER TABLE product_cost_logs DISABLE ROW LEVEL SECURITY;


-- ============================================================
-- 2. Trigger pencatat
-- ============================================================
-- Sumber perubahan dibaca dari GUC transaction-local 'app.cost_source' yang
-- di-set oleh fungsi pembelian di bawah. Perubahan dari browser/SQL Editor
-- nggak nge-set apa-apa, jadi jatuh ke default 'manual'.
CREATE OR REPLACE FUNCTION log_product_cost_change()
RETURNS TRIGGER AS $$
DECLARE
  v_source text;
  v_ref    uuid;
  v_user   uuid;
  v_old    decimal(15,2);
BEGIN
  -- OLD sengaja cuma disentuh di cabang UPDATE: pada trigger INSERT record OLD
  -- belum ter-assign, dan ekspresi SQL di plpgsql nggak dijamin short-circuit.
  IF TG_OP = 'UPDATE' THEN
    IF NEW.cost IS NOT DISTINCT FROM OLD.cost THEN
      RETURN NEW;
    END IF;
    v_old := OLD.cost;
  ELSE
    v_old := NULL;
  END IF;

  v_source := nullif(current_setting('app.cost_source', true), '');
  IF v_source IS NULL THEN
    IF TG_OP = 'INSERT' THEN v_source := 'create'; ELSE v_source := 'manual'; END IF;
  END IF;

  BEGIN
    v_ref := nullif(current_setting('app.cost_ref', true), '')::uuid;
  EXCEPTION WHEN others THEN
    v_ref := NULL;
  END;

  -- auth.uid() cuma ada kalau dipanggil lewat PostgREST dengan JWT.
  -- Dari SQL Editor / job internal hasilnya NULL, dan itu bukan error.
  BEGIN
    v_user := auth.uid();
  EXCEPTION WHEN others THEN
    v_user := NULL;
  END;

  INSERT INTO product_cost_logs
    (product_id, product_name, old_cost, new_cost, source, reference_id, changed_by)
  VALUES
    (NEW.id, NEW.name, v_old, NEW.cost, v_source, v_ref, v_user);

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_log_product_cost_change ON products;
CREATE TRIGGER trg_log_product_cost_change
  AFTER INSERT OR UPDATE OF cost ON products
  FOR EACH ROW EXECUTE FUNCTION log_product_cost_change();


-- ============================================================
-- 3. Tandai perubahan yang datang dari pembelian
-- ============================================================
-- Sama persis dengan versi migration34, cuma ditambah set_config() supaya
-- trigger di atas tahu perubahan ini berasal dari PO, bukan diketik admin.
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

  -- 'true' = transaction-local, otomatis hilang begitu transaksi selesai.
  -- Kalau edit_purchase() sudah mengisinya duluan ('purchase_edit'), jangan ditimpa.
  IF nullif(current_setting('app.cost_source', true), '') IS NULL THEN
    PERFORM set_config('app.cost_source', 'purchase', true);
  END IF;
  PERFORM set_config('app.cost_ref', NEW.purchase_id::text, true);

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
-- 3b. Tandai perubahan yang datang dari EDIT pembelian
-- ============================================================
-- edit_purchase() (migration34) ditulis ulang di sini dengan tambahan satu baris
-- set_config() di awal fungsi. Sisanya identik dengan migration34.
--
-- Catatan: cara yang lebih ringkas (ALTER FUNCTION ... SET app.cost_source)
-- TIDAK dipakai karena parameter custom yang belum terdaftar cuma boleh
-- disimpan permanen oleh superuser — role postgres di Supabase bukan superuser,
-- jadi hasilnya "permission denied to set parameter". set_config() saat fungsi
-- berjalan tidak kena batasan itu (increase_stock_on_purchase juga memakainya).
--
-- Kalau migration34 BELUM pernah dijalankan, blok ini yang membuat fungsinya —
-- tapi tetap jalankan migration34 juga supaya bagian lainnya ikut terpasang.
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
  -- Tandai sumber perubahan harga modal untuk trigger log_product_cost_change
  -- (migration36). 'true' = transaction-local, hilang sendiri begitu selesai.
  -- increase_stock_on_purchase() sengaja tidak menimpa nilai yang sudah terisi,
  -- jadi item hasil edit tercatat 'purchase_edit', bukan 'purchase'.
  PERFORM set_config('app.cost_source', 'purchase_edit', true);

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
-- 4. Backfill: satu baris awal per produk
-- ============================================================
-- Tanpa ini produk lama kelihatan "belum pernah punya harga modal" di riwayat.
-- Baris ini cuma titik awal (bukan bukti perubahan), makanya source-nya 'awal'.
INSERT INTO product_cost_logs (product_id, product_name, old_cost, new_cost, source, changed_at)
SELECT p.id, p.name, NULL, p.cost, 'awal', coalesce(p.created_at, now())
FROM products p
WHERE NOT EXISTS (SELECT 1 FROM product_cost_logs l WHERE l.product_id = p.id);


-- ============================================================
-- VERIFIKASI
-- ============================================================
-- Baris 1: trigger terpasang di tabel products.
-- Baris 2: increase_stock_on_purchase sudah menandai sumbernya.
-- Baris 3: edit_purchase sudah dapat label 'purchase_edit'.
-- Baris 4: jumlah baris awal hasil backfill (harus = jumlah produk).
SELECT 'trigger log terpasang' AS cek,
       EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_log_product_cost_change')::text AS hasil
UNION ALL
SELECT 'pembelian menandai sumber',
       (SELECT (pg_get_functiondef(p.oid) LIKE '%app.cost_source%')::text
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = 'increase_stock_on_purchase')
UNION ALL
SELECT 'edit PO menandai sumber',
       (SELECT (pg_get_functiondef(p.oid) LIKE '%purchase_edit%')::text
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = 'edit_purchase')
UNION ALL
SELECT 'baris awal vs jumlah produk',
       (SELECT count(*) FROM product_cost_logs)::text || ' / ' || (SELECT count(*) FROM products)::text;
