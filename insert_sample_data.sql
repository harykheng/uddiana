-- ============================================================
-- Jalankan query ini di Supabase SQL Editor
-- jika tabel sudah ada tapi data masih kosong
-- ============================================================

INSERT INTO categories (name) VALUES
  ('Elektronik'),
  ('Pakaian'),
  ('Makanan & Minuman'),
  ('Alat Tulis'),
  ('Peralatan Rumah')
ON CONFLICT (name) DO NOTHING;

INSERT INTO products (name, sku, category_id, price, cost, stock_quantity, min_stock, unit) VALUES
  ('Laptop ASUS VivoBook 14',  'ELEC-001', (SELECT id FROM categories WHERE name = 'Elektronik'),        8500000, 7000000, 15, 3, 'unit'),
  ('Mouse Wireless Logitech',  'ELEC-002', (SELECT id FROM categories WHERE name = 'Elektronik'),         250000,  180000, 50, 10, 'unit'),
  ('Keyboard Mechanical',      'ELEC-003', (SELECT id FROM categories WHERE name = 'Elektronik'),         650000,  500000, 25,  5, 'unit'),
  ('Headset Gaming Rexus',     'ELEC-004', (SELECT id FROM categories WHERE name = 'Elektronik'),         350000,  240000,  8,  5, 'unit'),
  ('Kaos Polos Putih',         'CLO-001',  (SELECT id FROM categories WHERE name = 'Pakaian'),             75000,   45000,100, 20, 'pcs'),
  ('Celana Jeans Slim',        'CLO-002',  (SELECT id FROM categories WHERE name = 'Pakaian'),            250000,  150000, 60, 15, 'pcs'),
  ('Jaket Hoodie',             'CLO-003',  (SELECT id FROM categories WHERE name = 'Pakaian'),            185000,  110000,  4, 10, 'pcs'),
  ('Kopi Arabica 250gr',       'FNB-001',  (SELECT id FROM categories WHERE name = 'Makanan & Minuman'),  85000,   55000,200, 50, 'pack'),
  ('Teh Hijau Premium',        'FNB-002',  (SELECT id FROM categories WHERE name = 'Makanan & Minuman'),  45000,   28000,150, 30, 'pack'),
  ('Pulpen Pilot G2 0.5',      'STA-001',  (SELECT id FROM categories WHERE name = 'Alat Tulis'),          8000,    4000,500,100, 'pcs'),
  ('Buku Tulis A5 100lbr',     'STA-002',  (SELECT id FROM categories WHERE name = 'Alat Tulis'),         15000,    8000,300, 50, 'pcs'),
  ('Sapu Lantai Standar',      'HOU-001',  (SELECT id FROM categories WHERE name = 'Peralatan Rumah'),    35000,   20000, 80, 20, 'pcs')
ON CONFLICT (sku) DO NOTHING;
