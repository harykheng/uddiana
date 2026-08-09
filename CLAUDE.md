# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**StokManager** — sistem manajemen stok untuk **DIANA KOSMETIK** (sebelumnya UD. DIANA). Pure static frontend (HTML + CSS + Vanilla JS) dengan backend Supabase (PostgreSQL + Auth). Tidak ada build step, bundler, atau framework JS.

**Repo:** https://github.com/harykheng/uddiana  
**Deployed:** Vercel (auto-deploy dari main)

## No Build System

Tidak ada `npm`, `package.json`, `node_modules`, atau compile step. Semua JS/CSS ditulis langsung di file HTML atau di `css/style.css` dan `js/*.js`. Untuk develop: buka file HTML langsung di browser, atau pakai Live Server extension di VS Code.

## Architecture

### File Structure
```
/
├── js/
│   ├── config.js          ← Supabase URL + anon key, inisialisasi client
│   ├── auth.js            ← requireAdmin(), requireSuperAdmin(), requireSales(),
│   │                        signOut(), updateSidebarUser(), mobile sidebar (hamburger)
│   └── utils.js           ← formatCurrency, formatDate, modal, toast, number format, debounce
├── css/
│   └── style.css          ← CSS global + mobile responsive + sidebar overlay
├── supabase_schema.sql        ← Schema awal
├── supabase_migration.sql     ← Migration 1: customers, price_shopee, invoice fields
├── supabase_migration2.sql    ← Migration 2: purchases, stock_transfers, cost_price
├── supabase_migration3.sql    ← Migration 3: user_profiles, auth columns di invoices
├── supabase_migration5.sql    ← Migration 5: wishlist_items table
├── supabase_migration6.sql    ← Migration 6: cash_paid & transfer_paid di invoices
├── supabase_migration7.sql    ← Migration 7: role super_admin di user_profiles
├── reset_demo_data.sql        ← Reset semua data demo (jalankan di Supabase SQL Editor)
├── split-csv.html             ← Tool pecah file CSV besar (public, no auth)
├── setup.html         ← Dipakai sekali untuk buat akun admin pertama
├── login.html
├── index.html         ← Dashboard
├── products.html      ← Kelola produk (admin + super_admin)
├── customers.html
├── invoices.html      ← Faktur penjualan (admin + super_admin)
├── sales.html         ← Buat faktur (sales role, mobile-first)
├── verify-invoices.html
├── purchases.html
├── stock-out.html
├── retur.html         ← Retur barang
├── reports.html       ← Laporan stok (super_admin only)
├── profit-loss.html   ← Laba rugi (super_admin only)
├── piutang.html       ← Piutang (super_admin only)
├── laporan-sales.html ← Laporan sales (super_admin only)
├── wishlist.html      ← Kelola wishlist dari sales (admin + super_admin)
├── discounts.html     ← Aturan diskon per produk (admin + super_admin)
└── settings.html      ← Pengaturan akun & target omzet (super_admin only)
```

### Script Load Order
```html
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
<!-- CDN lain jika dibutuhkan -->
<script src="js/config.js"></script>
<script src="js/utils.js"></script>
<script src="js/auth.js"></script>
<script>
  async function init() {
    const auth = await requireAdmin(); // atau requireSuperAdmin() / requireSales()
    if (!auth) return;
    // updateSidebarUser sudah dipanggil otomatis di requireAdmin/requireSuperAdmin
    // load data...
  }
  init();
</script>
```

### Sidebar Layout
Setiap halaman admin punya sidebar HTML yang di-hardcode. **JANGAN** pakai `sidebar-placeholder`.  
Menu `data-super-admin` hanya tampil untuk `super_admin` (CSS + `body.is-super-admin`).

