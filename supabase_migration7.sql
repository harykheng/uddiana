-- Migration 7: Tambah role super_admin
-- Jalankan di Supabase SQL Editor

-- Update check constraint untuk allow super_admin
ALTER TABLE user_profiles
  DROP CONSTRAINT IF EXISTS user_profiles_role_check;

ALTER TABLE user_profiles
  ADD CONSTRAINT user_profiles_role_check
  CHECK (role IN ('admin', 'sales', 'super_admin'));

-- Untuk upgrade user yang ada menjadi super_admin:
-- UPDATE user_profiles SET role = 'super_admin' WHERE role = 'admin' AND id = 'UUID_USER_DISINI';
