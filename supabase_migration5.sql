-- ============================================================
-- MIGRATION 5: Wishlist items
-- Jalankan di Supabase SQL Editor
-- ============================================================

CREATE TABLE IF NOT EXISTS wishlist_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_name text NOT NULL,
  brand text,
  submitted_by_id uuid,
  submitted_by_name text,
  is_fulfilled boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT now()
);

ALTER TABLE wishlist_items DISABLE ROW LEVEL SECURITY;
