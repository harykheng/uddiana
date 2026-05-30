# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**StokManager** — sistem manajemen stok untuk UD. DIANA. Pure static frontend (HTML + CSS + Vanilla JS) dengan backend Supabase (PostgreSQL + Auth). Tidak ada build step, bundler, atau framework JS. Buka langsung di browser atau deploy ke Vercel/Netlify as-is.

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
│   ├── auth.js            ← requireAdmin(), requireSales(), signOut(), updateSidebarUser()
│   └── utils.js           ← Semua utility: formatCurrency, formatDate, modal, toast, number format
├── css/
│   └── style.css          ← Satu file CSS global untuk semua halaman
├── supabase_schema.sql        ← Schema awal (tables, triggers, functions)
├── supabase_migration.sql     ← Migration 1: customers, price_shopee, invoice fields
├── supabase_migration2.sql    ← Migration 2: purchases, stock_transfers, cost_price
├── supabase_migration3.sql    ← Migration 3: user_profiles, auth columns di invoices
├── supabase_migration5.sql    ← Migration 5: wishlist_items table
├── reset_demo_data.sql        ← Query untuk reset semua data demo (jalankan di Supabase SQL Editor)
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
<script src="js/config.js"></script>   <!-- inisialisasi supabase global -->
<script src="js/utils.js"></script>    <!-- utility functions -->
<script src="js/auth.js"></script>     <!-- auth functions -->
<script>
  /* inline page logic */
  async function init() {
    const auth = await requireAdmin(); // atau requireSales()
    if (!auth) return;
    updateSidebarUser(auth.profile);   // selalu panggil ini setelah requireAdmin/Sales
    // load data...
  }
  init();
</script>
```

### Sidebar Layout (semua halaman admin)
Setiap halaman admin punya sidebar HTML yang di-hardcode (bukan inject via JS). Struktur wajib:
```html
<div class="layout">
  <aside class="sidebar">
    <div class="sidebar-logo">...</div>
    <nav class="sidebar-nav">
      <div class="nav-label">Menu Utama</div>
      <a href="index.html" class="nav-item">...</a>
      ...
      <div class="nav-label">Admin</div>
      <a href="wishlist.html" class="nav-item">⭐ Wishlist</a>
      <a href="settings.html" class="nav-item">⚙️ Pengaturan</a>
    </nav>
    <div class="sidebar-footer" id="sidebar-footer">© 2025 StokManager</div>
  </aside>
  <div class="main">
    <header class="topbar">...</header>
    <main class="page">...</main>
  </div>
