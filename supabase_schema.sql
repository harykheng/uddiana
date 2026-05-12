-- ============================================================
-- STOCK MANAGEMENT SYSTEM - SUPABASE SCHEMA
-- Jalankan query ini di Supabase SQL Editor (urut dari atas)
-- ============================================================

-- 1. Enable UUID extension
create extension if not exists "uuid-ossp";

-- ============================================================
-- 2. TABLE: categories
-- ============================================================
create table categories (
  id uuid default uuid_generate_v4() primary key,
  name text not null unique,
  created_at timestamp with time zone default now()
);

-- ============================================================
-- 3. TABLE: products
-- ============================================================
create table products (
  id uuid default uuid_generate_v4() primary key,
  name text not null,
  sku text unique not null,
  category_id uuid references categories(id) on delete set null,
  description text,
  price decimal(15,2) not null default 0,
  cost decimal(15,2) not null default 0,
  stock_quantity integer not null default 0,
  min_stock integer not null default 0,
  unit text not null default 'pcs',
  is_active boolean default true,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now()
);

-- ============================================================
-- 4. TABLE: invoices
-- ============================================================
create table invoices (
  id uuid default uuid_generate_v4() primary key,
  invoice_number text unique not null default '',
  customer_name text not null,
  customer_phone text,
  customer_address text,
  invoice_date date not null default current_date,
  subtotal decimal(15,2) not null default 0,
  discount decimal(15,2) not null default 0,
  tax_percent decimal(5,2) not null default 0,
  tax decimal(15,2) not null default 0,
  total decimal(15,2) not null default 0,
  status text not null default 'paid' check (status in ('pending', 'paid', 'cancelled')),
  notes text,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now()
);

-- ============================================================
-- 5. TABLE: invoice_items
-- ============================================================
create table invoice_items (
  id uuid default uuid_generate_v4() primary key,
  invoice_id uuid references invoices(id) on delete cascade,
  product_id uuid references products(id) on delete restrict,
  product_name text not null,
  quantity integer not null check (quantity > 0),
  price decimal(15,2) not null,
  subtotal decimal(15,2) not null,
  created_at timestamp with time zone default now()
);

-- ============================================================
-- 6. TABLE: stock_movements
-- ============================================================
create table stock_movements (
  id uuid default uuid_generate_v4() primary key,
  product_id uuid references products(id) on delete cascade,
  product_name text not null,
  type text not null check (type in ('in', 'out', 'adjustment')),
  quantity integer not null,
  quantity_before integer not null,
  quantity_after integer not null,
  reference_type text,
  reference_id uuid,
  notes text,
  created_at timestamp with time zone default now()
);

-- ============================================================
-- 7. FUNCTION: auto update updated_at timestamp
-- ============================================================
create or replace function update_updated_at_column()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger update_products_updated_at
  before update on products
  for each row execute function update_updated_at_column();

create trigger update_invoices_updated_at
  before update on invoices
  for each row execute function update_updated_at_column();

-- ============================================================
-- 8. FUNCTION: auto generate invoice number
-- ============================================================
create or replace function generate_invoice_number()
returns trigger as $$
declare
  seq integer;
  inv_num text;
  year_month text;
begin
  year_month := to_char(now(), 'YYMM');

  select coalesce(count(*), 0) + 1
  into seq
  from invoices
  where invoice_number like 'INV-' || year_month || '-%';

  inv_num := 'INV-' || year_month || '-' || lpad(seq::text, 4, '0');
  new.invoice_number := inv_num;
  return new;
end;
$$ language plpgsql;

create trigger auto_invoice_number
  before insert on invoices
  for each row
  when (new.invoice_number is null or new.invoice_number = '')
  execute function generate_invoice_number();

-- ============================================================
-- 9. FUNCTION: decrease stock when invoice item inserted
-- ============================================================
create or replace function decrease_stock_on_invoice_item()
returns trigger as $$
declare
  current_stock integer;
  prod_name text;
