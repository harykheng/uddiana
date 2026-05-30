-- ============================================================
-- MIGRATION 6: Track pembayaran per metode (cash vs transfer)
-- Jalankan di Supabase SQL Editor
-- ============================================================

-- Tambah kolom cash_paid dan transfer_paid ke tabel invoices
alter table invoices add column if not exists cash_paid     numeric default 0;
alter table invoices add column if not exists transfer_paid numeric default 0;

-- Backfill data lama: invoice yang sudah paid/lunas, isi cash_paid/transfer_paid
-- berdasarkan payment_method yang sudah ada
update invoices
set cash_paid     = total
where status = 'paid'
  and payment_method = 'cash'
  and cash_paid = 0
  and transfer_paid = 0;

update invoices
set transfer_paid = total
where status = 'paid'
  and payment_method = 'transfer'
  and cash_paid = 0
  and transfer_paid = 0;

-- Verifikasi
select
  status,
  payment_method,
  count(*) as jumlah,
  sum(total) as total_amount,
  sum(cash_paid) as total_cash,
  sum(transfer_paid) as total_transfer
from invoices
where status = 'paid'
group by status, payment_method
order by payment_method;
