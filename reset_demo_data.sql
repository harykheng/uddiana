-- ============================================================
-- RESET DATA — bersih total, siap data asli
-- Jalankan di Supabase → SQL Editor
--
-- YANG DIHAPUS  : semua transaksi, produk, customer, kategori
-- YANG DIPERTAHANKAN : user_profiles (akun login), app_settings
-- ============================================================

-- Hapus dari child ke parent agar tidak ada FK conflict
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
RESTART IDENTITY CASCADE;

-- ============================================================
-- CATATAN: Akun login (user_profiles + Supabase Auth) TIDAK
-- dihapus. Kalau ingin hapus user juga, lakukan manual di:
-- Supabase Dashboard → Authentication → Users
-- ============================================================

-- Verifikasi semua kosong
SELECT 'categories'             AS tabel, COUNT(*) AS sisa FROM categories
UNION ALL SELECT 'products',               COUNT(*) FROM products
UNION ALL SELECT 'customers',              COUNT(*) FROM customers
UNION ALL SELECT 'invoices',               COUNT(*) FROM invoices
UNION ALL SELECT 'invoice_items',          COUNT(*) FROM invoice_items
UNION ALL SELECT 'stock_movements',        COUNT(*) FROM stock_movements
UNION ALL SELECT 'purchases',              COUNT(*) FROM purchases
UNION ALL SELECT 'purchase_items',         COUNT(*) FROM purchase_items
UNION ALL SELECT 'stock_transfers',        COUNT(*) FROM stock_transfers
UNION ALL SELECT 'stock_transfer_items',   COUNT(*) FROM stock_transfer_items
UNION ALL SELECT 'returns',                COUNT(*) FROM returns
UNION ALL SELECT 'return_items',           COUNT(*) FROM return_items
UNION ALL SELECT 'wishlist_items',         COUNT(*) FROM wishlist_items
UNION ALL SELECT 'sales_targets',          COUNT(*) FROM sales_targets
ORDER BY tabel;
