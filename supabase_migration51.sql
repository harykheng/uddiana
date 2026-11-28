-- ============================================================
-- Migration 50: Harga modal rata-rata tertimbang (weighted average)
-- ============================================================
-- SEBELUMNYA: setiap PO masuk, products.cost DITIMPA harga beli PO itu.
--   Stok lama 31 pcs @20.138 + beli 72 pcs @16.805 → modal jadi 16.805,
--   padahal 31 pcs yang masih di rak belinya 20.138.
--
-- SEKARANG: modal = rata-rata tertimbang stok lama + barang masuk
--   (31 × 20.138 + 72 × 16.805) / 103 = 17.808,14
--
-- Aturan rumus (avg_cost_after_purchase):
--   - Stok sebelum PO ≤ 0, atau modal lama ≤ 0 (belum pernah diisi)
--     → langsung pakai harga beli PO (tidak ada yang dirata-rata)
--   - Harga beli 0 (barang bonus dari supplier) IKUT dirata-rata → modal turun.
--     Itu disengaja: barang gratis memang menurunkan modal per pcs
--   - Dibulatkan 2 desimal (tipe kolom cost)
--
-- EDIT PO & BATAL PO: kontribusi PO itu dikeluarkan dulu dari rata-rata.
--   Supaya bisa, tiap baris purchase_items sekarang mencatat modal produk
--   SEBELUM dan SESUDAH baris itu masuk (cost_before / cost_after /
--   cost_applied_at, diisi trigger). Saat edit/batal, modal dikembalikan ke
--   cost_before baris pertama PO itu — TAPI cuma kalau modal belum diubah oleh
--   hal lain sejak PO itu (lihat purchase_cost_base()). Kalau sudah ada PO lebih
--   baru atau modal diubah manual, modal TIDAK disentuh (sama seperti perilaku
--   lama untuk PO yang bukan terbaru) — admin sesuaikan manual kalau perlu.
--   PO yang dibuat sebelum migration ini belum punya catatan itu, jadi edit /
--   batal PO lama juga tidak mengubah modal.
--
-- HAPUS PO di purchases.html sekarang membatalkan PO dulu (lewat trigger di
--   bawah, jadi modal ikut dikembalikan) baru menghapus barisnya.
--
-- TIDAK DISENTUH: trigger faktur, retur, keluar barang, stock opname.
-- invoice_items.cost_price tetap snapshot saat faktur dibuat, jadi laporan
-- laba rugi faktur lama tidak berubah.
--
-- Jalankan setelah migration34 & migration36. Aman dijalankan ulang.
-- Jalankan di Supabase SQL Editor.
-- ============================================================


-- ============================================================
-- 1. Kolom catatan modal per baris PO
-- ============================================================
ALTER TABLE purchase_items ADD COLUMN IF NOT EXISTS cost_before     decimal(15,2);
ALTER TABLE purchase_items ADD COLUMN IF NOT EXISTS cost_after      decimal(15,2);
ALTER TABLE purchase_items ADD COLUMN IF NOT EXISTS cost_applied_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_purchase_items_product_applied
  ON purchase_items (product_id, cost_applied_at);


-- ============================================================
-- 2. Rumus rata-rata tertimbang
-- ============================================================
CREATE OR REPLACE FUNCTION avg_cost_after_purchase(
  p_old_stock integer,
  p_old_cost  numeric,
  p_qty       integer,
  p_price     numeric
) RETURNS numeric AS $$
DECLARE
  v_price numeric := GREATEST(COALESCE(p_price, 0), 0);
BEGIN
  IF COALESCE(p_old_stock, 0) <= 0 OR COALESCE(p_old_cost, 0) <= 0 THEN
    RETURN round(v_price, 2);
  END IF;
  IF p_old_stock + p_qty <= 0 THEN
    RETURN round(v_price, 2);
  END IF;
  RETURN round((p_old_stock * p_old_cost + p_qty * v_price) / (p_old_stock + p_qty), 2);
END;
$$ LANGUAGE plpgsql IMMUTABLE;


-- ============================================================
-- 3. Modal sebelum PO ini masuk — atau NULL kalau tidak bisa dipastikan
-- ============================================================
-- Dipakai Edit PO & Batal PO. Mengembalikan cost_before baris pertama PO ini
-- untuk produk tsb, HANYA kalau sejak PO ini diterapkan:
--   - tidak ada baris PO lain (yang tidak batal) yang menerapkan modal setelahnya
--   - modal produk sekarang masih sama dengan hasil baris terakhir PO ini
--     (kalau beda = sudah diubah manual / import / update massal)
-- Selain itu NULL = jangan ubah modal.
CREATE OR REPLACE FUNCTION purchase_cost_base(p_purchase_id uuid, p_product_id uuid)
RETURNS numeric AS $$
DECLARE
  v_first_before numeric;
  v_last_after   numeric;
  v_last_at      timestamptz;
  v_cur          numeric;
