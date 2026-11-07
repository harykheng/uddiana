-- ============================================================
-- Migration 48: Lampiran PDF di Faktur Supplier (purchases.html)
-- ============================================================
-- Faktur supplier kadang dikirim dalam bentuk PDF, bukan foto. Bucket
-- purchase-photos (migration44) cuma menerima webp/jpeg 2 MB, jadi PDF
-- ditolak. Migration ini:
--   1. Menambah application/pdf ke tipe file yang boleh diunggah
--   2. Menaikkan batas ukuran per file jadi 5 MB — PDF tidak bisa dikecilkan
--      di browser seperti foto (foto tetap dikecilkan, jadi tetap kecil)
--
-- Path PDF disimpan di kolom yang sama (purchases.photo_paths), berakhiran
-- .pdf. Policy baca/tulis/hapus tidak berubah (admin + super_admin).
-- Jalankan setelah migration44. Aman dijalankan ulang.
-- ============================================================

UPDATE storage.buckets
SET allowed_mime_types = ARRAY['image/webp', 'image/jpeg', 'application/pdf'],
    file_size_limit    = 5242880
WHERE id = 'purchase-photos';
