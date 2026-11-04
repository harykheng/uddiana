-- ============================================================
-- Migration 46: Nilai retur pakai harga SETELAH diskon
-- ============================================================
-- Bug: harga retur diambil dari invoice_items.price = harga katalog SEBELUM
-- diskon item. Faktur "Rp 70.000 diskon 50%" (dibayar Rp 35.000) diretur
-- senilai Rp 70.000, jadi tagihan toko terpotong terlalu banyak.
--
-- Harga retur sekarang = invoice_items.subtotal / quantity, yaitu harga per pcs
-- yang benar-benar ditagih (sudah termasuk diskon %/nominal, diskon bertingkat,
-- subtotal yang diedit manual, dan baris bonus Rp 0). Fallback ke price kalau
-- subtotal kosong (data sangat lama). retur.html memakai rumus yang sama
-- (netUnitPrice() di js/utils.js). Subtotal tiap baris retur dibulatkan NAIK
-- ke kelipatan 100, sama seperti subtotal faktur (returLineSubtotal()).
--
-- Migration ini cuma memperbaiki retur BARU dari gudang (create_store_return).
-- Retur lama yang sudah tersimpan TIDAK diubah otomatis — lihat query audit di
-- bagian bawah file ini.
--
-- Jalankan setelah migration43. Aman dijalankan ulang.
-- ============================================================

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
        SELECT ii.quantity, ii.product_name,
               -- harga net per pcs (setelah diskon), bukan harga katalog
               coalesce(round(ii.subtotal / nullif(ii.quantity, 0), 2), ii.price) AS price
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
    -- Total = jumlah subtotal per baris retur (dikelompokkan sama seperti INSERT
    -- return_items di bawah), tiap baris dibulatkan naik ke kelipatan 100.
    SELECT coalesce(sum(g.sub), 0) INTO v_total
    FROM (
      SELECT ceil(round(sum(x.quantity) * x.unit_price) / 100.0) * 100 AS sub
      FROM jsonb_to_recordset(v_alloc)
           AS x(invoice_id uuid, product_id uuid, product_name text, sku text, quantity integer, unit_price numeric)
      WHERE x.invoice_id = v_inv.id
      GROUP BY x.product_id, x.product_name, x.sku, x.unit_price
    ) g;

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
           sum(x.quantity), x.unit_price, ceil(round(sum(x.quantity) * x.unit_price) / 100.0) * 100
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
-- AUDIT (read-only, jalankan terpisah): baris retur lama yang nilainya beda
-- dari aturan baru (harga net faktur, subtotal dibulatkan naik ke 100).
-- selisih > 0 = retur kebesaran (toko dipotong terlalu banyak)
-- selisih < 0 = retur kekecilan (cuma beda pembulatan, biasanya < Rp 100)
-- ============================================================
-- SELECT r.return_number, r.status, r.invoice_number, ri.product_name, ri.quantity,
--        ri.unit_price AS harga_retur, ri.subtotal AS subtotal_retur,
--        ceil(round(ri.quantity * round(ii.subtotal / nullif(ii.quantity, 0), 2)) / 100.0) * 100 AS subtotal_benar,
--        ri.subtotal - ceil(round(ri.quantity * round(ii.subtotal / nullif(ii.quantity, 0), 2)) / 100.0) * 100 AS selisih
-- FROM return_items ri
-- JOIN returns r        ON r.id = ri.return_id
-- JOIN invoice_items ii ON ii.invoice_id = r.invoice_id AND ii.product_id = ri.product_id
-- WHERE r.status <> 'rejected'
--   AND ri.subtotal <> ceil(round(ri.quantity * round(ii.subtotal / nullif(ii.quantity, 0), 2)) / 100.0) * 100
-- ORDER BY selisih DESC, r.return_date DESC;