```html
<div class="layout">
  <aside class="sidebar">
    <div class="sidebar-logo">...</div>
    <nav class="sidebar-nav">
      <div class="nav-label">Menu Utama</div>
      <a href="index.html" class="nav-item">🏠 Dashboard</a>
      <a href="products.html" class="nav-item">📦 Produk</a>
      <a href="customers.html" class="nav-item">👥 Customers</a>
      <div class="nav-label">Transaksi</div>
      <a href="invoices.html" class="nav-item">🧾 Faktur Penjualan</a>
      <a href="verify-invoices.html" class="nav-item">✅ Verifikasi Faktur</a>
      <a href="purchases.html" class="nav-item">🛒 Pembelian Barang</a>
      <a href="stock-out.html" class="nav-item">📤 Keluar Barang</a>
      <a href="retur.html" class="nav-item">↩️ Retur Barang</a>
      <div class="nav-label">Laporan</div>
      <a href="reports.html" class="nav-item" data-super-admin>📊 Laporan Stok</a>
      <a href="profit-loss.html" class="nav-item" data-super-admin>💹 Laba Rugi</a>
      <a href="piutang.html" class="nav-item" data-super-admin>💰 Piutang</a>
      <a href="laporan-sales.html" class="nav-item" data-super-admin>👤 Laporan Sales</a>
      <div class="nav-label">Admin</div>
      <a href="wishlist.html" class="nav-item">⭐ Wishlist</a>
      <a href="discounts.html" class="nav-item">🏷️ Diskon Produk</a>
      <a href="settings.html" class="nav-item" data-super-admin>⚙️ Pengaturan</a>
    </nav>
    <div class="sidebar-footer">© 2025 StokManager</div>
  </aside>
  <div class="main">
    <header class="topbar">...</header>
    <main class="page">...</main>
  </div>
</div>
```

### Mobile Sidebar
`auth.js` otomatis inject hamburger button ke `.topbar` dan overlay backdrop saat `updateSidebarUser()` dipanggil. Tidak perlu kode tambahan di halaman.

### Supabase — Bypass Limit 1000 Rows
PostgREST default max 1000 rows. Gunakan pagination loop:
```js
let all = [], from = 0, CHUNK = 1000;
while (true) {
  const { data } = await supabase.from('tabel').select('*').range(from, from + CHUNK - 1);
  if (!data?.length) break;
  all = all.concat(data);
  if (data.length < CHUNK) break;
  from += CHUNK;
}
```

## Auth & Roles

### Role System
| Role | Akses |
|---|---|
| `sales` | `sales.html` saja |
| `admin` | Semua halaman KECUALI yang `data-super-admin` |
| `super_admin` | Semua halaman tanpa terkecuali |

### Auth Guard Functions
- `requireAdmin()` — allow `admin` + `super_admin`, redirect ke `sales.html` jika bukan
- `requireSuperAdmin()` — hanya `super_admin`, redirect ke `index.html` jika bukan
- `requireSales()` — cek sesi aktif saja, semua role boleh
- `requireAuth()` — **TIDAK ADA**, jangan gunakan

### Super Admin CSS (di style.css)
```css
.nav-item[data-super-admin] { display: none; }
body.is-super-admin .nav-item[data-super-admin] { display: flex; }
```
`auth.js` set `document.body.classList.add('is-super-admin')` untuk `super_admin`.

### Upgrade ke super_admin
Jalankan `supabase_migration7.sql`, lalu:
```sql
UPDATE user_profiles SET role = 'super_admin' WHERE id = 'UUID_USER';
```

## Critical Conventions

### Modal System
```js
openModal('modal-id');
closeModal('modal-id');
```
**JANGAN** pakai `el.style.display` — modal tidak akan muncul.

### Number Formatting (Indonesian)
```html
<input type="text" inputmode="numeric" data-number id="my-input">
```
```js
const nilai = parseFormattedNumber(document.getElementById('my-input').value);
input.value = Number(angka).toLocaleString('id-ID');
```

### Currency & Date
```js
formatCurrency(amount)    // → "Rp 1.500.000"
formatDate(dateStr)       // → "14 Mei 2026"
formatDateInput(dateStr)  // → "2026-05-14"
todayISO()                // → "2026-05-14"
```