</div>
```
**JANGAN** pakai `<div id="sidebar-placeholder">` — tidak ada script yang menginjeksi sidebar.  
Halaman aktif pakai `class="nav-item active"` pada link yang sesuai.

### Supabase Client
`config.js` membuat global `supabase` client. Semua halaman menggunakan `supabase` langsung (tidak di-import). Anon key terlihat di network — ini by design, keamanan via RLS policies Supabase. **Semua tabel yang dibuat manual harus `DISABLE ROW LEVEL SECURITY`** karena project ini tidak menggunakan RLS (menggunakan auth check di JS).

## Critical Conventions

### Auth Guards
- **Admin pages:** `const auth = await requireAdmin();` — redirect ke `sales.html` jika role bukan admin
- **Sales pages:** `const auth = await requireSales();` — hanya cek sesi aktif
- `requireAuth()` **TIDAK ADA** — jangan gunakan
- Role tersimpan di tabel `user_profiles.role` (nilai: `'admin'` | `'sales'`)
- Setelah auth berhasil, **wajib** panggil `updateSidebarUser(auth.profile)` agar nama user muncul di sidebar footer

### Modal System
CSS menggunakan `.modal-overlay` dengan `opacity:0; pointer-events:none` saat hidden. **WAJIB** pakai utility functions, bukan `style.display`:
```js
openModal('modal-id');   // tambah class 'open'
closeModal('modal-id');  // hapus class 'open'
```
**JANGAN** pakai `el.style.display = 'flex'` atau `'none'` — modal tidak akan muncul.

Tutup modal saat klik overlay:
```js
document.querySelectorAll('.modal-overlay').forEach(el => {
  el.addEventListener('click', e => { if (e.target === el) closeModal(el.id); });
});
```

### Number Formatting (Indonesian)
Semua input angka (harga, stok, qty) menggunakan format titik sebagai pemisah ribuan (1.000, 10.000, 100.000):

**HTML:**
```html
<input type="text" inputmode="numeric" data-number id="my-input" value="0">
```

**JS (membaca nilai):**
```js
const nilai = parseFormattedNumber(document.getElementById('my-input').value);
// parseFormattedNumber strips titik, returns float
```

**JS (set nilai ke input):**
```js
input.value = Number(angka).toLocaleString('id-ID');
```

Global handler di `utils.js` otomatis memformat semua input dengan atribut `data-number` saat user mengetik. `readonly` inputs boleh pakai `type="text"` tanpa `data-number`.

### Currency & Date Formatting
```js
formatCurrency(amount)    // → "Rp 1.500.000"
formatDate(dateStr)       // → "14 Mei 2026"
formatDateInput(dateStr)  // → "2026-05-14" (untuk value input[type=date])
todayISO()                // → "2026-05-14"
```

### Toast Notifications
```js
showToast('Berhasil disimpan');           // success (default)
showToast('Terjadi kesalahan', 'error');
showToast('Stok menipis', 'warning');
```

### Loading State Button
```js
setLoading(btnElement, true);   // disable + spinner
setLoading(btnElement, false);  // restore original text
```

### Subtotal & Harga Lusin — Pembulatan ke Kelipatan 100
Semua subtotal yang dihitung otomatis (`qty × harga`) dibulatkan ke kelipatan 100 terdekat:
```js
const sub = Math.round((qty * price) / 100) * 100;
```
Contoh: 16.666 × 12 = 199.992 → **200.000** ✓

Harga lusin di list produk = `Math.round((p.price * 12) / 100) * 100`

**Subtotal editable hanya di `invoices.html` (admin).** Di `sales.html` subtotal readonly.  
Saat user edit subtotal di invoices.html → harga satuan back-calc: `Math.round(subtotal / (qty * (1 - disc/100)))`

## Database Schema Summary

**Core tables:** `categories`, `products`, `customers`, `invoices`, `invoice_items`, `stock_movements`

**Transaction tables:** `purchases`, `purchase_items`, `stock_transfers`, `stock_transfer_items`

**Auth tables:** `user_profiles` (id = Supabase auth UUID)

**Return tables:** `returns`, `return_items` (RLS disabled)

**Settings tables:** `app_settings`, `sales_targets`

**Wishlist tables:** `wishlist_items` (RLS disabled)

**Key invoice columns (termasuk hasil migrations):**
- `status`: `'pending'` | `'paid'` | `'cancelled'`
- `verification_status`: `NULL` | `'pending'` | `'approved'` | `'rejected'`
- `payment_term`: `'cod'` | `'7_days'` | `'15_days'` | `'30_days'`
- `price_mode`: `'regular'` | `'shopee'` | `'custom'`
- `paid_amount`: numeric (akumulasi pembayaran parsial)
- `sales_name`, `created_by_id`: diisi saat sales buat faktur

**Supabase Triggers (otomatis, tidak perlu kode JS):**
- Insert `invoice_items` → kurangi stok produk + catat `stock_movements`
- Update `invoices.status = 'cancelled'` → kembalikan stok
- Insert `purchase_items` → tambah stok + update `products.cost`
- Auto-generate `invoice_number` (format: `INV-YYMM-0001`), `purchase_number` (`PO-`), `transfer_number` (`OUT-`)

### Tabel wishlist_items
```sql
-- supabase_migration5.sql
create table wishlist_items (
  id uuid default gen_random_uuid() primary key,
  product_name text not null,
  brand text,
  submitted_by_id uuid references auth.users(id),
  submitted_by_name text,
  is_fulfilled boolean default false,
  created_at timestamptz default now()
);
alter table wishlist_items disable row level security;
```

## CDN Dependencies

Dimuat via CDN di halaman yang membutuhkan:
- **Supabase JS v2:** `https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2` — semua halaman
- **TomSelect v2:** `https://cdn.jsdelivr.net/npm/tom-select@2` — `invoices.html`, `sales.html`
- **SheetJS:** `https://cdn.jsdelivr.net/npm/xlsx@0.18.5/dist/xlsx.full.min.js` — `products.html`
- **Chart.js v4:** `https://cdn.jsdelivr.net/npm/chart.js` — `laporan-sales.html`, `index.html`

