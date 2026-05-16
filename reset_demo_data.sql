-- ============================================================
-- RESET DATA DEMO — mulai dari 0
-- Jalankan di Supabase SQL Editor
--
-- YANG DIHAPUS : semua data transaksi & master data
-- YANG DIPERTAHANKAN : user_profiles, app_settings
-- ============================================================

-- Hapus dari tabel paling dalam (child) ke luar (parent)
-- CASCADE otomatis handle foreign key dependency

TRUNCATE TABLE
  wishlist_items,
  return_items,
  returns,
  stock_transfer_items,
  stock_transfers,
  purchase_items,
  purchases,
  invoice_items,
  stock_movements,
  invoices,
  sales_targets,
  customers,
  products,
  categories
CASCADE;

-- Verifikasi semua kosong
SELECT 'categories'       AS tabel, COUNT(*) AS sisa FROM categories
UNION ALL
SELECT 'products',          COUNT(*) FROM products
UNION ALL
SELECT 'customers',         COUNT(*) FROM customers
UNION ALL
SELECT 'invoices',          COUNT(*) FROM invoices
UNION ALL
SELECT 'invoice_items',     COUNT(*) FROM invoice_items
UNION ALL
SELECT 'purchases',         COUNT(*) FROM purchases
UNION ALL
SELECT 'stock_movements',   COUNT(*) FROM stock_movements
UNION ALL
SELECT 'returns',           COUNT(*) FROM returns
UNION ALL
SELECT 'wishlist_items',    COUNT(*) FROM wishlist_items
UNION ALL
SELECT 'sales_targets',     COUNT(*) FROM sales_targets
ORDER BY tabel;
