# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**StokManager** — sistem manajemen stok untuk DIANA KOSMETIK (sebelumnya UD. DIANA). Pure static frontend (HTML + CSS + Vanilla JS) dengan backend Supabase (PostgreSQL + Auth). Tidak ada build step, bundler, atau framework JS. Buka langsung di browser atau deploy ke Vercel/Netlify as-is.

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
│   ├── auth.js            ← requireAdmin(), requireSales(), signOut(), updateSidebarUser(), initMobileSidebar()
│   └── utils.js           ← Semua utility: formatCurrency, formatDate, modal, toast, number format, fetchAll()
├── css/
│   └── style.css          ← Satu file CSS global untuk semua halaman
├── supabase_schema.sql        ← Schema awal
├── supabase_migration*.sql    ← Migrations
├── reset_demo_data.sql        ← Query untuk reset semua data (jalankan di Supabase SQL Editor)
├── split-csv.html             ← Tool untuk split CSV besar sebelum import
├── setup.html         ← Dipakai sekali untuk buat akun admin pertama
├── login.html
├── index.html         ← Dashboard
├── products.html      ← Kelola produk (admin)
├── customers.html
├── invoices.html      ← Faktur penjualan (admin only)
├── sales.html         ← Buat faktur (sales role)
├── verify-invoices.html
├── purchases.html
├── stock-out.html
├── retur.html         ← Retur barang
├── reports.html       ← Laporan stok
├── profit-loss.html
├── piutang.html
├── laporan-sales.html
├── wishlist.html      ← Kelola wishlist produk dari sales (admin only)
└── settings.html      ← Target omzet per sales, toggle fitur
```

### Script Load Order (setiap halaman)
Setiap halaman HTML memuat script dalam urutan ini di bagian bawah `<body>`:
```html
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
<!-- optional CDN lain (TomSelect, SheetJS, Chart.js) -->
<script src="js/config.js"></script>
<script src="js/utils.js"></script>
<script src="js/auth.js"></script>
<script>
  async function init() {
    const auth = await requireAdmin();
    if (!auth) return;
    updateSidebarUser(auth.profile);
    // load data...
  }
  init();
