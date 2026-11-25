-- ============================================================
-- Migration 50: Edit faktur jadi satu transaksi + kartu stok bersih
-- Jalankan di Supabase SQL Editor (setelah migration43 — pakai current_app_role())
-- ============================================================
-- Masalah sebelumnya, tiga halaman tiga cara edit faktur, semuanya dari browser:
--
-- 1. sales.html — "batalkan faktur → hapus semua item → insert ulang". Trigger
--    restore_stock_on_cancel mengembalikan SEMUA qty, lalu trigger
--    decrease_stock_on_invoice_item memotong lagi. Tiap edit = 2 baris per barang di
--    stock_movements (+12 / −6 / +6 / −12 ...) walau qty-nya tidak berubah, dan kalau
--    koneksi putus setelah item dihapus, faktur tertinggal KOSONG berstatus 'cancelled'.
--
-- 2. invoices.html & verify-invoices.html — stok dihitung di browser lalu ditimpa
--    dengan angka absolut (baca → hitung → tulis). Penjualan lain yang menyelip di
--    antara baca & tulis ikut hilang. Pergerakannya dicatat tipe 'adjustment' tanpa
--    reference_id, jadi di Kartu Stok tidak muncul di kolom Masuk/Keluar & tidak
--    tersambung ke nomor faktur.
--
-- Sekarang ketiganya memanggil edit_invoice() di bawah:
--   - satu transaksi: gagal di langkah mana pun = tidak ada yang berubah
--   - stok hanya digeser sebesar SELISIH bersih per produk (qty baru − qty lama),
--     dicatat 1 baris per produk yang berubah: type 'out'/'in',
--     reference_type 'invoice_edit', reference_id = faktur, catatan "qty X → Y".
--     Produk yang qty-nya sama tidak menulis apa pun.
--   - potong stok tetap "cek + kurangi" satu perintah (pola migration23), jadi tidak
--     bisa minus & tidak menimpa transaksi lain
--
-- Supaya insert baris item di dalam fungsi ini tidak dipotong DUA kali (oleh trigger
-- decrease_stock_on_invoice_item dan oleh perhitungan selisih), trigger itu sekarang
-- melewati dirinya sendiri kalau GUC transaction-local app.invoice_edit = 'on'
-- (pola sama dengan app.cost_source di migration36). Di luar fungsi ini nilainya
-- kosong, jadi faktur baru tetap dipotong seperti biasa.
--
-- Catatan bug terkait yang ikut diperbaiki di verify-invoices.html (tanpa SQL):
-- Tolak faktur menyetel status = 'cancelled' (trigger sudah mengembalikan stok) lalu
-- browser MENAMBAH stok lagi per barang → stok dikembalikan DUA kali. Query audit
-- di bagian bawah file ini.
-- ============================================================


-- ============================================================
-- 1. Trigger potong stok faktur: bisa dilewati oleh edit_invoice()
-- ============================================================
CREATE OR REPLACE FUNCTION decrease_stock_on_invoice_item()
RETURNS TRIGGER AS $$
DECLARE
  prod_name text;
  before_stock integer;
  after_stock integer;
BEGIN
  -- edit_invoice() menggeser stok sendiri berdasarkan selisih bersih
  IF current_setting('app.invoice_edit', true) = 'on' THEN
    RETURN NEW;
  END IF;

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


