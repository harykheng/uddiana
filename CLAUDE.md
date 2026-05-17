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
│   ├── config.js     ← Supabase URL + anon key, inisialisasi client
│   ├── auth.js       ← requireAdmin(), requireSales(), signOut(), updateSidebarUser()
│   └── utils.js      ← Semua utility: formatCurrency, formatDate, modal, toast, number format
├── css/
│   └── style.css     ← Satu file CSS global untuk semua halaman
├── supabase_schema.sql       ← Schema awal (tables, triggers, functions)
├── supabase_migration.sql    ← Migration 1: customers, price_shopee, invoice fields
├── supabase_migration2.sql   ← Migration 2: purchases, stock_transfers, cost_price
├── supabase_migration3.sql   ← Migration 3: user_profiles, auth columns di invoices
├── setup.html        ← Dipakai sekali untuk buat akun admin pertama
├── login.html
├── index.html        ← Dashboard
├── products.html
├── customers.html
├── invoices.html     ← Faktur penjualan (admin only)
├── sales.html        ← Buat faktur (sales role)
├── verify-invoices.html
├── purchases.html
├── stock-out.html
├── retur.html        ← Retur barang
├── reports.html      ← Laporan stok
├── profit-loss.html
├── piutang.html
├── laporan-sales.html
└── settings.html     ← Target omzet per sales, toggle fitur
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
    // load data...
  }
  init();
</script>
```

### Supabase Client
`config.js` membuat global `supabase` client. Semua halaman menggunakan `supabase` langsung (tidak di-import). Anon key terlihat di network — ini by design, keamanan via RLS policies Supabase. **Semua tabel yang dibuat manual harus `DISABLE ROW LEVEL SECURITY`** karena project ini tidak menggunakan RLS (menggunakan auth check di JS).

## Critical Conventions

### Auth Guards
- **Admin pages:** `const auth = await requireAdmin();` — redirect ke `sales.html` jika role bukan admin
- **Sales pages:** `const auth = await requireSales();` — hanya cek sesi aktif
- `requireAuth()` **TIDAK ADA** — jangan gunakan
- Role tersimpan di tabel `user_profiles.role` (nilai: `'admin'` | `'sales'`)

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

## Database Schema Summary

**Core tables:** `categories`, `products`, `customers`, `invoices`, `invoice_items`, `stock_movements`

**Transaction tables:** `purchases`, `purchase_items`, `stock_transfers`, `stock_transfer_items`

**Auth tables:** `user_profiles` (id = Supabase auth UUID)

**Return tables:** `returns`, `return_items` (RLS disabled)

**Settings tables:** `app_settings`, `sales_targets`

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

## CDN Dependencies

Dimuat via CDN di halaman yang membutuhkan:
- **Supabase JS v2:** `https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2` — semua halaman
- **TomSelect v2:** `https://cdn.jsdelivr.net/npm/tom-select@2` — `invoices.html`, `sales.html` (searchable dropdown produk)
- **SheetJS:** `https://cdn.jsdelivr.net/npm/xlsx@0.18.5/dist/xlsx.full.min.js` — `products.html` (import/export XLS)
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
| `feat/invoice-improvements` | **Pending PR** | Sisa pembayaran di list faktur + data-number untuk pay-amount |
| `feat/number-format-forms` | **Pending PR** | data-number untuk form buat faktur & modal produk |
| `fix/print-layout-v4` | **Pending PR** | Layout print invoice untuk dot matrix Epson LQ-310 |
| `feat/product-sort-search` | **Pending PR** | Sort nama & stok di list produk; search input di tab Produk sales.html |
| `feat/auto-sku-generate` | **Pending** | Auto-generate SKU saat import/tambah produk tanpa SKU — saat ini isinya sama dengan `feat/product-sort-search` (belum ada kode baru, perlu diimplementasi) |

Merge `feat/invoice-improvements` **dulu** sebelum `feat/number-format-forms` untuk menghindari conflict kecil di `js/utils.js`.

## Known Bug — WAJIB DIPERBAIKI

### `main:products.html` — SyntaxError duplicate `const sku`
**Gejala:** Halaman products.html di Vercel stuck "Memuat data...", tidak ada Fetch/XHR request ke Supabase, console error: `Uncaught SyntaxError: Identifier 'sku' has already been declared (products.html:839)`.

**Root cause:** Ada dua deklarasi `const sku` di scope yang sama di dalam `products.html` — kemungkinan hasil dari merge dua PR sekaligus (`feat/import-sku-optional` + `feat/product-list-description`) yang masing-masing menambahkan `const sku` di area yang sama. SyntaxError mencegah seluruh inline script dieksekusi.

**Fix:** Cari di `main:products.html` semua baris `const sku` / `let sku` dalam satu function scope, hapus/rename yang duplikat. Setelah fix, push langsung ke `main` (ini hotfix).

## Pending Tasks (prioritas)