</script>
```

### Sidebar Layout (semua halaman admin)
Sidebar di-hardcode di setiap HTML. **JANGAN** pakai `<div id="sidebar-placeholder">`.  
Halaman aktif pakai `class="nav-item active"`.  
`initMobileSidebar()` di auth.js otomatis inject hamburger button untuk mobile — tidak perlu edit HTML.

### Supabase Client
`config.js` membuat global `supabase` client. Anon key terlihat di network — by design, keamanan via RLS policies. **Semua tabel manual harus `DISABLE ROW LEVEL SECURITY`**.

## Critical Conventions

### Auth Guards
- **Admin pages:** `const auth = await requireAdmin();`
- **Sales pages:** `const auth = await requireSales();`
- `requireAuth()` **TIDAK ADA**
- Setelah auth berhasil, **wajib** panggil `updateSidebarUser(auth.profile)`

### fetchAll() — Bypass Supabase 1000 Row Limit
Supabase PostgREST default limit 1000 rows. Gunakan `fetchAll()` dari utils.js untuk semua query yang bisa >1000 rows:
```js
const { data, error } = await fetchAll(() =>
  supabase.from('products').select('*').eq('is_active', true).order('name')
);
```
**Sudah diapply di:** products, invoices (customers+products), customers, purchases, stock-out, retur, sales, verify-invoices.

### Modal System
```js
openModal('modal-id');
closeModal('modal-id');
```
**JANGAN** pakai `el.style.display`. Tambah `data-no-overlay-close` ke modal form agar tidak close saat klik overlay.

### Number Formatting
```html
<input type="text" inputmode="numeric" data-number id="my-input">
```
```js
const nilai = parseFormattedNumber(document.getElementById('my-input').value);
input.value = Number(angka).toLocaleString('id-ID');
```
**Stok & min stok** pakai `type="number"` biasa (bukan data-number).

### Currency, Date, Toast
```js
formatCurrency(amount)    // → "Rp 1.500.000"
formatDate(dateStr)       // → "14 Mei 2026"
todayISO()                // → "2026-05-14"
showToast('Berhasil', 'success' | 'error' | 'warning')
setLoading(btnElement, true/false)
```

### Subtotal & Pembulatan
```js
const sub = Math.round((qty * price) / 100) * 100;
```

## Database Schema Summary

**Core tables:** `categories`, `products`, `customers`, `invoices`, `invoice_items`, `stock_movements`  
**Transaction tables:** `purchases`, `purchase_items`, `stock_transfers`, `stock_transfer_items`  
**Auth tables:** `user_profiles`  
**Return tables:** `returns`, `return_items` (RLS disabled)  
**Settings tables:** `app_settings`, `sales_targets`  
**Wishlist tables:** `wishlist_items` (RLS disabled)

**Key invoice columns:**
- `status`: `'pending'` | `'paid'` | `'cancelled'`
- `verification_status`: `NULL` | `'pending'` | `'approved'` | `'rejected'`
- `payment_term`: `'cod'` | `'14_days'` | `'30_days'`
- `price_mode`: `'regular'` | `'shopee'` | `'custom'`
- `paid_amount`: numeric
- `sales_name`, `created_by_id`: diisi saat sales buat faktur
- `customer_phone`, `customer_address`: disimpan saat buat faktur
- `additional_charges`: jsonb — biaya tambahan `[{name, type, value, amount}]`

**Supabase Triggers:**
- Insert `invoice_items` → kurangi stok + catat `stock_movements`
- Update `invoices.status = 'cancelled'` → kembalikan stok
- Insert `purchase_items` → tambah stok + update `products.cost`
- Auto-generate `invoice_number` (`INV-YYMM-0001`), `purchase_number` (`PO-`), `transfer_number` (`OUT-`)

## SKU Convention
Format auto-generate: `UDD-0001` (sequential, ambil max dari allProducts + 1).  
Fungsi `generateSKU()` di products.html. Import CSV: kalau SKU kosong → auto-generate, kalau duplikat → generate baru.

## Termin Pembayaran
`'cod'` | `'14_days'` | `'30_days'` (15 hari dan 7 hari sudah dihapus)

## Import Produk (products.html)
- Batch upsert 100 rows sekaligus (`onConflict: 'sku'`)
- Header CSV di-normalize lowercase + strip BOM
- Alias kolom SKU: `sku`, `no_sku`, `kode`, `kode_produk`, `product_code`, `barcode`
- Deduplikasi SKU dalam batch: kalau tabrakan → auto-generate UDD-XXXX baru
- `split-csv.html` tersedia untuk split file CSV besar

## Branch Status (per Juni 2026)

| Branch | Status | Keterangan |
|---|---|---|
| `feat/biaya-tambahan` | **Active** | Biaya tambahan di faktur + fix edit faktur + termin di edit |
| `fix/sales-improvements` | **Merged** | Sales improvements, mobile sidebar, pagination, dll |
| `feat/retur-customer-flow` | **Merged** | Retur flow customer picker |
| `feat/auto-sku-generate` | **Merged** | Auto-generate SKU |

## Pending Tasks

1. Merge `feat/biaya-tambahan` ke main
2. Hapus `debug.html` (security risk — publicly accessible)
3. Hapus `index.html.bak` (junk file)

## Fitur Lengkap per Halaman

### products.html
- Import CSV batch (100 rows), upsert, deduplikasi SKU
- Auto-generate SKU UDD-0001
- TomSelect untuk dropdown kategori
- Sort by nama & stok, search include deskripsi
- Harga pcs + lusin di tabel
- Pagination tampil 1300+ produk (fetchAll)

### sales.html (mobile-first, tidak pakai css/style.css)
- 4 tab: Buat Faktur, Riwayat, Produk, Wishlist
- TomSelect customer + create customer baru inline
- Qty max = stok tersedia, error message inline
- Format ribuan harga satuan (readonly)
- Filter tanggal di tab Riwayat
- Harga/lusin di tab Produk
- Toast muncul dari atas (mobile)
- customer_phone & customer_address disimpan ke invoice
- requireSales() auth

### invoices.html (admin)
- Edit faktur: ubah item + qty + harga + termin
- Biaya tambahan (nominal/%) per faktur → disimpan ke additional_charges
- Print: nama DIANA KOSMETIK, layout dot matrix LQ-310
- Subtotal editable (admin override)
- Payment: COD / 14 Hari / 30 Hari

### verify-invoices.html
- Edit faktur sebelum approve: harga format ribuan, layout grid stabil

### retur.html
- Flow: pilih customer → list faktur → pilih faktur → pilih item
- Print: layout invoice style, judul BUKTI RETUR PEMBELIAN

### Mobile Sidebar (semua halaman admin)
- Hamburger button auto-inject via `initMobileSidebar()` di auth.js
- Slide-in dari kiri + backdrop overlay
- Tidak perlu edit HTML per halaman

## Print Invoice
`@page { size: 8.5in 11.5in; margin: 0.3in 0.4in; }` — Dot matrix Epson LQ-310.  
Nama perusahaan: **DIANA KOSMETIK** (bukan UD. DIANA).

## Page–Role Matrix

| Halaman | Auth | Catatan |
|---|---|---|
| `login.html`, `setup.html` | — | Public |
| `sales.html` | `requireSales()` | Sales buat faktur |
| `verify-invoices.html` | `requireAdmin()` | |
| `wishlist.html` | `requireAdmin()` | |
| Semua halaman lain | `requireAdmin()` | |
