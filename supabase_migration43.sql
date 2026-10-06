-- ============================================================
-- Migration 43: Retur dari Gudang (retur-toko.html) + role gudang
-- Jalankan di Supabase SQL Editor
-- ============================================================
-- Karyawan gudang/toko DIANA KOSMETIK input retur barang dari toko pelanggan
-- lewat halaman sendiri (retur-toko.html), terpisah dari sales.html & halaman
-- admin, supaya sales tidak bisa retur sembarangan.
--
-- Karyawan pilih TOKO, lalu FAKTUR (opsional) + BARANG + QTY. Kalau faktur
-- dibiarkan "Otomatis", faktur asal dicari di database oleh create_store_return():
-- mulai dari faktur terbaru toko itu yang berisi barang tsb, dan kalau qty-nya
-- melebihi sisa di satu faktur, sisanya diambil dari faktur sebelumnya
-- (1 retur per faktur). Jadi retur tetap
-- terikat ke faktur seperti sebelumnya — piutang, laporan sales, dan batas qty
-- retur tetap jalan tanpa perubahan apa pun.
--
-- Retur dari gudang masuk sebagai 'pending'. Stok & piutang baru berubah
-- setelah admin menyetujui di retur.html, sama persis dengan retur buatan admin.
--
-- Isi:
--   1. Role 'gudang' di user_profiles
--   2. Kolom source / created_by_id / photo_path di returns
--   3. Pengaman role di user_profiles (cuma super_admin yang boleh mengubah role)
--   4. Fungsi create_store_return()
--   5. Kunci RLS returns & return_items: sales tidak bisa menulis retur
--   6. Bucket privat return-photos (foto barang retur, opsional)
-- ============================================================


-- ============================================================
-- 1. Role gudang
-- ============================================================
ALTER TABLE user_profiles DROP CONSTRAINT IF EXISTS user_profiles_role_check;
ALTER TABLE user_profiles ADD CONSTRAINT user_profiles_role_check
  CHECK (role IN ('admin', 'sales', 'super_admin', 'gudang'));


-- ============================================================
-- 2. Kolom baru di returns
-- ============================================================
-- 'admin'  = dibuat admin di retur.html (semua retur lama)
-- 'gudang' = dibuat lewat retur-toko.html
ALTER TABLE returns ADD COLUMN IF NOT EXISTS source text NOT NULL DEFAULT 'admin';
ALTER TABLE returns ADD COLUMN IF NOT EXISTS created_by_id uuid REFERENCES auth.users(id) ON DELETE SET NULL;
-- Path di bucket return-photos. Satu pengajuan yang terpecah ke beberapa faktur
-- memakai foto yang sama, jadi path-nya boleh sama di beberapa baris.
ALTER TABLE returns ADD COLUMN IF NOT EXISTS photo_path text;