## Git Workflow Rules

**WAJIB buat branch + PR untuk semua perubahan fitur.** Jangan push langsung ke `main`.

```bash
git checkout -b feat/nama-fitur
# buat perubahan
git add file1 file2
git commit -m "feat: deskripsi singkat"
git push -u origin feat/nama-fitur
# buat PR di GitHub untuk di-review user
```

Sebelum membuat branch baru pastikan main sudah up-to-date:
```bash
git pull --rebase origin main
```

Minor fixes (typo, favicon, logo) boleh langsung push ke main.

## Branch Status (per Mei 2026)

| Branch | Status | Keterangan |
|---|---|---|
| `feat/subtotal-editable` | **Active / Pending PR** | Branch utama saat ini — berisi semua fitur terbaru (lihat daftar di bawah) |
| `feat/product-sort-search` | **Pending PR** | Sort & search di list produk; search di tab produk sales.html — sudah ter-include di `feat/subtotal-editable` |
| `fix/print-layout-v4` | **Pending PR** | Layout print invoice untuk dot matrix Epson LQ-310 |
| `feat/invoice-improvements` | **Pending PR** | Sisa pembayaran di list faktur + data-number untuk pay-amount |
| `feat/number-format-forms` | **Pending PR** | data-number untuk form buat faktur & modal produk |
| `feat/auto-sku-generate` | **Pending** | Auto-generate SKU — belum diimplementasi, masih sama dengan `feat/product-sort-search` |

**Urutan merge yang aman:** `feat/invoice-improvements` → `feat/number-format-forms` → `feat/product-sort-search` → `feat/subtotal-editable`

## Known Bug — WAJIB DIPERBAIKI

### `main:products.html` — SyntaxError duplicate `const sku`
**Gejala:** Halaman products.html di Vercel stuck "Memuat data...", tidak ada Fetch/XHR ke Supabase, console error: `Uncaught SyntaxError: Identifier 'sku' has already been declared (products.html:839)`.

**Root cause:** Dua deklarasi `const sku` di scope yang sama di `products.html` — hasil merge dua PR bersamaan. SyntaxError mencegah seluruh inline `<script>` dieksekusi.

**Fix:** Cari semua `const sku` / `let sku` dalam satu function scope di `main:products.html`, hapus yang duplikat. Hotfix langsung ke `main`.

## Pending Tasks

1. **[HOTFIX]** Fix duplicate `const sku` di `main:products.html` — products.html broken di Vercel
2. **Auto-generate SKU** (`feat/auto-sku-generate`): saat import atau tambah produk tanpa SKU, generate otomatis dari nama produk. Format: 3 huruf pertama + 4 digit random (contoh: `BAJ-4721`). Cek uniqueness vs `allProducts` dan vs batch import. Berlaku di `runImport()` dan `saveProduct()`.
3. Merge PR-PR pending setelah hotfix

## Fitur yang Sudah Diimplementasi (branch feat/subtotal-editable)

### products.html
- **Kolom Deskripsi** di tabel (max-width 160px, truncated, full text on hover)
- **Sort** by nama & stok (klik header, toggle asc/desc, indikator ▲▼↕)
- **Search** juga menelusuri deskripsi produk
- **Harga Biasa** menampilkan 2 baris: harga/pcs + harga/lusin (rounded ke kelipatan 100)
- **Import CSV**: SKU opsional; error detail tampil dalam tabel scrollable (nama produk, SKU, penyebab); tombol "Download Error Report" → `.xlsx`
- Import: empty SKU → `null` (bukan `""`) agar tidak langgar unique constraint PostgreSQL

