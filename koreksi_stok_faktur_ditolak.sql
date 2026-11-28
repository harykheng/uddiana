-- ============================================================
-- KOREKSI STOK: faktur DITOLAK yang stoknya dikembalikan 2x
-- Jalankan di Supabase SQL Editor — SEKALI JALAN, seluruh file.
-- ============================================================
-- Latar belakang: sebelum migration50, Tolak faktur di verify-invoices.html
-- mengubah status faktur jadi 'cancelled' (trigger mengembalikan stok, tercatat
-- 'invoice_cancel') LALU browser menambah stok lagi per barang (tercatat
-- 'invoice_reject'). Stok produk kelebihan sebesar qty baris 'invoice_reject'.
--
-- CARA PAKAI
--   1. Jalankan file ini apa adanya → cuma PRATINJAU, tidak mengubah apa pun.
--      Hasilnya tabel per faktur+produk dengan kolom "status":
--        AKAN DIKOREKSI           → stok akan dikurangi sebesar "kelebihan"
--        LEWATI: sudah ada ...    → setelah faktur ditolak, stok produk itu sudah
--                                   pernah di-opname / Sesuaikan Stok / set massal
--                                   (tipe 'adjustment'), jadi kelebihannya kemungkinan
--                                   sudah ikut terkoreksi. Cek fisik manual.
--        LEWATI: stok sekarang kurang → dikurangi akan minus. Cek fisik manual.
--        SUDAH DIKOREKSI          → file ini pernah dijalankan untuk baris itu
--   2. Cek daftarnya. Kalau setuju, ubah   jalankan boolean := false;
--      di bawah jadi   true   lalu Run lagi. Tabel yang tampil sesudahnya
--      menunjukkan baris yang barusan dikoreksi sebagai SUDAH DIKOREKSI.
--
-- PENGAMAN
--   - Hanya faktur yang punya baris 'invoice_cancel' DAN 'invoice_reject' untuk
--     produk yang sama (dobel terbukti). Kelebihan = qty terkecil dari keduanya.
--   - Tiap koreksi dicatat di Kartu Stok: type 'out', reference_type
--     'invoice_reject_fix', reference_id = faktur, catatan berisi nomor faktur.
--     Baris yang sudah punya catatan itu tidak dikoreksi lagi → aman di-Run ulang.
--   - Pengurangan stok "cek + kurangi" satu perintah (tidak bisa minus).
--   - Ditolak kalau ada sesi stock opname aktif.
--   - Semua dalam satu transaksi: gagal satu = tidak ada yang berubah.
-- ============================================================

CREATE TEMP VIEW _kelebihan_tolak AS
WITH dobel AS (
  SELECT sm.reference_id AS invoice_id, sm.product_id,
         MAX(sm.product_name) AS product_name,
         SUM(sm.quantity) FILTER (WHERE sm.reference_type = 'invoice_cancel') AS qty_trigger,
         SUM(sm.quantity) FILTER (WHERE sm.reference_type = 'invoice_reject') AS qty_browser,
         MAX(sm.created_at) FILTER (WHERE sm.reference_type = 'invoice_reject') AS ditolak_pada
  FROM stock_movements sm
  WHERE sm.reference_type IN ('invoice_cancel', 'invoice_reject')
    AND sm.reference_id IS NOT NULL
  GROUP BY sm.reference_id, sm.product_id
  HAVING SUM(sm.quantity) FILTER (WHERE sm.reference_type = 'invoice_reject') > 0
     AND SUM(sm.quantity) FILTER (WHERE sm.reference_type = 'invoice_cancel') > 0
)
SELECT d.invoice_id,
       i.invoice_number,
       d.product_id,
       COALESCE(p.name, d.product_name) AS produk,
       d.ditolak_pada,
       LEAST(d.qty_trigger, d.qty_browser)::integer AS kelebihan,
       p.stock_quantity AS stok_sekarang,
       CASE
         WHEN EXISTS (SELECT 1 FROM stock_movements f
                      WHERE f.reference_type = 'invoice_reject_fix'
                        AND f.reference_id = d.invoice_id AND f.product_id = d.product_id)
           THEN 'SUDAH DIKOREKSI'
         WHEN p.id IS NULL
           THEN 'LEWATI: produk sudah dihapus'
         WHEN EXISTS (SELECT 1 FROM stock_movements a
                      WHERE a.product_id = d.product_id
                        AND a.type = 'adjustment'
                        AND a.created_at > d.ditolak_pada)
           THEN 'LEWATI: sudah ada opname/penyesuaian stok sesudahnya — cek fisik'
         WHEN p.stock_quantity < LEAST(d.qty_trigger, d.qty_browser)
           THEN 'LEWATI: stok sekarang kurang dari kelebihan — cek fisik'
         ELSE 'AKAN DIKOREKSI'
       END AS status
FROM dobel d
LEFT JOIN invoices i ON i.id = d.invoice_id
LEFT JOIN products p ON p.id = d.product_id;


DO $$
DECLARE
  jalankan boolean := false;   -- ← ubah jadi true untuk benar-benar mengoreksi
  r        record;
  v_after  integer;
  v_opname text;
  v_jumlah integer := 0;
BEGIN
  IF NOT jalankan THEN
    RAISE NOTICE 'Mode PRATINJAU — tidak ada yang diubah.';
    RETURN;
  END IF;

  SELECT name INTO v_opname FROM opname_sessions WHERE status = 'active' LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'Sedang ada sesi stock opname "%" — selesaikan dulu, baru jalankan koreksi.', v_opname;
  END IF;

  -- Urut product_id + waktu: stok satu produk yang kena beberapa faktur dikurangi
  -- berurutan, dan kunci baris produk selalu diambil dengan urutan yang sama.
  FOR r IN SELECT * FROM _kelebihan_tolak
           WHERE status = 'AKAN DIKOREKSI'
           ORDER BY product_id, ditolak_pada
  LOOP
    UPDATE products
    SET stock_quantity = stock_quantity - r.kelebihan
    WHERE id = r.product_id AND stock_quantity >= r.kelebihan
    RETURNING stock_quantity INTO v_after;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Stok "%" tidak cukup untuk dikurangi % (faktur %). Tidak ada yang diubah.',
        r.produk, r.kelebihan, r.invoice_number;
    END IF;

    INSERT INTO stock_movements
      (product_id, product_name, type, quantity, quantity_before, quantity_after,
       reference_type, reference_id, notes)
    VALUES
      (r.product_id, r.produk, 'out', r.kelebihan, v_after + r.kelebihan, v_after,
       'invoice_reject_fix', r.invoice_id,
       format('Koreksi: stok faktur ditolak %s dikembalikan 2x', COALESCE(r.invoice_number, '?')));

    v_jumlah := v_jumlah + 1;
  END LOOP;

  RAISE NOTICE 'Selesai: % baris dikoreksi.', v_jumlah;
END $$;


-- Hasil (tampil di panel bawah). Setelah koreksi, baris yang barusan diproses
-- berstatus SUDAH DIKOREKSI.
SELECT invoice_number AS faktur, produk, ditolak_pada, kelebihan,
       stok_sekarang, status
FROM _kelebihan_tolak
ORDER BY (status = 'AKAN DIKOREKSI') DESC, ditolak_pada DESC;