BEGIN
  IF p_product_id IS NULL THEN RETURN NULL; END IF;

  -- Ada baris PO ini (produk tsb) yang tidak tercatat → tidak bisa dipastikan
  IF EXISTS (
    SELECT 1 FROM purchase_items
    WHERE purchase_id = p_purchase_id AND product_id = p_product_id
      AND cost_applied_at IS NULL
  ) THEN
    RETURN NULL;
  END IF;

  SELECT cost_before INTO v_first_before
  FROM purchase_items
  WHERE purchase_id = p_purchase_id AND product_id = p_product_id
  ORDER BY cost_applied_at ASC LIMIT 1;
  IF NOT FOUND THEN RETURN NULL; END IF;

  SELECT cost_after, cost_applied_at INTO v_last_after, v_last_at
  FROM purchase_items
  WHERE purchase_id = p_purchase_id AND product_id = p_product_id
  ORDER BY cost_applied_at DESC LIMIT 1;

  IF EXISTS (
    SELECT 1
    FROM purchase_items pi
    JOIN purchases p ON p.id = pi.purchase_id
    WHERE pi.product_id = p_product_id
      AND pi.purchase_id <> p_purchase_id
      AND p.status <> 'cancelled'
      AND pi.cost_applied_at > v_last_at
  ) THEN
    RETURN NULL;
  END IF;

  SELECT cost INTO v_cur FROM products WHERE id = p_product_id;
  IF v_cur IS DISTINCT FROM v_last_after THEN
    RETURN NULL;
  END IF;

  RETURN COALESCE(v_first_before, 0);
END;
$$ LANGUAGE plpgsql STABLE;


-- ============================================================
-- 4. Trigger barang masuk: rata-rata tertimbang
-- ============================================================
-- GUC transaction-local yang diisi edit_purchase() per produk
-- (nama: app.avg_base_<uuid tanpa tanda minus> / app.avg_skip_<...>):
--   avg_base_* = modal dasar pengganti products.cost (kontribusi PO lama sudah
--                dikeluarkan). Dipakai baris PERTAMA produk itu saja, lalu dikosongkan
--   avg_skip_* = '1' → stok saja, modal jangan disentuh
CREATE OR REPLACE FUNCTION increase_stock_on_purchase()
RETURNS TRIGGER AS $$
DECLARE
  after_stock integer;
  v_key       text;
  v_stock     integer;
  v_cost      numeric;
  v_base      text;
  v_new       numeric;
BEGIN
  -- 'true' = transaction-local. Kalau edit_purchase() sudah mengisinya
  -- duluan ('purchase_edit'), jangan ditimpa.
  IF nullif(current_setting('app.cost_source', true), '') IS NULL THEN
    PERFORM set_config('app.cost_source', 'purchase', true);
  END IF;
  PERFORM set_config('app.cost_ref', NEW.purchase_id::text, true);

  v_key := replace(COALESCE(NEW.product_id::text, ''), '-', '');

  SELECT stock_quantity, cost INTO v_stock, v_cost
  FROM products WHERE id = NEW.product_id
  FOR UPDATE;

  IF NOT FOUND OR current_setting('app.avg_skip_' || v_key, true) = '1' THEN
    UPDATE products
    SET stock_quantity = stock_quantity + NEW.quantity
    WHERE id = NEW.product_id
    RETURNING stock_quantity INTO after_stock;
  ELSE
    v_base := nullif(current_setting('app.avg_base_' || v_key, true), '');
    IF v_base IS NOT NULL THEN
      v_cost := v_base::numeric;
      PERFORM set_config('app.avg_base_' || v_key, '', true);
    END IF;
    v_cost := COALESCE(v_cost, 0);

    v_new := avg_cost_after_purchase(v_stock, v_cost, NEW.quantity, NEW.cost_price);

    UPDATE products
    SET stock_quantity = stock_quantity + NEW.quantity, cost = v_new
    WHERE id = NEW.product_id
    RETURNING stock_quantity INTO after_stock;

    UPDATE purchase_items
    SET cost_before = v_cost, cost_after = v_new, cost_applied_at = clock_timestamp()
    WHERE id = NEW.id;
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
-- 5. Batal PO: stok dikembalikan + modal dikembalikan
-- ============================================================
-- Sama dengan migration33 (cek + kurangi stok dalam 1 perintah), ditambah
-- modal produk dikembalikan ke modal sebelum PO ini kalau bisa dipastikan.
CREATE OR REPLACE FUNCTION restore_stock_on_purchase_cancel()
RETURNS TRIGGER AS $$
DECLARE
  item        RECORD;
  rel         RECORD;
  after_stock integer;
  avail       integer;
  v_bases     jsonb := '{}'::jsonb;
  v_base      numeric;
