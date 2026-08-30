-- ============================================================
-- Migration 32: Lengkapi riwayat retur yang hilang (temuan F-03)
-- ============================================================
-- LATAR BELAKANG
-- retur.html dulu mengirim `type: 'return_in'` ke stock_movements, padahal
-- constraint stock_movements_type_check di supabase_schema.sql cuma mengizinkan
-- 'in' | 'out' | 'adjustment'. Jadi setiap retur yang disetujui:
--   • stok produk NAIK dengan benar (products.stock_quantity sudah betul), tapi
--   • baris stock_movements-nya SELALU ditolak database.
-- Kodenya cuma menampilkan toast lalu lanjut, jadi tidak ada yang sadar.
-- Sudah diperbaiki di kode (sekarang pakai 'in' + reference_type 'return_approve').
-- File ini hanya untuk menambal riwayat LAMA yang terlanjur hilang.
--
-- KENAPA TIDAK ASAL INSERT
-- Kolom quantity_before/quantity_after dipakai langsung sebagai kolom "Saldo" di
-- Kartu Stok (products.html). Menebak angka historis untuk kolom itu justru
-- merusak tampilannya. Untungnya angka yang benar bisa DIHITUNG, bukan ditebak:
-- karena retur memang sudah menaikkan products.stock_quantity, pergerakan
-- sesudahnya tercatat dengan quantity_before yang SUDAH memuat efek retur itu.
-- Artinya ada LOMPATAN di buku besar tepat di posisi retur yang hilang, dan
-- besar lompatan itu = qty retur. Script ini mencari lompatan tersebut.
--
-- PENGAMAN
-- Tabel returns tidak punya kolom updated_at, jadi waktu persetujuan didekati
-- dengan created_at. Kalau pendekatan itu meleset, pasangan pergerakan yang
-- ketemu jadi salah dan lompatannya TIDAK akan sama dengan qty — baris itu
-- otomatis dilewati, bukan ditulis dengan angka ngawur. Begitu juga kalau satu
-- produk punya beberapa retur hilang di celah yang sama (lompatannya jadi
-- gabungan, tidak cocok dengan qty manapun). Semua yang dilewati dilaporkan di
-- LANGKAH 1 untuk ditangani manual.
--
-- CARA PAKAI: jalankan LANGKAH 1 dulu dan baca hasilnya. Kalau kolom `aman`
-- sudah true semua (atau yang false memang wajar), baru jalankan LANGKAH 2.
-- ============================================================


-- ============================================================
-- LANGKAH 1 — DIAGNOSA (hanya membaca, tidak mengubah apapun)
-- ============================================================
WITH missing AS (
  SELECT
    r.id                        AS return_id,
    r.return_number,
    r.created_at                AS approx_at,
    ri.product_id,
    ri.product_name,
    ri.quantity::int            AS quantity
  FROM returns r
  JOIN return_items ri ON ri.return_id = r.id
  WHERE r.status = 'approved'
    AND ri.product_id IS NOT NULL
    AND ri.quantity > 0
    AND NOT EXISTS (
      SELECT 1 FROM stock_movements sm
      WHERE sm.product_id = ri.product_id
        AND (
             (sm.reference_type = 'return_approve' AND sm.reference_id = r.id)
          OR (r.return_number IS NOT NULL AND sm.notes LIKE '%' || r.return_number || '%')
        )
    )
),
ctx AS (
  SELECT
    m.*,
    prev.quantity_after  AS prev_after,
    nxt.quantity_before  AS next_before,
    pr.stock_quantity    AS current_stock
  FROM missing m
  LEFT JOIN LATERAL (
    SELECT sm.quantity_after
    FROM stock_movements sm
    WHERE sm.product_id = m.product_id AND sm.created_at <= m.approx_at
    ORDER BY sm.created_at DESC, sm.id DESC
    LIMIT 1
  ) prev ON true
  LEFT JOIN LATERAL (
    SELECT sm.quantity_before
    FROM stock_movements sm
    WHERE sm.product_id = m.product_id AND sm.created_at > m.approx_at
    ORDER BY sm.created_at ASC, sm.id ASC
    LIMIT 1
  ) nxt ON true
  LEFT JOIN products pr ON pr.id = m.product_id
),
calc AS (
  SELECT
    c.*,
    -- Saldo sesudah retur = quantity_before pergerakan berikutnya. Kalau retur ini
    -- kejadian terakhir untuk produk tsb, pakai stok produk sekarang.
    COALESCE(c.next_before, c.current_stock) AS after_val,
    -- Saldo sebelum retur = quantity_after pergerakan sebelumnya. Kalau tidak ada
    -- pergerakan sebelumnya sama sekali, turunkan dari saldo sesudah.
    COALESCE(c.prev_after, COALESCE(c.next_before, c.current_stock) - c.quantity) AS before_val
  FROM ctx c
)
SELECT
  return_number,
  product_name,
  quantity                       AS qty_retur,
  approx_at::date                AS perkiraan_tanggal,
  before_val                     AS saldo_sebelum,
  after_val                      AS saldo_sesudah,
  (after_val - before_val)       AS lompatan_terdeteksi,
  (after_val - before_val) = quantity AS aman,
  CASE
    WHEN (after_val - before_val) = quantity THEN 'Siap ditambal otomatis'
    WHEN (after_val - before_val) IS NULL     THEN 'Produk sudah dihapus — perlu dicek manual'
    ELSE 'Lompatan tidak cocok dengan qty — perlu dicek manual'
  END                            AS keterangan