### sales.html
- 4 tab: **Buat Faktur**, **Riwayat**, **Produk**, **Wishlist**
- Tab Produk: search input, filter real-time
- Tab Wishlist: sales ajukan produk baru (nama + brand) → simpan ke `wishlist_items`
- Form customer: field telepon + alamat
- Item row: stok ditampilkan (disabled), harga auto-fill dari produk (disabled)
- Subtotal: **readonly** (auto-calc, dibulatkan ke kelipatan 100), tidak bisa diedit oleh sales
- `checkUnpaidInvoices(customerId)` — warning jika customer punya faktur belum lunas
- Payment term values: `'cod'` | `'7_days'` | `'15_days'` | `'30_days'`

### invoices.html
- Subtotal per baris item: **editable** (admin bisa override)
- Edit subtotal → harga satuan auto back-calc: `Math.round(subtotal / (qty × (1 - disc%)))`
- Subtotal auto-round ke kelipatan 100 saat dihitung dari qty × harga

### wishlist.html (admin)
- Layout standar admin (sidebar + topbar + layout class) — **bukan** sidebar-placeholder
- Filter by status (belum/sudah dipenuhi) dan by nama sales
- Tombol "✓ Penuhi" / "↩ Batal" dan "Hapus"
- Menu "⭐ Wishlist" sudah ada di sidebar semua halaman admin

### reset_demo_data.sql
- TRUNCATE semua tabel transaksi + master data
- Yang dipertahankan: `user_profiles`, `app_settings`
- Jalankan di Supabase SQL Editor saat reset data demo

### Print Invoice (fix/print-layout-v4)
- Optimized untuk dot matrix Epson LQ-310, continuous form
- `@page { size: 8.5in 11.5in; margin: 0.3in 0.4in; }`
- Minimal borders: hanya `border-bottom:2px solid #000` pada `<th>`, `border-top:1.5px solid #000` pada grand total
- Header: Nomor invoice (bold) → UD. DIANA → tanggal cetak (bold) → nama sales
- Info pembeli di pojok kanan atas (nama toko, telp, alamat, jatuh tempo)
- TTD + totals dalam 1 baris flex

## Page–Role Matrix

| Halaman | Auth Required | Catatan |
|---|---|---|
| `login.html`, `setup.html` | — | Public |
| `sales.html` | `requireSales()` | Sales buat faktur, lihat riwayat, wishlist |
| `verify-invoices.html` | `requireAdmin()` | Admin approve/reject faktur sales |
| `wishlist.html` | `requireAdmin()` | Admin kelola wishlist dari sales |
| Semua halaman lain | `requireAdmin()` | Admin only |

## Retur Barang Flow

`retur.html` → admin buat retur berdasarkan nomor faktur → status `pending` → admin approve:
- Approval: stok dikembalikan manual di JS (bukan trigger), catat di `returns` + `return_items`
- `laporan-sales.html` mengurangi revenue dengan `total_return_value` dari returns yang `status = 'approved'`
- Tabel `returns` dan `return_items` **wajib** `DISABLE ROW LEVEL SECURITY` di Supabase

## Print Invoice

`@page { size: 8.5in 11.5in; margin: 0.3in 0.4in; }` — Continuous Form 3ply kertas.  
Print dipicu via `window.print()`, konten di-inject ke `#print-area` div (display:none → block via @media print).  
**Catatan:** Browser tidak mau load gambar dari elemen `display:none` — gunakan teks "UD. DIANA" bukan `<img>` untuk logo di print area.

## Settings & Target Omzet

`settings.html` menggunakan tab: Kategori, User, Target Omzet.  
Target omzet tersimpan di tabel `sales_targets` (per sales per bulan).  
Toggle "tampilkan omzet bar" tersimpan di `app_settings` (key-value store).  
Omzet bar di `sales.html` dan `laporan-sales.html` membaca setting ini sebelum render.