BEGIN
  IF NEW.status = 'cancelled' AND OLD.status != 'cancelled' THEN

    -- Modal dasar dihitung SEBELUM stok disentuh, per produk
    FOR rel IN
      SELECT DISTINCT product_id FROM purchase_items
      WHERE purchase_id = NEW.id AND product_id IS NOT NULL
    LOOP
      v_base := purchase_cost_base(NEW.id, rel.product_id);
      IF v_base IS NOT NULL THEN
        v_bases := v_bases || jsonb_build_object(rel.product_id::text, v_base);
      END IF;
    END LOOP;

    FOR item IN SELECT * FROM purchase_items WHERE purchase_id = NEW.id LOOP

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

    IF v_bases <> '{}'::jsonb THEN
      PERFORM set_config('app.cost_source', 'purchase_cancel', true);
      PERFORM set_config('app.cost_ref', NEW.id::text, true);
      UPDATE products p
      SET cost = (v_bases ->> p.id::text)::numeric
      WHERE v_bases ? p.id::text;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- ============================================================
-- 6. Edit PO: kontribusi item lama dikeluarkan dari rata-rata
-- ============================================================
-- Sama dengan versi migration36, ditambah: sebelum item lama dilepas, modal
-- dasar tiap produk diambil lewat purchase_cost_base() lalu diteruskan ke
-- trigger lewat GUC. Produk yang dihapus dari PO langsung dikembalikan ke modal
-- dasarnya.
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
  v_base      numeric;
  v_in_new    boolean;
  v_gkey      text;
BEGIN
  PERFORM set_config('app.cost_source', 'purchase_edit', true);

  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Pembelian harus berisi minimal 1 barang.';
  END IF;

  PERFORM 1 FROM purchases WHERE id = p_purchase_id AND status <> 'cancelled';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PO tidak ditemukan atau sudah dibatalkan, jadi tidak bisa diedit.';
  END IF;

  SELECT COALESCE(jsonb_object_agg(id::text, jsonb_build_object(
           'product_id', product_id, 'batch_number', batch_number, 'expired_date', expired_date)), '{}'::jsonb)
  INTO v_old
  FROM purchase_items WHERE purchase_id = p_purchase_id;

  FOR rel IN
    SELECT product_id, SUM(quantity)::integer AS qty
    FROM purchase_items WHERE purchase_id = p_purchase_id GROUP BY product_id
  LOOP
    SELECT name INTO prod_name FROM products WHERE id = rel.product_id;

    -- Modal dasar diambil SEBELUM stok & item lama disentuh
    v_base := purchase_cost_base(p_purchase_id, rel.product_id);

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

    IF rel.product_id IS NOT NULL THEN
      v_gkey := replace(rel.product_id::text, '-', '');
      SELECT EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_items) x
        WHERE x->>'product_id' = rel.product_id::text
      ) INTO v_in_new;

      IF v_base IS NULL THEN
        -- Tidak bisa dipastikan → item baru produk ini tidak mengubah modal
        IF v_in_new THEN
          PERFORM set_config('app.avg_skip_' || v_gkey, '1', true);
        END IF;
      ELSIF v_in_new THEN
        PERFORM set_config('app.avg_base_' || v_gkey, v_base::text, true);
      ELSE
        -- Produk dihapus dari PO → modal kembali ke sebelum PO ini
        PERFORM set_config('app.cost_ref', p_purchase_id::text, true);
        UPDATE products SET cost = v_base WHERE id = rel.product_id;
      END IF;
    END IF;
  END LOOP;

  DELETE FROM purchase_items WHERE purchase_id = p_purchase_id;

  FOR it IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    IF (it->>'quantity')::integer <= 0 THEN
      RAISE EXCEPTION 'Jumlah barang harus lebih dari 0.';
    END IF;

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
SELECT 'kolom cost_applied_at ada' AS cek,
       EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_name = 'purchase_items' AND column_name = 'cost_applied_at')::text AS hasil
UNION ALL
SELECT 'trigger pembelian pakai rata-rata',
       (SELECT (pg_get_functiondef(p.oid) LIKE '%avg_cost_after_purchase%')::text
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = 'increase_stock_on_purchase')
UNION ALL
SELECT 'contoh 31@20.138 + 72@16.805',
       avg_cost_after_purchase(31, 20138, 72, 16805)::text;   -- harus 17808.14