FROM calc
ORDER BY aman DESC NULLS LAST, approx_at;


-- ============================================================
-- LANGKAH 2 — TAMBAL (baru jalankan setelah LANGKAH 1 dibaca)
-- ============================================================
-- Hanya menulis baris yang lompatannya persis sama dengan qty retur.
-- Aman diulang: baris yang sudah ditambal tidak akan ketangkap lagi oleh
-- filter NOT EXISTS di atas, jadi tidak akan dobel.

INSERT INTO stock_movements
  (product_id, product_name, type, quantity, quantity_before, quantity_after,
   reference_type, reference_id, notes, created_at)
SELECT
  c.product_id,
  c.product_name,
  'in',
  c.quantity,
  c.before_val,
  c.after_val,
  'return_approve',
  c.return_id,
  'Retur disetujui: ' || c.return_number || ' (dicatat ulang — riwayat sempat hilang, lihat migration32)',
  c.approx_at
FROM (
  WITH missing AS (
    SELECT
      r.id AS return_id, r.return_number, r.created_at AS approx_at,
      ri.product_id, ri.product_name, ri.quantity::int AS quantity
    FROM returns r
    JOIN return_items ri ON ri.return_id = r.id
    WHERE r.status = 'approved'
      AND ri.product_id IS NOT NULL
      AND ri.quantity > 0
      AND NOT EXISTS (
        SELECT 1 FROM stock_movements sm
        WHERE sm.product_id = ri.product_id
          AND (
               (sm.reference_type = 'return_approve' AND sm.reference_id = r.id)
            OR (r.return_number IS NOT NULL AND sm.notes LIKE '%' || r.return_number || '%')
          )
      )
  ),
  ctx AS (
    SELECT
      m.*,
      prev.quantity_after AS prev_after,
      nxt.quantity_before AS next_before,
      pr.stock_quantity   AS current_stock
    FROM missing m
    LEFT JOIN LATERAL (
      SELECT sm.quantity_after FROM stock_movements sm
      WHERE sm.product_id = m.product_id AND sm.created_at <= m.approx_at
      ORDER BY sm.created_at DESC, sm.id DESC LIMIT 1
    ) prev ON true
    LEFT JOIN LATERAL (
      SELECT sm.quantity_before FROM stock_movements sm
      WHERE sm.product_id = m.product_id AND sm.created_at > m.approx_at
      ORDER BY sm.created_at ASC, sm.id ASC LIMIT 1
    ) nxt ON true
    LEFT JOIN products pr ON pr.id = m.product_id
  )
  SELECT
    ctx.*,
    COALESCE(ctx.next_before, ctx.current_stock) AS after_val,
    COALESCE(ctx.prev_after, COALESCE(ctx.next_before, ctx.current_stock) - ctx.quantity) AS before_val
  FROM ctx
) c
WHERE (c.after_val - c.before_val) = c.quantity;


-- ============================================================
-- LANGKAH 3 — VERIFIKASI
-- ============================================================
-- (a) Harus 0 baris, atau tersisa hanya yang di LANGKAH 1 sudah ditandai
--     "perlu dicek manual".
SELECT count(*) AS retur_masih_tanpa_riwayat
FROM returns r
JOIN return_items ri ON ri.return_id = r.id
WHERE r.status = 'approved'
  AND ri.product_id IS NOT NULL
  AND ri.quantity > 0
  AND NOT EXISTS (
    SELECT 1 FROM stock_movements sm
    WHERE sm.product_id = ri.product_id
      AND (
           (sm.reference_type = 'return_approve' AND sm.reference_id = r.id)
        OR (r.return_number IS NOT NULL AND sm.notes LIKE '%' || r.return_number || '%')
      )
  );

-- (b) Rantai buku besar harus nyambung: quantity_before tiap pergerakan sama
--     dengan quantity_after pergerakan sebelumnya. Baris yang muncul di sini
--     adalah sisa selisih dari sebab LAIN (lihat F-01/F-02 soal import CSV).
WITH m AS (
  SELECT product_id, product_name, created_at, id, type, quantity,
         quantity_before, quantity_after, reference_type, notes,
         lag(quantity_after) OVER (PARTITION BY product_id ORDER BY created_at, id) AS prev_after
  FROM stock_movements
)
SELECT product_name, created_at, type, quantity,
       prev_after AS saldo_sebelumnya, quantity_before AS tercatat_sebagai,
       quantity_before - prev_after AS selisih, reference_type, notes
FROM m
WHERE prev_after IS NOT NULL AND prev_after <> quantity_before
ORDER BY created_at DESC
LIMIT 200;
