-- ============================================================
-- Migration 47: Riwayat pembayaran faktur + batalkan pembayaran
-- ============================================================
-- Sebelumnya pembayaran cuma disimpan sebagai angka kumulatif di invoices
-- (paid_amount, cash_paid, transfer_paid) dan tanggal/metode/catatan
-- pembayaran TERAKHIR. Tiap pembayaran menimpa jejak pembayaran sebelumnya,
-- jadi pelunasan yang salah klik tidak bisa dikembalikan tanpa tahu sendiri
-- berapa cicilan sebelumnya.
--
--   1. Tabel invoice_payments: 1 baris per pembayaran (cicilan/pelunasan).
--      Dibatalkan = ditandai voided_at, BUKAN dihapus, supaya tetap ada jejak.
--   2. recalc_invoice_payment(): hitung ulang kolom pembayaran di invoices
--      dari baris yang belum dibatalkan. invoices tetap jadi sumber yang dibaca
--      laporan (piutang, laba rugi, dst.), jadi halaman lain tidak perlu diubah.
--   3. record_invoice_payment(): SATU-SATUNYA jalan mencatat pembayaran, dipakai
--      invoices.html, piutang.html, verify-invoices.html. Sisa tagihan dihitung
--      di sini: total - retur approved - sudah dibayar (sebelumnya piutang.html
--      dan verify-invoices.html lupa mengurangi retur).
--   4. void_invoice_payment(): batalkan satu pembayaran (super_admin saja).
--   5. Backfill: faktur yang sudah ada pembayarannya dapat baris 'backfill'
--      (gabungan per metode — rincian cicilan lamanya memang sudah tidak ada).
--
-- Jalankan setelah migration43 (memakai current_app_role()).
-- Aman dijalankan ulang.
-- ============================================================

CREATE TABLE IF NOT EXISTS invoice_payments (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id      uuid NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
  amount          numeric(15,2) NOT NULL CHECK (amount > 0),
  method          text NOT NULL CHECK (method IN ('cash', 'transfer')),
  payment_date    date NOT NULL,
  notes           text,
  -- invoices | piutang | verify | backfill
  source          text NOT NULL DEFAULT 'invoices',
  created_by_id   uuid,
  created_by_name text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  voided_at       timestamptz,
  voided_by_id    uuid,
  voided_by_name  text,
  void_reason     text
);

CREATE INDEX IF NOT EXISTS idx_invoice_payments_invoice ON invoice_payments(invoice_id);

-- Baca: admin + super_admin. Tulis: cuma lewat fungsi di bawah (SECURITY DEFINER),
-- jadi angka di invoices dan riwayat tidak bisa jalan sendiri-sendiri.
ALTER TABLE invoice_payments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admin read invoice payments" ON invoice_payments;
CREATE POLICY "Admin read invoice payments" ON invoice_payments
  FOR SELECT TO authenticated
  USING (current_app_role() IN ('admin', 'super_admin'));

