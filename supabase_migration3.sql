-- ============================================================
-- MIGRATION 3: Authentication & User Management
-- Jalankan di Supabase SQL Editor
-- ============================================================

-- 1. Tabel user profiles
CREATE TABLE IF NOT EXISTS user_profiles (
  id uuid PRIMARY KEY,
  name text NOT NULL,
  email text NOT NULL,
  role text NOT NULL DEFAULT 'sales' CHECK (role IN ('admin', 'sales')),
  is_active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_user_profiles_updated_at') THEN
    CREATE TRIGGER update_user_profiles_updated_at
      BEFORE UPDATE ON user_profiles
      FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  END IF;
END $$;

ALTER TABLE user_profiles DISABLE ROW LEVEL SECURITY;

-- 2. Tambah kolom verifikasi & sales ke invoices
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS created_by_id uuid;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS sales_name text;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS verification_status text
  DEFAULT NULL CHECK (verification_status IN ('pending', 'approved', 'rejected'));
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS verified_by_id uuid;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS verified_at timestamp with time zone;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS reject_reason text;

-- ============================================================
-- PENTING: Langkah Setup Awal
-- ============================================================
-- Sebelum menjalankan setup.html, lakukan ini di Supabase:
-- 1. Buka Supabase Dashboard
-- 2. Authentication → Providers → Email
-- 3. Matikan "Confirm email" (toggle OFF)
-- 4. Save
-- 5. Kemudian buka setup.html untuk buat akun admin
-- ============================================================
