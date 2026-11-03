-- ============================================================
-- Migration 44: Foto faktur supplier di Pembelian/Masuk Barang
-- ============================================================
-- Admin bisa melampirkan beberapa foto (faktur / nota / surat jalan supplier)
-- saat input pembelian di purchases.html, dan menambah/menghapusnya lagi dari
-- modal Detail PO.
--
--   1. Kolom purchases.photo_paths (array path di bucket purchase-photos)
--   2. Bucket privat purchase-photos (dibuka lewat signed URL)
--
-- Jalankan setelah migration43 (memakai fungsi current_app_role()).
-- Aman dijalankan ulang.
-- ============================================================

ALTER TABLE purchases ADD COLUMN IF NOT EXISTS photo_paths text[] NOT NULL DEFAULT '{}';

-- Foto dikecilkan dulu di browser (maks 1600px, webp/jpeg). Lebih besar dari
-- foto retur (1200px) karena tulisan di faktur harus tetap terbaca. Batas 2 MB
-- cuma pengaman kuota Supabase gratis.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('purchase-photos', 'purchase-photos', false, 2097152, ARRAY['image/webp', 'image/jpeg'])
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Admin upload purchase photos" ON storage.objects;
CREATE POLICY "Admin upload purchase photos" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'purchase-photos' AND current_app_role() IN ('admin', 'super_admin'));

DROP POLICY IF EXISTS "Admin read purchase photos" ON storage.objects;
CREATE POLICY "Admin read purchase photos" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'purchase-photos' AND current_app_role() IN ('admin', 'super_admin'));

-- Dipakai saat foto dihapus dari Detail PO, saat PO dihapus, dan untuk
-- membersihkan foto yang terlanjur terunggah kalau simpan PO gagal.
DROP POLICY IF EXISTS "Admin delete purchase photos" ON storage.objects;
CREATE POLICY "Admin delete purchase photos" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'purchase-photos' AND current_app_role() IN ('admin', 'super_admin'));
