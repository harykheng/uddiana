-- Migration 22: Fix race condition di auto-generate return_number
-- retur.html generateReturnNumber() masih hitung nomor di client (rawan collision
-- kalau 2 retur diajukan hampir bersamaan) — pola sama dengan masalah invoice_number/
-- purchase_number/transfer_number yang sudah diperbaiki sebelumnya (migration10 & 20).
-- Sekarang dipindah ke trigger DB dengan counter atomik, reuse tabel doc_counters
-- dari migration20 (kolom year_month dipakai generik untuk nyimpan key 'YYYYMMDD'
-- di sini, bukan cuma 'YYMM').
-- Jalankan di Supabase SQL Editor

-- 1. Pastikan kolom return_number punya default '' supaya trigger bisa isi otomatis
--    kalau tidak dikirim dari client
ALTER TABLE returns ALTER COLUMN return_number SET DEFAULT '';

-- 2. Isi counter dari data yang sudah ada per hari (format RTR-YYYYMMDD-XXX),
--    supaya nomor berikutnya tidak konflik dengan yang sudah ada
INSERT INTO doc_counters (doc_type, year_month, last_count)
SELECT
  'return',
  SUBSTRING(return_number FROM 5 FOR 8) AS year_month,
  MAX(CAST(SUBSTRING(return_number FROM 14) AS INTEGER)) AS last_count
FROM returns
WHERE return_number ~ '^RTR-[0-9]{8}-[0-9]+$'
GROUP BY SUBSTRING(return_number FROM 5 FOR 8)
ON CONFLICT (doc_type, year_month) DO UPDATE
  SET last_count = GREATEST(doc_counters.last_count, EXCLUDED.last_count);

-- 3. Fungsi trigger generate return_number yang aman dari race condition
CREATE OR REPLACE FUNCTION generate_return_number()
RETURNS TRIGGER AS $$
DECLARE
  v_day  TEXT;
  v_next INTEGER;
BEGIN
  IF NEW.return_number IS NOT NULL AND NEW.return_number <> '' THEN
    RETURN NEW;
  END IF;

  v_day := TO_CHAR(NOW() AT TIME ZONE 'Asia/Jakarta', 'YYYYMMDD');

  INSERT INTO doc_counters (doc_type, year_month, last_count)
  VALUES ('return', v_day, 1)
  ON CONFLICT (doc_type, year_month) DO UPDATE
    SET last_count = doc_counters.last_count + 1
  RETURNING last_count INTO v_next;

  NEW.return_number := 'RTR-' || v_day || '-' || LPAD(v_next::TEXT, 3, '0');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Trigger — hanya generate kalau return_number belum diisi
DROP TRIGGER IF EXISTS trg_generate_return_number ON returns;
CREATE TRIGGER trg_generate_return_number
  BEFORE INSERT ON returns
  FOR EACH ROW
  EXECUTE FUNCTION generate_return_number();
