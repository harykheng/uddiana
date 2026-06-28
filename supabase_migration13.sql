-- Migration 13: Tambah last_opname_session_id ke tabel products
-- Jalankan di Supabase SQL Editor

ALTER TABLE products
  ADD COLUMN IF NOT EXISTS last_opname_session_id uuid;