begin
  select stock_quantity, name into current_stock, prod_name
  from products where id = new.product_id;

  if current_stock < new.quantity then
    raise exception 'Stok produk "%" tidak cukup. Stok tersedia: %, diminta: %',
      prod_name, current_stock, new.quantity;
  end if;

  update products
  set stock_quantity = stock_quantity - new.quantity
  where id = new.product_id;

  insert into stock_movements
    (product_id, product_name, type, quantity, quantity_before, quantity_after, reference_type, reference_id)
  values
    (new.product_id, new.product_name, 'out', new.quantity,
     current_stock, current_stock - new.quantity, 'invoice', new.invoice_id);

  return new;
end;
$$ language plpgsql;

create trigger decrease_stock_trigger
  after insert on invoice_items
  for each row execute function decrease_stock_on_invoice_item();

-- ============================================================
-- 10. FUNCTION: restore stock when invoice cancelled
-- ============================================================
create or replace function restore_stock_on_cancel()
returns trigger as $$
declare
  item record;
  current_stock integer;
begin
  if new.status = 'cancelled' and old.status != 'cancelled' then
    for item in select * from invoice_items where invoice_id = new.id loop
      select stock_quantity into current_stock
      from products where id = item.product_id;

      update products
      set stock_quantity = stock_quantity + item.quantity
      where id = item.product_id;

      insert into stock_movements
        (product_id, product_name, type, quantity, quantity_before, quantity_after, reference_type, reference_id)
      values
        (item.product_id, item.product_name, 'in', item.quantity,
         current_stock, current_stock + item.quantity, 'invoice_cancel', new.id);
    end loop;
  end if;
  return new;
end;
$$ language plpgsql;

create trigger restore_stock_trigger
  after update on invoices
  for each row execute function restore_stock_on_cancel();

-- ============================================================
-- 11. SAMPLE DATA
-- ============================================================
insert into categories (name) values
  ('Elektronik'),
  ('Pakaian'),
  ('Makanan & Minuman'),
  ('Alat Tulis'),
  ('Peralatan Rumah');

insert into products (name, sku, category_id, price, cost, stock_quantity, min_stock, unit) values
  ('Laptop ASUS VivoBook 14',  'ELEC-001', (select id from categories where name = 'Elektronik'),        8500000, 7000000, 15, 3, 'unit'),
  ('Mouse Wireless Logitech',  'ELEC-002', (select id from categories where name = 'Elektronik'),         250000,  180000, 50, 10, 'unit'),
  ('Keyboard Mechanical',      'ELEC-003', (select id from categories where name = 'Elektronik'),         650000,  500000, 25,  5, 'unit'),
  ('Headset Gaming Rexus',     'ELEC-004', (select id from categories where name = 'Elektronik'),         350000,  240000,  8,  5, 'unit'),
  ('Kaos Polos Putih',         'CLO-001',  (select id from categories where name = 'Pakaian'),             75000,   45000,100, 20, 'pcs'),
  ('Celana Jeans Slim',        'CLO-002',  (select id from categories where name = 'Pakaian'),            250000,  150000, 60, 15, 'pcs'),
  ('Jaket Hoodie',             'CLO-003',  (select id from categories where name = 'Pakaian'),            185000,  110000,  4, 10, 'pcs'),
  ('Kopi Arabica 250gr',       'FNB-001',  (select id from categories where name = 'Makanan & Minuman'),  85000,   55000,200, 50, 'pack'),
  ('Teh Hijau Premium',        'FNB-002',  (select id from categories where name = 'Makanan & Minuman'),  45000,   28000,150, 30, 'pack'),
  ('Pulpen Pilot G2 0.5',      'STA-001',  (select id from categories where name = 'Alat Tulis'),          8000,    4000,500,100, 'pcs'),
  ('Buku Tulis A5 100lbr',     'STA-002',  (select id from categories where name = 'Alat Tulis'),         15000,    8000,300, 50, 'pcs'),
  ('Sapu Lantai Standar',      'HOU-001',  (select id from categories where name = 'Peralatan Rumah'),    35000,   20000, 80, 20, 'pcs');

-- ============================================================
-- SELESAI! Semua tabel, fungsi, dan sample data sudah dibuat.
-- ============================================================