-- ============================================================
-- 2. edit_invoice()
-- ============================================================
-- p_items  : array baris item. Baris dengan "id" milik faktur ini = di-update,
--            tanpa id = baris baru, baris lama yang tidak disebut = dihapus.
--            Kolom: id, product_id, product_name, quantity, price, item_discount,
--            item_discount2, discount_type, subtotal, cost_price (null = pertahankan
--            cost_price lama kalau produknya sama, kalau beda pakai products.cost)
-- p_header : kolom faktur yang mau diubah (kunci yang tidak dikirim = tidak diubah):
--            customer_id, customer_name, store_name, customer_phone, customer_address,
--            invoice_date, payment_term, notes, total, subtotal, sales_name,
--            created_by_id, approve (true = setujui sekaligus, hanya admin/super_admin)
CREATE OR REPLACE FUNCTION edit_invoice(p_invoice_id uuid, p_items jsonb, p_header jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_role     text := current_app_role();
  v_inv      invoices%ROWTYPE;
  v_opname   text;
  v_bad      text;
  r          record;
  v_after    integer;
  v_changed  integer := 0;
  v_approve  boolean := COALESCE((p_header->>'approve')::boolean, false);
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('sales', 'admin', 'super_admin') THEN
    RAISE EXCEPTION 'Akun ini tidak boleh mengedit faktur.';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Faktur harus berisi minimal 1 barang.';
  END IF;

  SELECT * INTO v_inv FROM invoices WHERE id = p_invoice_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Faktur tidak ditemukan.';
  END IF;
  IF v_inv.status = 'cancelled' THEN
    RAISE EXCEPTION 'Faktur ini sudah dibatalkan, tidak bisa diedit lagi.';
  END IF;

  IF v_role = 'sales' THEN
    IF v_inv.created_by_id IS DISTINCT FROM auth.uid() THEN
      RAISE EXCEPTION 'Faktur ini bukan milik akun Anda.';
    END IF;
    IF v_inv.verification_status IS DISTINCT FROM 'pending' THEN
      RAISE EXCEPTION 'Faktur ini sudah diproses admin, tidak bisa diedit lagi.';
    END IF;
    IF p_header ?| ARRAY['sales_name', 'created_by_id', 'approve'] THEN
      RAISE EXCEPTION 'Sales tidak boleh mengubah sales/verifikasi faktur.';
    END IF;
  END IF;

  IF v_approve AND v_inv.verification_status IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'Faktur ini sudah diproses sebelumnya.';
  END IF;

  SELECT name INTO v_opname FROM opname_sessions WHERE status = 'active' LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'Tidak bisa edit faktur — sedang ada sesi stock opname "%" berlangsung', v_opname;
  END IF;

  -- Baris baru, dibaca dengan tipe kolom invoice_items yang sebenarnya
  CREATE TEMP TABLE _ei_new ON COMMIT DROP AS
    SELECT * FROM jsonb_populate_recordset(NULL::invoice_items, p_items);

  SELECT product_name INTO v_bad FROM _ei_new
  WHERE quantity IS NULL OR quantity <= 0 OR product_id IS NULL LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'Qty "%" harus lebih dari 0.', COALESCE(v_bad, 'barang');
  END IF;
  SELECT n.product_name INTO v_bad FROM _ei_new n
  WHERE NOT EXISTS (SELECT 1 FROM products p WHERE p.id = n.product_id) LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'Produk "%" sudah tidak ada di daftar produk.', COALESCE(v_bad, '?');
  END IF;

  -- id yang bukan milik faktur ini diperlakukan sebagai baris baru
  UPDATE _ei_new n SET id = NULL
  WHERE n.id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM invoice_items i WHERE i.id = n.id AND i.invoice_id = p_invoice_id);

  -- Selisih qty per produk: lama (sebelum diubah) vs baru
  CREATE TEMP TABLE _ei_delta ON COMMIT DROP AS
    SELECT product_id, MAX(product_name) AS product_name,
           SUM(old_qty)::integer AS old_qty, SUM(new_qty)::integer AS new_qty
    FROM (
      SELECT product_id, product_name, quantity AS old_qty, 0 AS new_qty
      FROM invoice_items WHERE invoice_id = p_invoice_id
      UNION ALL
      SELECT product_id, product_name, 0, quantity FROM _ei_new
    ) x
    GROUP BY product_id;

  -- Tulis baris item tanpa memicu potong stok per baris
  PERFORM set_config('app.invoice_edit', 'on', true);

  DELETE FROM invoice_items i
  WHERE i.invoice_id = p_invoice_id
    AND NOT EXISTS (SELECT 1 FROM _ei_new n WHERE n.id = i.id);

  UPDATE invoice_items i SET
    product_id     = n.product_id,
    product_name   = n.product_name,
    quantity       = n.quantity,
    price          = n.price,
    item_discount  = COALESCE(n.item_discount, 0),
    item_discount2 = COALESCE(n.item_discount2, 0),
    discount_type  = COALESCE(n.discount_type, 'percent'),
    subtotal       = n.subtotal,
    cost_price     = COALESCE(n.cost_price,
                       CASE WHEN i.product_id = n.product_id THEN i.cost_price
                            ELSE (SELECT cost FROM products p WHERE p.id = n.product_id) END)
  FROM _ei_new n
  WHERE n.id = i.id;

  INSERT INTO invoice_items
    (invoice_id, product_id, product_name, quantity, price,
     item_discount, item_discount2, discount_type, subtotal, cost_price)
  SELECT p_invoice_id, n.product_id, n.product_name, n.quantity, n.price,
         COALESCE(n.item_discount, 0), COALESCE(n.item_discount2, 0),
         COALESCE(n.discount_type, 'percent'), n.subtotal,
         COALESCE(n.cost_price, (SELECT cost FROM products p WHERE p.id = n.product_id), 0)
  FROM _ei_new n
  WHERE n.id IS NULL;

  PERFORM set_config('app.invoice_edit', 'off', true);

  -- Geser stok sebesar selisih bersih. Urut product_id supaya dua edit bersamaan
  -- selalu mengunci baris produk dengan urutan sama (tidak deadlock).
  FOR r IN SELECT * FROM _ei_delta WHERE new_qty <> old_qty ORDER BY product_id LOOP
    IF r.new_qty > r.old_qty THEN
      UPDATE products
      SET stock_quantity = stock_quantity - (r.new_qty - r.old_qty)
      WHERE id = r.product_id AND stock_quantity >= (r.new_qty - r.old_qty)
      RETURNING stock_quantity INTO v_after;
      IF NOT FOUND THEN
        SELECT stock_quantity INTO v_after FROM products WHERE id = r.product_id;
        RAISE EXCEPTION 'Stok "%" tidak cukup (tersedia untuk faktur ini: %, diminta: %)',
          r.product_name, COALESCE(v_after, 0) + r.old_qty, r.new_qty;
      END IF;
      INSERT INTO stock_movements
        (product_id, product_name, type, quantity, quantity_before, quantity_after,
         reference_type, reference_id, notes)
      VALUES
        (r.product_id, r.product_name, 'out', r.new_qty - r.old_qty,
         v_after + (r.new_qty - r.old_qty), v_after,
         'invoice_edit', p_invoice_id,
         format('Edit faktur: qty %s → %s', r.old_qty, r.new_qty));
    ELSE
      UPDATE products
      SET stock_quantity = stock_quantity + (r.old_qty - r.new_qty)
      WHERE id = r.product_id
      RETURNING stock_quantity INTO v_after;
      IF FOUND THEN
        INSERT INTO stock_movements
          (product_id, product_name, type, quantity, quantity_before, quantity_after,
           reference_type, reference_id, notes)
        VALUES
          (r.product_id, r.product_name, 'in', r.old_qty - r.new_qty,
           v_after - (r.old_qty - r.new_qty), v_after,
           'invoice_edit', p_invoice_id,
           format('Edit faktur: qty %s → %s', r.old_qty, r.new_qty));
      END IF;
    END IF;
    v_changed := v_changed + 1;
  END LOOP;

  -- Kolom header yang dikirim saja yang diubah
  UPDATE invoices SET
    customer_id      = CASE WHEN p_header ? 'customer_id'      THEN NULLIF(p_header->>'customer_id', '')::uuid ELSE customer_id END,
    customer_name    = CASE WHEN p_header ? 'customer_name'    THEN p_header->>'customer_name'    ELSE customer_name END,
    store_name       = CASE WHEN p_header ? 'store_name'       THEN p_header->>'store_name'       ELSE store_name END,
    customer_phone   = CASE WHEN p_header ? 'customer_phone'   THEN p_header->>'customer_phone'   ELSE customer_phone END,
    customer_address = CASE WHEN p_header ? 'customer_address' THEN p_header->>'customer_address' ELSE customer_address END,
    invoice_date     = CASE WHEN p_header ? 'invoice_date'     THEN (p_header->>'invoice_date')::date ELSE invoice_date END,
    payment_term     = CASE WHEN p_header ? 'payment_term'     THEN p_header->>'payment_term'     ELSE payment_term END,
    notes            = CASE WHEN p_header ? 'notes'            THEN p_header->>'notes'            ELSE notes END,
    total            = CASE WHEN p_header ? 'total'            THEN (p_header->>'total')::numeric    ELSE total END,
    subtotal         = CASE WHEN p_header ? 'subtotal'         THEN (p_header->>'subtotal')::numeric ELSE subtotal END,
    sales_name       = CASE WHEN p_header ? 'sales_name'       THEN p_header->>'sales_name'       ELSE sales_name END,
    created_by_id    = CASE WHEN p_header ? 'created_by_id'    THEN NULLIF(p_header->>'created_by_id', '')::uuid ELSE created_by_id END,
    verification_status = CASE WHEN v_approve THEN 'approved' ELSE verification_status END,
    verified_by_id   = CASE WHEN v_approve THEN auth.uid() ELSE verified_by_id END,
    verified_at      = CASE WHEN v_approve THEN now()      ELSE verified_at END
  WHERE id = p_invoice_id;

  RETURN jsonb_build_object('products_changed', v_changed);
