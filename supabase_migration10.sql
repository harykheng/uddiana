-- Migration 10: Fix race condition di auto-generate invoice_number
-- Ganti pendekatan MAX+1 (tidak aman) dengan tabel counter + atomic increment
-- Jalankan di Supabase SQL Editor

-- 1. Tabel counter per bulan (YY+MM)
CREATE TABLE IF NOT EXISTS invoice_counters (
  year_month  TEXT    PRIMARY KEY,   -- contoh: '2606' untuk Juni 2026
  last_count  INTEGER NOT NULL DEFAULT 0
);
ALTER TABLE invoice_counters ENABLE ROW LEVEL SECURITY;
CREATE POLICY "authenticated_all" ON invoice_counters
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 2. Isi counter dari data yang sudah ada (agar nomor berikutnya tidak konflik)
INSERT INTO invoice_counters (year_month, last_count)
SELECT
  SUBSTRING(invoice_number FROM 5 FOR 4) AS year_month,
  MAX(CAST(SUBSTRING(invoice_number FROM 10) AS INTEGER)) AS last_count
FROM invoices
WHERE invoice_number ~ '^INV-[0-9]{4}-[0-9]+$'
GROUP BY SUBSTRING(invoice_number FROM 5 FOR 4)
ON CONFLICT (year_month) DO UPDATE
  SET last_count = GREATEST(invoice_counters.last_count, EXCLUDED.last_count);

-- 3. Fungsi trigger yang aman dari race condition
CREATE OR REPLACE FUNCTION generate_invoice_number()
RETURNS TRIGGER AS $$
DECLARE
  v_ym        TEXT;
  v_next      INTEGER;
BEGIN
  -- Hanya generate jika invoice_number belum diisi
  IF NEW.invoice_number IS NOT NULL AND NEW.invoice_number <> '' THEN
    RETURN NEW;
  END IF;

  v_ym := TO_CHAR(NOW() AT TIME ZONE 'Asia/Jakarta', 'YYMM');

  -- Atomic increment: INSERT baru atau UPDATE existing — menghindari race condition
  INSERT INTO invoice_counters (year_month, last_count)
  VALUES (v_ym, 1)
  ON CONFLICT (year_month) DO UPDATE
    SET last_count = invoice_counters.last_count + 1
  RETURNING last_count INTO v_next;

  NEW.invoice_number := 'INV-' || v_ym || '-' || LPAD(v_next::TEXT, 4, '0');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Drop trigger lama (coba beberapa nama yang mungkin dipakai)
DROP TRIGGER IF EXISTS trg_generate_invoice_number   ON invoices;
DROP TRIGGER IF EXISTS trg_invoice_number            ON invoices;
DROP TRIGGER IF EXISTS generate_invoice_number_trg   ON invoices;
DROP TRIGGER IF EXISTS set_invoice_number            ON invoices;
DROP TRIGGER IF EXISTS before_insert_invoice         ON invoices;

-- 5. Buat trigger baru dengan fungsi yang sudah diperbaiki
CREATE TRIGGER trg_generate_invoice_number
  BEFORE INSERT ON invoices
  FOR EACH ROW
  EXECUTE FUNCTION generate_invoice_number();