### Subtotal & Harga Lusin
```js
// Subtotal auto-calc — Math.ceil (selalu round UP ke kelipatan 100)
const sub = Math.ceil((qty * price) / 100) * 100;

// Harga lusin di list produk
const hargaLusin = Math.round((p.price * 12) / 100) * 100;

// Stok format lusin
const lusin = Math.floor(qty / 12);
const sisa  = qty % 12;
// Tampil: "144 pcs (12 lsn)" atau "15 pcs (1 lsn + 3)"
```

**Subtotal editable hanya di `invoices.html`.** Di `sales.html` subtotal readonly.  
Saat edit subtotal → back-calc: `Math.round(subtotal / (qty * (1 - disc%)))`

## Database Schema Summary

**Core:** `categories`, `products`, `customers`, `invoices`, `invoice_items`, `stock_movements`  
**Transactions:** `purchases`, `purchase_items`, `stock_transfers`, `stock_transfer_items`  
**Auth:** `user_profiles` (role: `'admin'` | `'sales'` | `'super_admin'`)  
**Returns:** `returns`, `return_items`  
**Settings:** `app_settings`, `sales_targets`  
**Wishlist:** `wishlist_items`  
**Discounts:** `product_discount_rules` (product_id, min_qty, min_amount, discount_type, discount_value, is_active)  

### Key invoice columns
- `status`: `'pending'` | `'paid'` | `'cancelled'`
- `verification_status`: `NULL` | `'pending'` | `'approved'` | `'rejected'`
- `payment_term`: `'cod'` | `'14_days'` | `'15_days'` | `'30_days'` *(7_days dihapus)*
- `price_mode`: `'regular'` | `'shopee'` | `'custom'`
- `paid_amount`: akumulasi pembayaran parsial
- `cash_paid`, `transfer_paid`: tracking per metode (migration6)
- `additional_charges`: JSONB `[{name, type:'nominal'|'percent', value, amount}]`
- `sales_name`, `created_by_id`: diisi saat sales buat faktur

### Supabase Triggers
- Insert `invoice_items` → kurangi stok + catat `stock_movements`
- Update `invoices.status = 'cancelled'` → kembalikan stok
- Insert `purchase_items` → tambah stok + update `products.cost`
- Auto-generate `invoice_number` (`INV-YYMM-0001`), `purchase_number` (`PO-`), `transfer_number` (`OUT-`)

## CDN Dependencies

- **Supabase JS v2:** `https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2` — semua halaman
- **TomSelect v2:** `https://cdn.jsdelivr.net/npm/tom-select@2` — `invoices.html`, `sales.html`, `products.html`
- **SheetJS:** `https://cdn.jsdelivr.net/npm/xlsx@0.18.5/dist/xlsx.full.min.js` — `products.html`, `split-csv.html`
- **Chart.js v4:** `https://cdn.jsdelivr.net/npm/chart.js` — `laporan-sales.html`, `index.html`

## Git Workflow

**WAJIB branch + PR untuk fitur baru.** Minor fix boleh langsung ke main.

```bash
git checkout main && git pull --rebase origin main
git checkout -b feat/nama-fitur
git add file1 file2
git commit -m "feat: deskripsi"
git push -u origin feat/nama-fitur
```

## Branch Status (per Juni 2026)

| Branch | Status | Keterangan |
|---|---|---|
| `main` | **Live** | Semua fitur terbaru sudah merged |
| `fix/payment-method-split` | **Pending PR** | Fix cash/transfer split di laba rugi — perlu merge + jalankan migration6 |
| `feat/retur-customer-flow` | **Pending** | Perlu dicek statusnya |
| `feat/invoice-edit-and-ui-fixes` | **Pending** | Perlu dicek statusnya |

## Fitur per Halaman (kondisi terkini di main)

### products.html
- Sort nama & stok (▲▼↕), search nama/SKU/deskripsi
- Kolom harga biasa: 2 baris (harga/pcs + harga lusin rounded)
- Stok: format `X pcs (Y lsn + Z sisa)`
- Import CSV: SKU opsional, auto-generate jika kosong, batch upsert, bypass 1000 row limit
- Import: strip BOM, fallback alias kolom SKU, error detail tabel scrollable + download xlsx
- Export XLS termasuk harga lusin