CREATE INDEX IF NOT EXISTS idx_returns_created_by_id ON returns (created_by_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_returns_invoice_id ON returns (invoice_id);


-- ============================================================
-- 3. Pengaman role di user_profiles
-- ============================================================
-- user_profiles tidak memakai RLS (setiap akun yang login bisa menulis ke sana).
-- Tanpa pengaman ini, kunci retur di bagian 5 tidak ada artinya: akun sales cukup
-- mengubah role-nya sendiri jadi 'gudang' atau 'admin' lewat satu panggilan API.
--
-- Aturannya:
--   * SQL Editor / service role (bukan anon/authenticated)  → bebas
--   * Role tidak berubah (edit nama, aktif/nonaktif)           → bebas
--   * Setup awal: belum ada admin sama sekali (setup.html)    → boleh bikin admin
--   * Selain itu cuma super_admin yang boleh menentukan/mengubah role
--
-- settings.html sudah memulihkan sesi super_admin SEBELUM menyimpan profil akun
-- baru, jadi pembuatan akun sales & gudang dari halaman Pengaturan tetap jalan.
--
-- Sengaja SECURITY INVOKER: current_user di sini harus role si pemanggil
-- (anon/authenticated dari PostgREST), bukan pemilik fungsi.
CREATE OR REPLACE FUNCTION guard_user_profile_role()
RETURNS TRIGGER AS $$
DECLARE
  v_caller_role text;
BEGIN
  IF current_user NOT IN ('anon', 'authenticated') THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' AND NEW.role IS NOT DISTINCT FROM OLD.role THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT'
     AND NEW.role IN ('admin', 'super_admin')
     AND NOT EXISTS (SELECT 1 FROM user_profiles WHERE role IN ('admin', 'super_admin')) THEN
    RETURN NEW;
  END IF;

  SELECT role INTO v_caller_role
  FROM user_profiles
  WHERE id = auth.uid() AND is_active;

  IF v_caller_role = 'super_admin' THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'Hanya super_admin yang boleh mengatur role akun'
    USING ERRCODE = '42501';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_guard_user_profile_role ON user_profiles;
CREATE TRIGGER trg_guard_user_profile_role
  BEFORE INSERT OR UPDATE OF role ON user_profiles
  FOR EACH ROW
  EXECUTE FUNCTION guard_user_profile_role();


-- ============================================================
-- 4. create_store_return()
-- ============================================================
-- Dipanggil retur-toko.html:
--   supabase.rpc('create_store_return', {
--     p_customer_id, p_items: [{product_id, quantity}], p_reason, p_notes, p_photo_path,
--     p_invoice_id })
--
-- p_invoice_id NULL = "Otomatis": faktur dicari sendiri, terbaru dulu, dan kalau
-- qty melebihi sisa satu faktur sisanya diambil dari faktur sebelumnya.
-- p_invoice_id diisi = karyawan memilih fakturnya sendiri: cuma faktur itu yang
-- dipakai, qty melebihi sisa faktur itu = ditolak.
--
-- Semua dalam SATU transaksi: kalau satu barang qty-nya melebihi sisa yang bisa
-- diretur, tidak ada satu pun retur yang tersimpan.
--
-- Aturan faktur sama dengan retur.html:
--   * faktur toko itu, bukan 'cancelled', verifikasi NULL atau 'approved'
--   * sisa yang bisa diretur = qty terjual − qty retur 'pending' + 'approved'
--     di faktur itu (pending ikut dihitung supaya tidak bisa diajukan dua kali)
--   * harga retur = invoice_items.price (sama dengan retur.html)
--   * kalau produk muncul di >1 baris satu faktur, qty yang sudah diretur
--     dianggap memakai baris-baris awal dulu (sama dengan retur.html)
--
-- SECURITY DEFINER supaya bisa menulis returns walaupun RLS (bagian 5) cuma
-- mengizinkan admin menulis langsung — role pemanggil dicek sendiri di sini.
-- Versi awal tanpa p_invoice_id dihapus dulu: kalau dibiarkan, dua versi fungsi
-- sama-sama cocok dan PostgREST menolak panggilannya (ambigu).
DROP FUNCTION IF EXISTS create_store_return(uuid, jsonb, text, text, text);

CREATE OR REPLACE FUNCTION create_store_return(
  p_customer_id uuid,
  p_items       jsonb,
  p_reason      text,
  p_notes       text DEFAULT NULL,
  p_photo_path  text DEFAULT NULL,
  p_invoice_id  uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  v_role      text;
  v_name      text;
  v_today     date := (now() AT TIME ZONE 'Asia/Jakarta')::date;
  v_req       record;
  v_inv       record;
  v_line      record;
  v_prod      record;
  v_left      integer;
  v_skip      integer;
  v_avail     integer;
  v_take      integer;
  v_alloc     jsonb := '[]'::jsonb;
  v_ret_id    uuid;
  v_ret_no    text;
  v_total     numeric;
  v_result    jsonb := '[]'::jsonb;
BEGIN
  SELECT role, name INTO v_role, v_name
  FROM user_profiles
  WHERE id = v_uid AND is_active;

  IF v_role IS NULL OR v_role NOT IN ('gudang', 'admin', 'super_admin') THEN
    RAISE EXCEPTION 'Akun ini tidak boleh mengajukan retur' USING ERRCODE = '42501';
  END IF;

  IF p_reason IS NULL OR btrim(p_reason) = '' THEN
    RAISE EXCEPTION 'Alasan retur wajib diisi';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Pilih minimal 1 barang untuk diretur';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM customers WHERE id = p_customer_id) THEN
    RAISE EXCEPTION 'Toko tidak ditemukan';
  END IF;

  IF p_invoice_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM invoices
    WHERE id = p_invoice_id
      AND customer_id = p_customer_id
      AND status <> 'cancelled'
      AND (verification_status IS NULL OR verification_status = 'approved')
  ) THEN
    RAISE EXCEPTION 'Faktur yang dipilih bukan milik toko ini, sudah dibatalkan, atau ditolak verifikasinya';
  END IF;

  -- Dua pengajuan untuk toko yang sama diproses bergiliran, supaya keduanya
  -- tidak sama-sama melihat sisa qty yang sama lalu sama-sama lolos.
  PERFORM pg_advisory_xact_lock(hashtextextended('store_return:' || p_customer_id::text, 0));

  -- Produk yang sama dikirim dua kali digabung dulu
  FOR v_req IN
    SELECT (e->>'product_id')::uuid AS product_id,
           sum((e->>'quantity')::integer) AS qty
    FROM jsonb_array_elements(p_items) e
    GROUP BY 1
  LOOP
    IF v_req.product_id IS NULL OR v_req.qty IS NULL OR v_req.qty <= 0 THEN
      RAISE EXCEPTION 'Qty retur tidak valid';
    END IF;

    SELECT name, sku INTO v_prod FROM products WHERE id = v_req.product_id;
    v_left := v_req.qty;

    FOR v_inv IN
      SELECT i.id,
             (SELECT coalesce(sum(ri.quantity), 0)
                FROM returns r
                JOIN return_items ri ON ri.return_id = r.id
               WHERE r.invoice_id = i.id
                 AND ri.product_id = v_req.product_id
                 AND r.status IN ('pending', 'approved')) AS returned
      FROM invoices i
      WHERE i.customer_id = p_customer_id
        AND (p_invoice_id IS NULL OR i.id = p_invoice_id)
        AND i.status <> 'cancelled'
        AND (i.verification_status IS NULL OR i.verification_status = 'approved')
        AND EXISTS (SELECT 1 FROM invoice_items ii
                     WHERE ii.invoice_id = i.id AND ii.product_id = v_req.product_id)
      ORDER BY i.invoice_date DESC, i.created_at DESC
    LOOP
      EXIT WHEN v_left <= 0;
      v_skip := v_inv.returned;

      FOR v_line IN
        SELECT ii.quantity, ii.price, ii.product_name
        FROM invoice_items ii
        WHERE ii.invoice_id = v_inv.id AND ii.product_id = v_req.product_id
        ORDER BY ii.created_at, ii.id
      LOOP
        EXIT WHEN v_left <= 0;
        v_avail := v_line.quantity - least(v_skip, v_line.quantity);
        v_skip  := v_skip - least(v_skip, v_line.quantity);
        v_take  := least(v_left, v_avail);
        IF v_take > 0 THEN
          v_alloc := v_alloc || jsonb_build_object(
            'invoice_id',   v_inv.id,
            'product_id',   v_req.product_id,
            'product_name', coalesce(v_prod.name, v_line.product_name, '-'),
            'sku',          coalesce(v_prod.sku, '-'),
            'quantity',     v_take,
            'unit_price',   coalesce(v_line.price, 0)
          );
          v_left := v_left - v_take;
        END IF;
      END LOOP;
    END LOOP;

    IF v_left > 0 THEN
      RAISE EXCEPTION 'Qty retur "%" melebihi sisa yang bisa diretur % (diminta %, sisa %). Mungkin sudah pernah diretur sebelumnya.',
        coalesce(v_prod.name, v_req.product_id::text),
        CASE WHEN p_invoice_id IS NULL THEN 'untuk toko ini' ELSE 'dari faktur ini' END,
        v_req.qty, v_req.qty - v_left;
    END IF;
  END LOOP;

  -- 1 retur per faktur, faktur terbaru dulu
  FOR v_inv IN
    SELECT i.id, i.invoice_number, i.customer_id, i.customer_name
    FROM invoices i
    WHERE i.id IN (SELECT DISTINCT (a->>'invoice_id')::uuid FROM jsonb_array_elements(v_alloc) a)
    ORDER BY i.invoice_date DESC, i.created_at DESC
  LOOP
    SELECT coalesce(sum(x.quantity * x.unit_price), 0) INTO v_total
    FROM jsonb_to_recordset(v_alloc) AS x(invoice_id uuid, quantity integer, unit_price numeric)
    WHERE x.invoice_id = v_inv.id;

    -- return_number diisi trigger generate_return_number (migration22)
    INSERT INTO returns (
      invoice_id, invoice_number, customer_id, customer_name, return_date,
      reason, notes, status, total_return_value,
      created_by, created_by_id, source, photo_path
    ) VALUES (
      v_inv.id, v_inv.invoice_number, v_inv.customer_id, v_inv.customer_name, v_today,
      btrim(p_reason), nullif(btrim(coalesce(p_notes, '')), ''), 'pending', v_total,
      v_name, v_uid, 'gudang', nullif(btrim(coalesce(p_photo_path, '')), '')
    )
    RETURNING id, return_number INTO v_ret_id, v_ret_no;

    INSERT INTO return_items (return_id, product_id, product_name, sku, quantity, unit_price, subtotal)
    SELECT v_ret_id, x.product_id, x.product_name, x.sku,
           sum(x.quantity), x.unit_price, sum(x.quantity) * x.unit_price
    FROM jsonb_to_recordset(v_alloc)
         AS x(invoice_id uuid, product_id uuid, product_name text, sku text, quantity integer, unit_price numeric)
    WHERE x.invoice_id = v_inv.id
    GROUP BY x.product_id, x.product_name, x.sku, x.unit_price;

    v_result := v_result || jsonb_build_object(
      'id', v_ret_id, 'return_number', v_ret_no, 'invoice_number', v_inv.invoice_number);
  END LOOP;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION create_store_return(uuid, jsonb, text, text, text, uuid) FROM public;
GRANT EXECUTE ON FUNCTION create_store_return(uuid, jsonb, text, text, text, uuid) TO authenticated;


-- ============================================================
-- 5. Kunci RLS returns & return_items
-- ============================================================
-- Membaca tetap bebas seperti sebelumnya (piutang, laba rugi, laporan sales, tab
-- Hari Ini di sales.html semuanya membaca retur). Yang dikunci cuma MENULIS:
--   * insert/update/delete langsung → admin & super_admin (retur.html)
--   * gudang → hanya lewat create_store_return() di atas
--   * sales  → tidak bisa sama sekali
CREATE OR REPLACE FUNCTION current_app_role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT role FROM user_profiles WHERE id = auth.uid() AND is_active
$$;

ALTER TABLE returns      ENABLE ROW LEVEL SECURITY;
ALTER TABLE return_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS returns_select       ON returns;
DROP POLICY IF EXISTS returns_admin_insert ON returns;
DROP POLICY IF EXISTS returns_admin_update ON returns;
DROP POLICY IF EXISTS returns_admin_delete ON returns;

CREATE POLICY returns_select ON returns
  FOR SELECT USING (true);
CREATE POLICY returns_admin_insert ON returns
  FOR INSERT TO authenticated
  WITH CHECK (current_app_role() IN ('admin', 'super_admin'));
CREATE POLICY returns_admin_update ON returns
  FOR UPDATE TO authenticated
  USING (current_app_role() IN ('admin', 'super_admin'))
  WITH CHECK (current_app_role() IN ('admin', 'super_admin'));
CREATE POLICY returns_admin_delete ON returns
  FOR DELETE TO authenticated
  USING (current_app_role() IN ('admin', 'super_admin'));

DROP POLICY IF EXISTS return_items_select       ON return_items;
DROP POLICY IF EXISTS return_items_admin_insert ON return_items;
DROP POLICY IF EXISTS return_items_admin_update ON return_items;
DROP POLICY IF EXISTS return_items_admin_delete ON return_items;

CREATE POLICY return_items_select ON return_items
  FOR SELECT USING (true);
CREATE POLICY return_items_admin_insert ON return_items
  FOR INSERT TO authenticated
  WITH CHECK (current_app_role() IN ('admin', 'super_admin'));
CREATE POLICY return_items_admin_update ON return_items
  FOR UPDATE TO authenticated
  USING (current_app_role() IN ('admin', 'super_admin'))
  WITH CHECK (current_app_role() IN ('admin', 'super_admin'));
CREATE POLICY return_items_admin_delete ON return_items
  FOR DELETE TO authenticated
  USING (current_app_role() IN ('admin', 'super_admin'));


-- ============================================================
-- 6. Bucket foto retur (privat, dibuka lewat signed URL)
-- ============================================================
-- Foto dikecilkan dulu di browser (maks 1200px, webp/jpeg) — batas 1 MB di sini
-- cuma pengaman kuota Supabase gratis, sama seperti product-photos.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('return-photos', 'return-photos', false, 1048576, ARRAY['image/webp', 'image/jpeg'])
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Authenticated upload return photos" ON storage.objects;
CREATE POLICY "Authenticated upload return photos" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'return-photos');

DROP POLICY IF EXISTS "Authenticated read return photos" ON storage.objects;
CREATE POLICY "Authenticated read return photos" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'return-photos');

-- Pengunggah boleh menghapus fotonya sendiri — dipakai kalau pengajuan retur
-- gagal disimpan setelah fotonya terlanjur terunggah.
DROP POLICY IF EXISTS "Owner delete return photos" ON storage.objects;
CREATE POLICY "Owner delete return photos" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'return-photos' AND owner = auth.uid());