END;
$$;

GRANT EXECUTE ON FUNCTION edit_invoice(uuid, jsonb, jsonb) TO authenticated;


-- ============================================================
-- VERIFIKASI
-- ============================================================
-- Harus true dua-duanya:
SELECT
  (SELECT pg_get_functiondef('decrease_stock_on_invoice_item'::regproc) LIKE '%app.invoice_edit%') AS trigger_sudah_baru,
  (SELECT count(*) = 1 FROM pg_proc WHERE proname = 'edit_invoice') AS fungsi_edit_ada;


-- ============================================================
-- AUDIT (opsional, cuma membaca): faktur DITOLAK yang stoknya dikembalikan dua kali
-- ============================================================
-- Tiap faktur ditolak sebelum perbaikan ini punya baris 'invoice_cancel' (dari trigger)
-- DAN baris 'invoice_reject' (dari browser) untuk barang yang sama → stok produk itu
-- kelebihan sebesar qty_kelebihan. Cek fisik barangnya dulu sebelum mengoreksi lewat
-- Sesuaikan Stok di halaman Produk / stock opname.
--
-- SELECT i.invoice_number, sm.product_name,
--        SUM(sm.quantity) FILTER (WHERE sm.reference_type = 'invoice_cancel') AS dari_trigger,
--        SUM(sm.quantity) FILTER (WHERE sm.reference_type = 'invoice_reject') AS qty_kelebihan,
--        MAX(sm.created_at) AS kapan
-- FROM stock_movements sm
-- JOIN invoices i ON i.id = sm.reference_id
-- WHERE sm.reference_type IN ('invoice_cancel', 'invoice_reject')
-- GROUP BY i.invoice_number, sm.product_id, sm.product_name
-- HAVING SUM(sm.quantity) FILTER (WHERE sm.reference_type = 'invoice_reject') > 0
--    AND SUM(sm.quantity) FILTER (WHERE sm.reference_type = 'invoice_cancel') > 0
-- ORDER BY kapan DESC;