### invoices.html
- Price mode: Regular / Shopee / Custom
- **Diskon per item**: toggle `%` (persentase) atau `Rp` (nominal) per baris item
  - `item_discount`: nilai diskon (angka % atau Rp)
  - `discount_type`: `'percent'` | `'nominal'` (migration8)
  - Auto-apply dari `product_discount_rules` saat pilih produk
  - Tampil di detail view & print jika ada item ber-diskon
- **Biaya tambahan**: nama bebas, tipe nominal atau persentase, disimpan ke `additional_charges` JSONB
- **Edit faktur**: admin bisa ubah termin pembayaran
- **Bayar sebagian**: akumulasi `cash_paid` + `transfer_paid` per metode pembayaran
- Subtotal per baris editable, back-calc harga satuan
- Print: nama **DIANA KOSMETIK**, layout dot matrix LQ-310
- Auto-update harga jual produk saat approve faktur

### discounts.html
- CRUD aturan diskon per produk (`product_discount_rules` table)
- Syarat berlaku: `min_qty` (pcs) dan/atau `min_amount` (Rp) — 0 = tanpa syarat
- Tipe diskon: `percent` (%) atau `nominal` (Rp)
- Jika beberapa rule cocok untuk satu produk → prioritas rule dengan `min_qty` tertinggi
- Accessible: admin + super_admin (`requireAdmin()`)

### sales.html
- Desain mobile-first dengan top nav (bukan sidebar)
- 4 tab: Buat Faktur, Riwayat, Produk, Wishlist
- Subtotal readonly (auto-round `Math.ceil` ke kelipatan 100)
- Payment term: COD, 14 Hari, 15 Hari, 30 Hari
- Simpan `customer_phone` & `customer_address` saat submit
- Tab produk: search, scroll horizontal mobile

### retur.html
- Print layout mirip invoice (3 kolom TTD)

### profit-loss.html
- Rekap kas: gunakan `cash_paid`/`transfer_paid` langsung (bukan `payment_method × total`)
- Fallback untuk faktur lama yang belum punya kolom baru

### reports.html
- Pagination tabel pergerakan stok (20 per halaman)
- Super_admin only

### split-csv.html
- Tool mandiri pecah CSV besar, tidak butuh auth

## Page–Role Matrix

| Halaman | Auth | Role |
|---|---|---|
| `login.html`, `setup.html`, `split-csv.html` | — | Public |
| `sales.html` | `requireSales()` | Semua role |
| `index.html`, `products.html`, `customers.html`, `invoices.html`, `verify-invoices.html`, `purchases.html`, `stock-out.html`, `retur.html`, `wishlist.html`, `discounts.html` | `requireAdmin()` | admin + super_admin |
| `reports.html`, `profit-loss.html`, `piutang.html`, `laporan-sales.html`, `settings.html` | `requireSuperAdmin()` | super_admin only |

## Print Invoice

Nama perusahaan di print: **DIANA KOSMETIK**.  
`@page { size: 8.5in 11.5in; margin: 0.3in 0.4in; }` — Continuous Form Epson LQ-310.  
**JANGAN** pakai `<img>` logo di print area — browser tidak load gambar dari `display:none`.

## Pending Migrations

| File | Keterangan |
|---|---|
| `supabase_migration6.sql` | cash_paid + transfer_paid — jalankan jika belum (terkait fix/payment-method-split) |
| `supabase_migration7.sql` | role super_admin — jalankan jika belum dijalankan sebelumnya |
| `supabase_migration8.sql` | discount_type di invoice_items + tabel product_discount_rules |
| `supabase_migration23.sql` | Bikin trigger `decrease_stock_on_invoice_item` atomik (cek+kurangi stok 1 statement) — cegah oversell kalau 2 faktur untuk produk sama di-insert nyaris bersamaan |
| `supabase_migration24.sql` | Sama seperti migration23 tapi untuk `decrease_stock_on_transfer` (Keluar Barang) |
| `supabase_migration25.sql` | Perbaiki akurasi quantity_before/after di `increase_stock_on_purchase` (bukan bug oversell, cuma akurasi catatan) |


