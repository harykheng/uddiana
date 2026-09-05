-- Migration 35: Koordinat GPS di customers (auto-isi dari Absen Kunjungan)
-- Sebelumnya link "Buka Maps" di list customer cuma nyari berdasarkan teks alamat,
-- yang sering meleset (alamat ditulis bebas, gang/ruko nggak kebaca Google Maps).
-- Sekarang tiap sales absen kunjungan di sales.html, koordinat GPS-nya sekalian
-- ditempel ke customer yang bersangkutan, jadi Maps langsung nunjuk titik tokonya.
-- Jalankan di Supabase SQL Editor

ALTER TABLE customers ADD COLUMN IF NOT EXISTS latitude double precision;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS longitude double precision;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS location_updated_at timestamptz;

-- 'absen'  = otomatis dari kunjungan sales, boleh ditimpa absen berikutnya
-- 'manual' = dikunci admin dari halaman Customers, absen TIDAK akan menimpanya
ALTER TABLE customers ADD COLUMN IF NOT EXISTS location_source text;

-- Fungsi ini yang dipanggil sales.html setelah absen tersimpan.
-- Aturan timpa ditaruh di server (bukan di browser) biar konsisten:
-- koordinat yang dikunci admin (location_source = 'manual') nggak pernah berubah.
-- Mengembalikan koordinat customer SETELAH operasi, jadi browser tahu titik mana
-- yang sekarang berlaku (bisa saja tetap koordinat lama kalau dikunci admin).
CREATE OR REPLACE FUNCTION set_customer_location_from_visit(
  p_customer_id uuid,
  p_latitude double precision,
  p_longitude double precision
) RETURNS TABLE (latitude double precision, longitude double precision)
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE customers c
  SET latitude = p_latitude,
      longitude = p_longitude,
      location_updated_at = now(),
      location_source = 'absen'
  WHERE c.id = p_customer_id
    AND p_latitude IS NOT NULL
    AND p_longitude IS NOT NULL
    AND coalesce(c.location_source, 'absen') <> 'manual';

  RETURN QUERY
    SELECT c.latitude, c.longitude FROM customers c WHERE c.id = p_customer_id;
END;
$$;
