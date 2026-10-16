-- ============================================================
-- Migration 44: Harga Canvas
-- Jalankan di Supabase SQL Editor
-- ============================================================
-- Sales canvas jualan lusinan dengan harga lebih murah dari harga reguler.
-- Barangnya produk yang SAMA (bukan SKU terpisah) supaya stok tetap satu.
--
--   * products.price_canvas  — harga canvas per pcs. 0 = produk tidak dijual
--                              canvas (disembunyikan dari akun canvas di sales.html)
--   * user_profiles.price_tier — 'regular' | 'canvas'. Akun 'canvas' di sales.html
--                              memakai price_canvas, qty pcs wajib kelipatan 12,
--                              diskon otomatis mati, faktur price_mode = 'canvas'
--
-- user_profiles tidak memakai RLS (migration3), jadi tanpa trigger di bawah sales
-- bisa mengubah price_tier akunnya sendiri lewat API. Polanya sama dengan
-- guard_user_profile_role (migration43): cuma super_admin yang boleh mengubah.
--
-- Aman dijalankan ulang.
-- ============================================================

ALTER TABLE products
  ADD COLUMN IF NOT EXISTS price_canvas decimal(15,2) NOT NULL DEFAULT 0;

ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS price_tier text NOT NULL DEFAULT 'regular';

ALTER TABLE user_profiles DROP CONSTRAINT IF EXISTS user_profiles_price_tier_check;
ALTER TABLE user_profiles
  ADD CONSTRAINT user_profiles_price_tier_check CHECK (price_tier IN ('regular', 'canvas'));


-- Aturannya:
--   * SQL Editor / service role (bukan anon/authenticated)  → bebas
--   * Akun baru dengan tier 'regular' (default)              → bebas
--   * Tier tidak berubah (edit nama, aktif/nonaktif)          → bebas
--   * Selain itu cuma super_admin
--
-- Sengaja SECURITY INVOKER — lihat catatan guard_user_profile_role di migration43.
CREATE OR REPLACE FUNCTION guard_user_profile_price_tier()
RETURNS TRIGGER AS $$
DECLARE
  v_caller_role text;
BEGIN
  IF current_user NOT IN ('anon', 'authenticated') THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' AND NEW.price_tier = 'regular' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' AND NEW.price_tier IS NOT DISTINCT FROM OLD.price_tier THEN
    RETURN NEW;
  END IF;

  SELECT role INTO v_caller_role
  FROM user_profiles
  WHERE id = auth.uid() AND is_active;

  IF v_caller_role = 'super_admin' THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'Hanya super_admin yang boleh mengatur harga canvas akun'
    USING ERRCODE = '42501';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_guard_user_profile_price_tier ON user_profiles;
CREATE TRIGGER trg_guard_user_profile_price_tier
  BEFORE INSERT OR UPDATE OF price_tier ON user_profiles
  FOR EACH ROW
  EXECUTE FUNCTION guard_user_profile_price_tier();