1. **[HOTFIX] Fix duplicate `const sku` di `main:products.html`** — products.html broken di Vercel
2. **Auto-generate SKU** di `feat/auto-sku-generate`: saat import produk tanpa SKU, generate otomatis dari nama produk (misal `"Baju Batik"` → prefix 3 huruf + 4 digit random = `BAJ-4721`). Cek uniqueness vs `allProducts`. Berlaku juga di form tambah manual. Fungsi: `generateSKU(nama, alreadyUsed=null)`.
3. Merge PR-PR pending setelah fix bug

## Fitur Terbaru (diimplementasi sesi ini)

### sales.html — Major Overhaul (sudah merged ke main)
- 4 tab: **Buat Faktur**, **Riwayat**, **Produk**, **Wishlist**
- Tab Produk: search input, filter real-time nama produk
- Tab Wishlist: sales bisa ajukan produk baru (nama + brand), tersimpan ke tabel `wishlist_items`
- Form customer: field telepon + alamat
- Item row: stok ditampilkan (disabled), harga auto-fill dari produk (disabled)
- `checkUnpaidInvoices(customerId)` — warning jika customer punya faktur belum lunas
- Payment term values: `'cod'` | `'7_days'` | `'15_days'` | `'30_days'`

### wishlist.html — Halaman Admin Baru (sudah merged ke main)
- Filter by status (belum/sudah dipenuhi) dan by sales
- Admin bisa mark wishlist sebagai "Dipenuhi" atau hapus
- Membutuhkan tabel `wishlist_items` (lihat `supabase_migration5.sql`)

### products.html — Fitur Tambahan (di branch `feat/product-sort-search`)
- Kolom **Deskripsi** di tabel produk (truncated 160px, full text on hover)
- Search juga menelusuri deskripsi
- Sort by **Nama** dan **Stok** (klik header, toggle asc/desc, indikator ▲▼↕)
- Import: SKU opsional — kolom `sku` di CSV tidak wajib diisi
- Import: empty SKU → `null` (bukan `""`) agar tidak melanggar unique constraint PostgreSQL

### reset_demo_data.sql (sudah push ke main)
- TRUNCATE semua tabel transaksi + master data
- Yang dipertahankan: `user_profiles`, `app_settings`
- Jalankan di Supabase SQL Editor saat demo reset

### invoices.html — Print Layout (di branch `fix/print-layout-v4`)
- Optimized untuk dot matrix Epson LQ-310 (continuous form)
- `@page { size: 9.5in 11in; margin: 0.4in 0.6in; }`
- Minimal borders (border lambatkan LQ-310): hanya `border-bottom` pada `<th>` dan `border-top` pada grand total
- Header: Nomor invoice (bold) → nama toko "UD. DIANA" → tanggal cetak (bold) → nama sales
- Info pembeli di pojok kanan atas (nama toko, telp, alamat, jatuh tempo)
- TTD + totals dalam 1 baris flex (TTD kiri, totals kanan)
- Angka tanpa prefix "Rp" di baris item; "Rp" hanya di subtotal, diskon, total

### Tabel Baru — wishlist_items
```sql
-- Sudah ada di supabase_migration5.sql
create table wishlist_items (
  id uuid default gen_random_uuid() primary key,
  product_name text not null,
  brand text,
  submitted_by_id uuid references auth.users(id),
  submitted_by_name text,
  is_fulfilled boolean default false,
  created_at timestamptz default now()
);
-- DISABLE ROW LEVEL SECURITY
```

## Page–Role Matrix

| Halaman | Auth Required | Catatan |
|---|---|---|
| `login.html`, `setup.html` | — | Public |
| `sales.html` | `requireSales()` | Sales buat faktur, verif via admin |
| `verify-invoices.html` | `requireAdmin()` | Admin approve/reject faktur sales |
| Semua halaman lain | `requireAdmin()` | Admin only |

## Retur Barang Flow

`retur.html` → admin buat retur berdasarkan nomor faktur → status `pending` → admin approve:
- Approval: stok dikembalikan manual di JS (bukan trigger), catat di `returns` + `return_items`
- `laporan-sales.html` mengurangi revenue dengan `total_return_value` dari returns yang `status = 'approved'`
- Tabel `returns` dan `return_items` **wajib** `DISABLE ROW LEVEL SECURITY` di Supabase

## Print Invoice

`@page { size: 9.5in 11in; margin: 0.4in 0.6in; }` — Continuous Form 3ply kertas.  
Print dipicu via `window.print()`, konten di-inject ke `#print-area` div.

## Settings & Target Omzet

`settings.html` menggunakan tab: Kategori, User, Target Omzet.  
Target omzet tersimpan di tabel `sales_targets` (per sales per bulan).  
Toggle "tampilkan omzet bar" tersimpan di `app_settings` (key-value store).  
Omzet bar di `sales.html` dan `laporan-sales.html` membaca setting ini sebelum render.
