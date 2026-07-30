-- Migration 20: Fix race condition di auto-generate purchase_number & transfer_number
-- Pola sama seperti migration10.sql yang sudah menutup celah ini untuk invoice_number,
-- direplikasi ke sini karena PO & transfer masih pakai pendekatan COUNT(*)+1 yang rawan
-- collision kalau 2 user submit hampir bersamaan.
-- Jalankan di Supabase SQL Editor

-- 1. Tabel counter generik per jenis dokumen + bulan (YY+MM)
CREATE TABLE IF NOT EXISTS doc_counters (
  doc_type    TEXT    NOT NULL,   -- 'purchase' | 'transfer'
  year_month  TEXT    NOT NULL,   -- contoh: '2606' untuk Juni 2026
  last_count  INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (doc_type, year_month)
);
ALTER TABLE doc_counters ENABLE ROW LEVEL SECURITY;
CREATE POLICY "authenticated_all" ON doc_counters
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 2. Isi counter dari data yang sudah ada (agar nomor berikutnya tidak konflik)
INSERT INTO doc_counters (doc_type, year_month, last_count)
SELECT
  'purchase',
  SUBSTRING(purchase_number FROM 4 FOR 4) AS year_month,
  MAX(CAST(SUBSTRING(purchase_number FROM 9) AS INTEGER)) AS last_count
FROM purchases
WHERE purchase_number ~ '^PO-[0-9]{4}-[0-9]+$'
GROUP BY SUBSTRING(purchase_number FROM 4 FOR 4)
ON CONFLICT (doc_type, year_month) DO UPDATE
  SET last_count = GREATEST(doc_counters.last_count, EXCLUDED.last_count);

INSERT INTO doc_counters (doc_type, year_month, last_count)
SELECT
  'transfer',
  SUBSTRING(transfer_number FROM 5 FOR 4) AS year_month,
  MAX(CAST(SUBSTRING(transfer_number FROM 10) AS INTEGER)) AS last_count
FROM stock_transfers
WHERE transfer_number ~ '^OUT-[0-9]{4}-[0-9]+$'
GROUP BY SUBSTRING(transfer_number FROM 5 FOR 4)
ON CONFLICT (doc_type, year_month) DO UPDATE
  SET last_count = GREATEST(doc_counters.last_count, EXCLUDED.last_count);

-- 3. Fungsi trigger yang aman dari race condition — purchase_number
CREATE OR REPLACE FUNCTION generate_purchase_number()
RETURNS TRIGGER AS $$
DECLARE
  v_ym   TEXT;
  v_next INTEGER;
BEGIN
  IF NEW.purchase_number IS NOT NULL AND NEW.purchase_number <> '' THEN
    RETURN NEW;
  END IF;

  v_ym := TO_CHAR(NOW() AT TIME ZONE 'Asia/Jakarta', 'YYMM');

  INSERT INTO doc_counters (doc_type, year_month, last_count)
  VALUES ('purchase', v_ym, 1)
  ON CONFLICT (doc_type, year_month) DO UPDATE
    SET last_count = doc_counters.last_count + 1
  RETURNING last_count INTO v_next;

  NEW.purchase_number := 'PO-' || v_ym || '-' || LPAD(v_next::TEXT, 4, '0');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Fungsi trigger yang aman dari race condition — transfer_number
CREATE OR REPLACE FUNCTION generate_transfer_number()
RETURNS TRIGGER AS $$
DECLARE
  v_ym   TEXT;
  v_next INTEGER;
BEGIN
  IF NEW.transfer_number IS NOT NULL AND NEW.transfer_number <> '' THEN
    RETURN NEW;
  END IF;

  v_ym := TO_CHAR(NOW() AT TIME ZONE 'Asia/Jakarta', 'YYMM');

  INSERT INTO doc_counters (doc_type, year_month, last_count)
  VALUES ('transfer', v_ym, 1)
  ON CONFLICT (doc_type, year_month) DO UPDATE
    SET last_count = doc_counters.last_count + 1
  RETURNING last_count INTO v_next;

  NEW.transfer_number := 'OUT-' || v_ym || '-' || LPAD(v_next::TEXT, 4, '0');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Trigger tetap dengan nama yang sama (fungsi sudah di-CREATE OR REPLACE di atas,
--    jadi trigger existing otomatis pakai versi baru — tidak perlu drop/recreate trigger)
