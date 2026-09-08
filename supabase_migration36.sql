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
-- edit_purchase() (migration34) nggak perlu ditulis ulang: klausa SET pada
-- ALTER FUNCTION otomatis mengisi GUC ini selama fungsi berjalan dan
-- mengembalikannya begitu selesai. increase_stock_on_purchase() di atas
-- sengaja nggak menimpa nilai yang sudah terisi, jadi item hasil edit tercatat
-- sebagai 'purchase_edit' — inilah perubahan harga modal yang paling sering
-- terjadi tanpa disadari.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'edit_purchase'
  ) THEN
    EXECUTE 'ALTER FUNCTION edit_purchase(uuid, text, date, text, numeric, jsonb) '
         || 'SET app.cost_source = ''purchase_edit''';
  ELSE
    RAISE NOTICE 'edit_purchase() belum ada — jalankan supabase_migration34.sql dulu, lalu ulangi bagian ini.';
  END IF;
END $$;


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
       (SELECT (array_to_string(p.proconfig, ',') LIKE '%purchase_edit%')::text
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = 'edit_purchase')
UNION ALL
SELECT 'baris awal vs jumlah produk',
       (SELECT count(*) FROM product_cost_logs)::text || ' / ' || (SELECT count(*) FROM products)::text;