-- ── Hitung ulang kolom pembayaran faktur dari riwayat ───────────────────────
CREATE OR REPLACE FUNCTION recalc_invoice_payment(p_invoice_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total    numeric;
  v_status   text;
  v_retur    numeric;
  v_cash     numeric;
  v_transfer numeric;
  v_last     invoice_payments%ROWTYPE;
BEGIN
  SELECT total, status INTO v_total, v_status FROM invoices WHERE id = p_invoice_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Faktur tidak ditemukan'; END IF;

  SELECT coalesce(sum(total_return_value), 0) INTO v_retur
  FROM returns WHERE invoice_id = p_invoice_id AND status = 'approved';

  SELECT coalesce(sum(amount) FILTER (WHERE method = 'cash'), 0),
         coalesce(sum(amount) FILTER (WHERE method = 'transfer'), 0)
    INTO v_cash, v_transfer
  FROM invoice_payments
  WHERE invoice_id = p_invoice_id AND voided_at IS NULL;

  SELECT * INTO v_last
  FROM invoice_payments
  WHERE invoice_id = p_invoice_id AND voided_at IS NULL
  ORDER BY payment_date DESC, created_at DESC
  LIMIT 1;

  UPDATE invoices SET
    paid_amount    = v_cash + v_transfer,
    cash_paid      = v_cash,
    transfer_paid  = v_transfer,
    payment_method = v_last.method,
    payment_date   = v_last.payment_date,
    payment_notes  = v_last.notes,
    -- faktur batal tidak disentuh statusnya
    status = CASE
      WHEN v_status = 'cancelled' THEN v_status
      WHEN v_cash + v_transfer > 0 AND v_cash + v_transfer >= v_total - v_retur THEN 'paid'
      ELSE 'pending'
    END
  WHERE id = p_invoice_id;
END;
$$;

REVOKE ALL ON FUNCTION recalc_invoice_payment(uuid) FROM public, authenticated;

-- ── Catat pembayaran ────────────────────────────────────────────────────────
-- p_amount NULL = lunasi seluruh sisa (dipakai piutang.html).
-- p_clear_claim = kosongkan klaim bayar dari sales (verify-invoices.html).
CREATE OR REPLACE FUNCTION record_invoice_payment(
  p_invoice_id  uuid,
  p_amount      numeric,
  p_method      text,
  p_date        date DEFAULT NULL,
  p_notes       text DEFAULT NULL,
  p_source      text DEFAULT 'invoices',
  p_clear_claim boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inv    invoices%ROWTYPE;
  v_retur  numeric;
  v_sisa   numeric;
  v_amount numeric;
  v_name   text;
BEGIN
  IF coalesce(current_app_role(), '') NOT IN ('admin', 'super_admin') THEN
    RAISE EXCEPTION 'Hanya admin yang bisa mencatat pembayaran';
  END IF;
  IF p_method NOT IN ('cash', 'transfer') THEN
    RAISE EXCEPTION 'Metode pembayaran tidak dikenal: %', p_method;
  END IF;

  -- Kunci baris faktur: dua admin melunasi faktur yang sama bersamaan
  -- tidak boleh sama-sama lolos.
  SELECT * INTO v_inv FROM invoices WHERE id = p_invoice_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Faktur tidak ditemukan'; END IF;
  IF v_inv.status = 'cancelled' THEN RAISE EXCEPTION 'Faktur % sudah dibatalkan', v_inv.invoice_number; END IF;
  IF v_inv.status = 'paid' THEN RAISE EXCEPTION 'Faktur % sudah lunas', v_inv.invoice_number; END IF;

  PERFORM sync_invoice_payment_rows(p_invoice_id);

  SELECT coalesce(sum(total_return_value), 0) INTO v_retur
  FROM returns WHERE invoice_id = p_invoice_id AND status = 'approved';

  v_sisa   := v_inv.total - v_retur - coalesce(v_inv.paid_amount, 0);
  v_amount := coalesce(p_amount, v_sisa);
  IF v_amount IS NULL OR v_amount <= 0 THEN
    RAISE EXCEPTION 'Jumlah pembayaran harus lebih dari 0 (sisa tagihan %)', v_sisa;
  END IF;

  SELECT name INTO v_name FROM user_profiles WHERE id = auth.uid();

  INSERT INTO invoice_payments (invoice_id, amount, method, payment_date, notes, source, created_by_id, created_by_name)
  VALUES (p_invoice_id, v_amount, p_method, coalesce(p_date, (now() AT TIME ZONE 'Asia/Jakarta')::date),
          nullif(btrim(coalesce(p_notes, '')), ''), coalesce(p_source, 'invoices'), auth.uid(), v_name);

  PERFORM recalc_invoice_payment(p_invoice_id);

  IF p_clear_claim THEN
    UPDATE invoices SET
      payment_claimed_at = NULL, payment_claimed_date = NULL, payment_claimed_amount = NULL,
      payment_claimed_method = NULL, payment_claimed_by_name = NULL, payment_claimed_note = NULL
    WHERE id = p_invoice_id;
  END IF;

  SELECT * INTO v_inv FROM invoices WHERE id = p_invoice_id;
  RETURN jsonb_build_object(
    'amount', v_amount,
    'lunas',  v_inv.status = 'paid',
    'sisa',   greatest(0, v_inv.total - v_retur - v_inv.paid_amount)
  );
END;
$$;

REVOKE ALL ON FUNCTION record_invoice_payment(uuid, numeric, text, date, text, text, boolean) FROM public;
GRANT EXECUTE ON FUNCTION record_invoice_payment(uuid, numeric, text, date, text, text, boolean) TO authenticated;

-- ── Batalkan satu pembayaran (super_admin) ──────────────────────────────────
CREATE OR REPLACE FUNCTION void_invoice_payment(p_payment_id uuid, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pay  invoice_payments%ROWTYPE;
  v_inv  invoices%ROWTYPE;
  v_name text;
BEGIN
  IF coalesce(current_app_role(), '') <> 'super_admin' THEN
    RAISE EXCEPTION 'Hanya super admin yang bisa membatalkan pembayaran';
  END IF;
  IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Alasan pembatalan wajib diisi';
  END IF;

  SELECT * INTO v_pay FROM invoice_payments WHERE id = p_payment_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Pembayaran tidak ditemukan'; END IF;

  SELECT * INTO v_inv FROM invoices WHERE id = v_pay.invoice_id FOR UPDATE;
  IF v_inv.status = 'cancelled' THEN RAISE EXCEPTION 'Faktur % sudah dibatalkan', v_inv.invoice_number; END IF;

  -- Baca ulang setelah faktur dikunci: bisa saja sudah dibatalkan di tab lain.
  SELECT * INTO v_pay FROM invoice_payments WHERE id = p_payment_id;
  IF v_pay.voided_at IS NOT NULL THEN RAISE EXCEPTION 'Pembayaran ini sudah dibatalkan'; END IF;

  PERFORM sync_invoice_payment_rows(v_pay.invoice_id);

  SELECT name INTO v_name FROM user_profiles WHERE id = auth.uid();

  UPDATE invoice_payments SET
    voided_at = now(), voided_by_id = auth.uid(), voided_by_name = v_name,
    void_reason = btrim(p_reason)
  WHERE id = p_payment_id;

  PERFORM recalc_invoice_payment(v_pay.invoice_id);

  SELECT * INTO v_inv FROM invoices WHERE id = v_pay.invoice_id;
  RETURN jsonb_build_object('status', v_inv.status, 'paid_amount', v_inv.paid_amount);
END;
$$;

REVOKE ALL ON FUNCTION void_invoice_payment(uuid, text) FROM public;
GRANT EXECUTE ON FUNCTION void_invoice_payment(uuid, text) TO authenticated;

-- ── Selaraskan riwayat dengan angka di invoices ─────────────────────────────
-- Pembayaran yang tercatat di invoices tapi belum ada di riwayat (pembayaran
-- sebelum migration ini, atau angka yang diubah langsung lewat SQL Editor)
-- dibuatkan baris 'backfill' sebesar selisihnya, per metode.
-- Kalau riwayat justru LEBIH BESAR dari angka di faktur (faktur dikurangi
-- manual lewat SQL), ditolak: tidak bisa ditebak pembayaran mana yang sah.
-- Dipanggil di awal record/void, jadi riwayat selalu cocok sebelum dihitung ulang.
CREATE OR REPLACE FUNCTION sync_invoice_payment_rows(p_invoice_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inv       invoices%ROWTYPE;
  v_remainder numeric;
  v_want_cash numeric;
  v_want_tf   numeric;
  v_have_cash numeric;
  v_have_tf   numeric;
  v_date      date;
BEGIN
  SELECT * INTO v_inv FROM invoices WHERE id = p_invoice_id;
  IF NOT FOUND THEN RETURN; END IF;

  v_want_cash := coalesce(v_inv.cash_paid, 0);
  v_want_tf   := coalesce(v_inv.transfer_paid, 0);
  -- Faktur sangat lama (sebelum migration6): paid_amount belum dipecah per metode.
  v_remainder := coalesce(v_inv.paid_amount, 0) - v_want_cash - v_want_tf;
  IF v_remainder > 0 THEN
    IF v_inv.payment_method = 'transfer' THEN v_want_tf := v_want_tf + v_remainder;
    ELSE v_want_cash := v_want_cash + v_remainder; END IF;
  END IF;

  SELECT coalesce(sum(amount) FILTER (WHERE method = 'cash'), 0),
         coalesce(sum(amount) FILTER (WHERE method = 'transfer'), 0)
    INTO v_have_cash, v_have_tf
  FROM invoice_payments
  WHERE invoice_id = p_invoice_id AND voided_at IS NULL;

  IF v_have_cash > v_want_cash OR v_have_tf > v_want_tf THEN
    RAISE EXCEPTION 'Riwayat pembayaran faktur % tidak cocok dengan data faktur (kemungkinan diubah langsung lewat SQL). Cocokkan dulu sebelum mencatat/membatalkan pembayaran.', v_inv.invoice_number;
  END IF;

  v_date := coalesce(v_inv.payment_date, v_inv.invoice_date, (now() AT TIME ZONE 'Asia/Jakarta')::date);

  IF v_want_cash > v_have_cash THEN
    INSERT INTO invoice_payments (invoice_id, amount, method, payment_date, notes, source, created_at)
    VALUES (p_invoice_id, v_want_cash - v_have_cash, 'cash', v_date, v_inv.payment_notes, 'backfill',
            coalesce(v_inv.updated_at, v_inv.created_at, now()));
  END IF;
  IF v_want_tf > v_have_tf THEN
    INSERT INTO invoice_payments (invoice_id, amount, method, payment_date, notes, source, created_at)
    VALUES (p_invoice_id, v_want_tf - v_have_tf, 'transfer', v_date, v_inv.payment_notes, 'backfill',
            coalesce(v_inv.updated_at, v_inv.created_at, now()));
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION sync_invoice_payment_rows(uuid) FROM public, authenticated;

-- ── Backfill pembayaran yang sudah ada ──────────────────────────────────────
-- Rincian per cicilan sudah tidak ada, jadi dibuat 1 baris per metode.
-- Kolom di invoices TIDAK dihitung ulang di sini, supaya laporan lama tidak
-- berubah. Aman dijalankan ulang (yang sudah cocok tidak ditambah lagi).
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT id FROM invoices WHERE coalesce(paid_amount, 0) > 0
                                     AND NOT EXISTS (SELECT 1 FROM invoice_payments p WHERE p.invoice_id = invoices.id)
  LOOP
    PERFORM sync_invoice_payment_rows(r.id);
  END LOOP;
END $$;
