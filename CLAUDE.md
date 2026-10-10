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
│   ├── auth.js            ← requireAdmin(), requireSuperAdmin(), requireSales(), requireGudang(),
│   │                        homePageForRole(), signOut(), updateSidebarUser(), mobile sidebar (hamburger)
│   ├── utils.js           ← formatCurrency, formatDate, modal, toast, number format, debounce
│   └── jadwal.js          ← helper Jadwal Kunjungan: HARI, localDateISO, fetchVisitFacts, computeVisitStatus
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
├── katalog-cetak.html ← Brosur PDF produk terlaris (admin + super_admin), buat toko yang belum terbiasa link katalog online
├── customers.html
├── invoices.html      ← Faktur penjualan (admin + super_admin)
├── sales.html         ← Buat faktur (sales role, mobile-first)
├── verify-invoices.html
├── purchases.html
├── stock-out.html
├── retur.html         ← Retur barang
├── retur-toko.html    ← Input retur dari toko oleh karyawan gudang (role gudang, layout tablet)
├── reports.html       ← Laporan stok (super_admin only)
├── profit-loss.html   ← Laba rugi (super_admin only)
├── piutang.html       ← Piutang (super_admin only)
├── laporan-sales.html ← Laporan sales (super_admin only)
├── jadwal-kunjungan.html ← Jadwal kunjungan mingguan per sales (super_admin only)
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
      <a href="jadwal-kunjungan.html" class="nav-item" data-super-admin>📅 Jadwal Kunjungan</a>
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

### Badge Retur Pending
`updateSidebarUser()` juga memanggil `refreshReturPendingBadge()` — badge oranye jumlah retur `pending` di menu **↩️ Retur Barang** semua halaman admin (cari link `.nav-item[href="retur.html"]`, 1 query `count` head-only). Tidak perlu kode di halaman; `retur.html` memanggil `setReturPendingBadge(n)` sendiri setelah `loadReturns()` supaya badge langsung ikut berubah setelah setujui/tolak.

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
| `sales` | `sales.html` saja (tidak bisa input retur — dikunci di database) |
| `gudang` | `retur-toko.html` saja (input retur dari toko, tanpa harga) |
| `admin` | Semua halaman KECUALI yang `data-super-admin` |
| `super_admin` | Semua halaman tanpa terkecuali |

### Auth Guard Functions
- `requireAdmin()` — allow `admin` + `super_admin`, redirect ke `sales.html` jika bukan
- `requireSuperAdmin()` — hanya `super_admin`, redirect ke `index.html` jika bukan
- `requireSales()` — cek sesi aktif saja, semua role boleh (`sales.html` sendiri melempar role `gudang` ke `retur-toko.html`)
- `requireGudang()` — `gudang` + `admin` + `super_admin`; sales dilempar ke `sales.html`
- `homePageForRole(role)` — halaman awal per role (dipakai `login.html` & redirect guard): admin/super_admin → `index.html`, gudang → `retur-toko.html`, sales → `sales.html`
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

### Loading Besar & Data Selalu Terbaru
- Proses yang menulis ke database (simpan/setujui/tolak) pakai `showFullLoading('pesan...')` → `hideFullLoading()` di `finally`. Overlay ditahan sampai daftar **selesai dimuat ulang** (`await loadX()`), baru toast sukses — supaya user tidak melihat daftar lama sesaat setelah proses selesai. Contoh: Setujui/Tolak/Edit faktur & Konfirmasi Bayar di `verify-invoices.html`
- `utils.js` otomatis `location.reload()` kalau halaman dipulihkan dari bfcache (tombol Back/Forward) — tanpa ini halaman tampil sebagai snapshot lama dan `init()` tidak jalan lagi
- `refreshOnReturn(fn)` (opt-in per halaman): balik ke tab setelah ≥ 10 detik ditinggal → `fn()` ambil ulang data. **Bukan** reload penuh, dan dilewati kalau ada modal terbuka / overlay loading tampil, supaya isian form tidak hilang (admin sering bolak-balik ke tab WhatsApp). Saat ini dipakai `verify-invoices.html`

### Number Formatting (Indonesian)
```html
<input type="text" inputmode="numeric" data-number id="my-input">
```
```js
const nilai = parseFormattedNumber(document.getElementById('my-input').value);
input.value = Number(angka).toLocaleString('id-ID');
```

### Dropdown Produk di Baris Item Faktur
Pakai `createProductTomSelect(sel, productList, onChange)` dari `utils.js` (dipakai `invoices.html`, `sales.html`, `verify-invoices.html`). **JANGAN** tulis semua produk sebagai `<option>` di tiap baris — faktur 60 item × 3000 produk bikin modal edit butuh ~8 detik dibuka dan ~0,7 detik per ketikan qty. `<select>`-nya cukup berisi opsi kosong + produk terpilih; karena itu `<option>` **tidak punya** `data-price`/`data-stock` — ambil data produk dari Map (`productById` / `editProductById`) berdasarkan `sel.value`.

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

// Harga lusin di list produk — Math.ceil juga (round UP), sama seperti
// subtotal di atas. Bukan Math.round — jangan diubah sepihak, harus tetap
// sama dengan lusinPrice() di repo katalog (katalog-diana-kosmetik)
const hargaLusin = Math.ceil((p.price * 12) / 100) * 100;

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
**Auth:** `user_profiles` (role: `'admin'` | `'sales'` | `'super_admin'` | `'gudang'`) — role cuma boleh diubah super_admin (trigger `guard_user_profile_role`, migration43)  
**Returns:** `returns`, `return_items` — `returns.source` (`'admin'` | `'gudang'`), `created_by_id`, `photo_path` (bucket privat `return-photos`). **RLS aktif** (migration43): baca bebas, tulis langsung cuma admin/super_admin, gudang lewat RPC `create_store_return()`, sales tidak bisa sama sekali  
**Settings:** `app_settings`, `sales_targets`  
**Wishlist:** `wishlist_items`  
**Jadwal Kunjungan:** `visit_schedules` (customer_id, sales_id, day_of_week 1=Senin..7=Minggu, every_week, needs_review, added_by_id) — unik per (customer, sales, hari)  
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
- Export XLS termasuk harga lusin — tombol toolbar = semua produk hasil filter; tombol **⬇️ Export XLS** di bar aksi seleksi = cuma produk yang dicentang (urutan sesuai urutan dicentang, diambil dari `allProducts` jadi centangan di luar filter aktif tetap ikut). Kolom sama persis, lewat `tulisXlsProduk()` bersama
- **Update Harga Massal**: checkbox pilih produk di tabel (desktop only, belum ada di mobile card view) → bar aksi muncul → modal set Harga Modal & Harga Jual sekaligus untuk semua produk terpilih, mode "Set nilai baru" atau "Naik/Turun %/Rp" (dihitung dari harga masing-masing produk saat ini, bukan disamakan)
- **Riwayat Harga Modal**: tab 💰 di modal Info Produk (ℹ️), **super_admin only** — daftar perubahan `products.cost` dari `product_cost_logs` (migration36) + ringkasan di atas ("3× berubah sejak ... Rp X → Rp Y ▲ naik Rp Z" / "belum pernah berubah"). Label sumber: Data awal / Produk baru / Dari pembelian (+ nomor PO) / Edit pembelian / Diubah manual, plus nama user dari `user_profiles`. Log ditulis trigger database, jadi import CSV, update massal, sampai UPDATE dari SQL Editor ikut tercatat
- **Foto Produk**: tombol 📷/🖼️ per baris (dan menu ··· di mobile) → modal unggah foto. Foto dikecilkan **di browser** jadi dua ukuran sebelum diunggah — thumb 400px & large 900px, WebP (fallback JPEG kalau browser tidak bisa encode WebP), rotasi EXIF diterapkan lewat `createImageBitmap(..., {imageOrientation:'from-image'})`. Disimpan di bucket publik `product-photos` (migration41) dengan path ber-timestamp `<id>/<ts>-thumb.webp` supaya ganti foto = URL baru, tidak ada cache CDN basi. Kolom `products.photo_thumb_path`/`photo_large_path`. Foto lama dihapus **setelah** baris produk menunjuk foto baru. Bucket dibatasi 1 MB/file & webp/jpeg saja sebagai pengaman kuota Supabase gratis
- **Foto Massal**: dari bar aksi seleksi (checkbox) → modal dengan dua cara isi: (1) **1 foto untuk semua produk terpilih** — untuk beberapa SKU yang fotonya memang sama; fotonya diunggah **sekali** ke `bersama/<kode>-thumb.webp` lalu path-nya dipakai semua produk terpilih, jadi 10 SKU = 1 file bukan 10 salinan; (2) **input file per baris** untuk SKU yang fotonya beda — baris yang diisi sendiri menang atas foto bersama. Batas **20 produk per batch**. Unggah berurutan, bukan paralel; kalau satu produk gagal sisanya tetap jalan dan yang gagal dilaporkan per SKU
- **PENTING — foto bisa dipakai bersama**: jangan pernah `storage.remove()` foto lama begitu saja. Pakai `hapusFotoKalauSudahYatim(paths)` yang menghitung dulu berapa baris `products` yang masih menunjuk path tsb (kolom thumb + large); file baru dihapus kalau hitungannya 0. Dipanggil **setelah** baris produk diperbarui, supaya hitungannya sudah mencerminkan keadaan baru. Berlaku di unggah satuan, hapus satuan, maupun massal
- **Edit Nama/SKU Massal**: dari bar aksi yang sama → modal list produk terpilih dengan input nama & SKU per baris (pre-filled), simpan sekaligus. Validasi: nama/SKU wajib diisi, SKU harus unik (dicek terhadap sesama baris terpilih & produk lain di luar seleksi) sebelum submit
- **Buat PDF**: dari bar aksi yang sama → buka `katalog-cetak.html?ids=<uuid1,uuid2,...>` (produk terpilih via query string, bukan sessionStorage — supaya reload halaman & window.open tanpa opener tetap jalan) di tab baru. Ini mode "manual" dari `katalog-cetak.html`, lihat halaman itu

### invoices.html
- **Daftar faktur dipaginasi di database** (25/halaman lewat `.range()` + `count: 'exact'`), bukan ambil semua lalu dipotong di browser — dulu juga diam-diam terpotong di 1000 faktur (batas PostgREST). `allInvoices` = baris halaman aktif saja. Pencarian (no. faktur / pelanggan / toko / nama barang) mengambil kolom ringan semua hasil (`searchInvoiceRows()`), isi lengkap tetap per halaman. Total nilai + dropdown filter sales dihitung dari query 3 kolom (`loadInvoiceSummary()`) yang jalan di belakang, tidak menahan tabel. Semua query daftar lewat `applyInvoiceFilters()` supaya halaman, jumlah, dan total konsisten
- Price mode: Regular / Shopee / Custom
- **Diskon per item**: toggle `%` (persentase) atau `Rp` (nominal, **per pcs** — otomatis dikali qty) per baris item
  - `item_discount`: nilai diskon tier pertama (angka % atau Rp per pcs)
  - `discount_type`: `'percent'` | `'nominal'` (migration8)
  - `item_discount2`: diskon tier kedua opsional, cuma berlaku kalau `discount_type = 'percent'` (migration28) — contoh "20%+5%". Dihitung **bertingkat/compound**, bukan dijumlah: `harga * (1 - d1/100) * (1 - d2/100)`. Field tier 2 otomatis disembunyikan kalau tipe diskon nominal.
  - Auto-apply dari `product_discount_rules` **dievaluasi ulang tiap qty / harga satuan / customer berubah**, bukan cuma sekali saat produk dipilih (`reapplyAllDiscounts()` di form buat faktur, `reapplyAllDiscountsEdit()` di modal edit). Aturan khusus customer diprioritaskan di atas aturan umum; aturan produk menang atas aturan grup — semua lewat satu fungsi bersama `findBestDiscountRule()`
  - **Kunci manual**: begitu kolom diskon (tipe/tier1/tier2) disentuh tangan, baris itu ditandai `tr.dataset.discAuto = '0'` dan berhenti ikut evaluasi otomatis. Ganti produk di baris itu = balik ke auto
  - Di modal edit, baris item yang sudah tersimpan default-nya terkunci. `seedEditAutoFlags()` melepas kunci cuma untuk baris yang diskon tersimpannya **sama persis** dengan hasil aturan pada qty & harga tersimpannya — jadi angka yang diketik tangan waktu faktur dibuat tidak ketimpa, tapi diskon yang memang datang dari aturan tetap ikut update kalau qty diubah
  - Tampil di detail view & print jika ada item ber-diskon (format `20%+5%` kalau ada tier kedua)
- **Biaya tambahan**: nama bebas, tipe nominal atau persentase, disimpan ke `additional_charges` JSONB
- **Edit faktur**: admin bisa ubah termin pembayaran
- **Bayar sebagian**: akumulasi `cash_paid` + `transfer_paid` per metode pembayaran
- Subtotal per baris editable, back-calc harga satuan
- **Tambah Stok Cepat** (tombol **+** di kolom Stok tiap baris item, form Buat maupun Edit Faktur): untuk produk yang stok di sistem 0/kurang padahal barangnya ada — modal kecil `modal-quick-stock` terbuka **di atas** form faktur, jadi draft tidak perlu ditutup & dibuat ulang. Kolom Stok + tombol jadi merah kalau qty > stok (`markStockShortage()`). Modal mengambil stok **live** dulu (bisa jadi sudah ditambah dari tab lain — kalau sudah cukup, cuma menyegarkan angka tanpa menambah), qty terisi otomatis sebesar kekurangan (total qty produk itu di semua baris; di modal Edit qty yang sudah dipakai faktur itu ikut dihitung lewat `editOwnedByProduct`). Alasan wajib. Simpan = `products.stock_quantity` diupdate bersyarat `.eq('stock_quantity', stokLama)` (kalau ada transaksi lain di jeda itu, tidak menimpa — admin klik Simpan lagi) + `stock_movements` tipe `in` dengan catatan `Tambah stok dari form faktur: <alasan>`. Diblok saat ada sesi stock opname aktif, sama seperti Sesuaikan Stok di `products.html`. Pengecekan stok saat simpan faktur & trigger database **tidak dilonggarkan** — faktur tetap tidak bisa membuat stok minus
- Print: nama **DIANA KOSMETIK**, layout dot matrix LQ-310
- Auto-update harga jual produk saat approve faktur
- **Import dari Teks WA** (tombol di form Buat Faktur, `openWaImport()`): admin tempel teks order WA (1 baris = 1 barang), `parseAndImportWaText()` parse tiap baris jadi qty+produk lalu panggil `addItemRow()` + `tomSelectInstances[id].setValue()` + `onQtyChange()` **yang sama dengan input manual** — bukan jalur baru ke `invoice_items`, cuma mengotomatisasi pengisian draft form. Qty: satuan `lusin/lsn/dz/dozen` dikonversi pasti ke pcs (×12), `pcs/pc/buah/biji/unit/botol/btl` dipakai apa adanya — dua ini dianggap pasti (posisi angka di awal/akhir baris sama-sama kena, cth "6 pcs Produk X" maupun "Produk X 6 pcs"). Satuan ambigu (`dus/box/karton/pack/pak`), notasi `x3`/`3x`, atau angka polos di akhir baris tanpa satuan tetap diisi sebagai perkiraan tapi ditandai `assumed=true`
  - Qty: angka polos di akhir baris tanpa satuan sama sekali **dilewati** (tidak dianggap qty) kalau berpadding nol (`01`, `02`, `05`, dst.) — itu hampir pasti kode varian/shade kosmetik (lazim di nama produk), bukan qty yang diketik manusia (orang nulis qty "5", bukan "05"). Penting kalau admin paste **nama produk asli apa adanya** (tanpa "x pcs" sama sekali) — kalau kode variannya salah terbaca sebagai qty lalu terpotong dari nama, beberapa varian produk (misal "...Matte 01/02/03/05") jadi punya sisa nama yang SAMA, dianggap ambigu oleh `cariProdukTerbaik()`, dan baris itu jadi TIDAK ketemu sama sekali walau nama sumbernya sama persis dengan nama produk di database
  - Pencocokan produk (`cariProdukTerbaik()`): skor = **recall dari sisi teks WA saja** (berapa % kata di WA ketemu di nama produk, pakai `kataCocok()` yang toleran typo 1 huruf via Levenshtein + sinonim slang `cewe/cewek/perempuan→wanita`, `cowo/cowok/laki→pria`) — BUKAN dinormalisasi ke sisi terpanjang, karena nama produk di database nyaris selalu lebih deskriptif daripada singkatan toko (cth WA "Pixy Refill 05" vs DB "Pixy UV Whitening Two Way Cake Refill 05") — kalau dihukum karena nama produk lebih panjang, singkatan apa pun jadi hampir tidak pernah cocok. Minimal 60% kata WA nyambung (`cariKandidat()`)
  - **Ambigu** = kandidat terbaik TIDAK punya satu pun kata pembeda dibanding kandidat lain yang juga lolos ambang 60% (bukan sekadar skornya mepet secara persentase) — kalau tiap kata yang bikin dia "terbaik" ikut dipunyai kandidat lain itu juga, dianggap TIDAK ketemu (misal "Pasta Gigi Kecil" nyangkut ke Pepsodent & CloseUp sama rata, ga ada kata pembeda sama sekali). Sebaliknya kalau ada 1 kata pembeda nyata — meski nama produknya panjang & cuma beda itu doang (cth "...Extra **Vitamin E** 100ml" vs "...Extra **Lidah Buaya** 100ml", beda di 1 dari 7 kata) — tetap dianggap ketemu, BUKAN ditolak cuma karena skor kandidat ke-2 kebetulan ikut tinggi (6/7). Threshold rasio murni (skorKedua/skorTerbaik) sempat dicoba lebih dulu tapi gagal di kasus nama panjang yang cuma beda 1 kata, makanya diganti ke cek "kata pembeda" ini
  - **Tanda kurung TIDAK dibuang mentah-mentah** sebelum dicocokkan — isinya kadang catatan ("(ALL warna)", "(harga dikonfirmasi)") tapi kadang justru **nama varian asli produk** ("(Creme)"/"(Invisible)"/"(Natural Beige)"/"(Rose)" di "Marcks Bedak Beauty Powder ( ... ) 40gr", atau "(Kecil)"/"(Besar)" dkk) — kalau dibuang begitu saja, beberapa varian produk yang bedanya CUMA di isi kurung jadi punya sisa teks IDENTIK dan dianggap ambigu, walau teks WA-nya sama persis dengan nama produk di database. `cariProdukTerbaik()` coba **2 cara baca sekaligus** lewat `cariKandidat()`: isi kurung dipertahankan sebagai kata biasa, DAN isi kurung dibuang total (`stripKurung()`) — kalau cuma salah satu yang dapat kandidat, pakai itu; kalau KEDUANYA dapat kandidat tapi produknya beda, baru dianggap ambigu
  - Baris yang mengandung kata **"all"/"semua"** (varian warna dkk) ditandai perlu dicek juga meski produknya ketemu — 1 baris cuma bisa isi 1 produk, jadi tidak auto-expand jadi banyak SKU warna
  - Baris yang produknya tidak ketemu ATAU qty/satuannya tidak pasti ATAU ada kata "all/semua" ditandai **kuning** (`tr.style.background` + `title` berisi teks WA asli) — **tidak pernah auto-submit**, admin wajib cek/lengkapi manual sebelum klik Simpan Faktur, exact sama dengan prinsip katalog online: salah satuan/qty adalah kegagalan paling fatal, jadi langkah verifikasi manusia terakhir tidak pernah dilewati

### discounts.html
- CRUD aturan diskon per produk (`product_discount_rules` table)
- Syarat berlaku: `min_qty` (disimpan dalam pcs, tapi **input & tampilan di UI dalam lusin** — 1 lusin = 12 pcs, dikonversi otomatis) dan/atau `min_amount` (Rp) — 0 = tanpa syarat
- Tipe diskon: `percent` (%) atau `nominal` (Rp per pcs)
- Diskon bertingkat opsional (`discount_value2`, migration29) khusus tipe `percent` — contoh "20%+5%", ikut ke-auto-apply ke faktur (tier 1 & 2)
- **Diskon khusus customer** (tabel junction `product_discount_rule_customers`, migration30+31) — opsional, bisa pilih beberapa toko sekaligus per aturan. Kosong = berlaku semua toko (aturan umum), diisi 1+ toko = cuma berlaku toko-toko itu. Kalau ada aturan umum & khusus toko yang sama-sama cocok, yang khusus toko diprioritaskan (di `invoices.html` & `sales.html`)
- Jika beberapa rule cocok untuk satu produk → prioritas: khusus customer dulu, baru `min_qty` tertinggi
- Accessible: admin + super_admin (`requireAdmin()`)

### customers.html
- Kolom **Lokasi**: link Buka Maps per customer — pakai koordinat GPS kalau ada (label `📍 dari absen` / `📌 manual`), fallback pencarian teks alamat kalau belum ada
- Field **Titik Lokasi (GPS)** di modal edit: paste `lat, lng` dari Google Maps. Diisi tangan = `location_source = 'manual'` (dikunci, absen sales tidak menimpanya); dikosongkan = koordinat dihapus dan boleh diisi absen lagi. Koordinat cuma ikut tersimpan kalau memang diubah, jadi edit nama/telepon tidak diam-diam mengunci titik hasil absen
- Export XLS termasuk kolom Latitude & Longitude
- Tombol **🔗 Link** per baris: salin link katalog toko ke clipboard. Link = `app_settings.catalog_base_url` + `/t/` + `customers.catalog_token` — dua-duanya dari database, tidak ada domain atau token yang di-hardcode. Token dibuat otomatis untuk customer baru lewat trigger (migration38); kalau domain atau token belum ada, tombolnya memberi tahu apa yang kurang, bukan menyalin link rusak. Fallback `document.execCommand('copy')` dipakai kalau ERP dibuka lewat http biasa (`navigator.clipboard` cuma jalan di HTTPS)
- Tombol **📲 Kirim WA** di sebelah 🔗 Link: buka `wa.me` langsung ke nomor HP toko (`customers.phone`) dengan pesan link katalog sudah terisi — tanpa menyalin/tempel manual. Validasi link-nya sama dengan 🔗 Link (lewat `catalogLinkFor()` bersama), plus cek nomor HP toko sudah terisi. Nomor `08xx...` dikonversi ke format `62xxx` (wa.me tidak terima `0` di depan) lewat `normalizeIndoPhone()`
- Nama distributor, nomor WA kantor, dan domain katalog (`app_settings.catalog_distributor_name`/`catalog_whatsapp_number`/`catalog_base_url`) diedit lewat tab **🔗 Katalog Toko** di `settings.html` (super_admin) — sebelumnya cuma bisa diubah lewat SQL Editor
- **Sort kolom** (pola sama dengan `products.html`): header **Nama**, **Total Transaksi**, **Total Belanja** bisa diklik (`setSort()` + `sort-icon` ▲▼↕). "Total Transaksi" = jumlah faktur penjualan toko itu — ini yang dipakai untuk lihat toko mana paling sering PO. Klik pertama kali di kolom angka langsung urut besar→kecil (bukan kecil→besar) supaya toko paling aktif langsung kelihatan di atas tanpa klik dua kali; kolom Nama tetap A→Z di klik pertama. Sort jalan di data yang sudah ke-filter pencarian, dari `invoiceStats` yang sama dengan yang dipakai kolom Total Transaksi/Total Belanja — bukan query ulang ke database

### sales.html
- Desain mobile-first dengan top nav (bukan sidebar)
- Tab: Hari Ini, Buat Faktur, Riwayat, Produk, Customer, Absen, Wishlist
- **Layar loading awal** (`#init-loading`, statis di HTML jadi muncul sebelum JS jalan) menutup halaman sampai `init()` selesai — termasuk jadwal Hari Ini — supaya tidak tampil tab Buat Faktur dulu lalu loncat. Semua query awal yang tidak saling bergantung dijalankan paralel di satu `Promise.all`. Dibuka di `finally` (plus pengaman 20 detik) supaya tidak pernah macet menutupi halaman. CSS `.full-loading-overlay` untuk `showFullLoading()` didefinisikan sendiri di halaman ini karena `css/style.css` tidak dimuat
- **Tab 📅 Hari Ini** *(masih uji coba — cuma tampil untuk akun yang dipilih di `jadwal-kunjungan.html`, key `app_settings.jadwal_tab_visible_for`: `''` = belum ke siapa pun, `<user id>` = satu akun mis. akun test sales, `'all'` = semua sales. Akun lain: tombol tab disembunyikan, data jadwal tidak dimuat, tab default tetap Buat Faktur)* (jadwal kunjungan, dibuka otomatis kalau sales punya jadwal di `visit_schedules`): daftar toko jadwal hari itu untuk sales yang login + pilihan hari lain (intip jadwal berikutnya). Status tiap toko dihitung **di browser** dari faktur lewat `computeVisitStatus()` di `js/jadwal.js`, tidak disimpan:
  - **PO kurang dari 10 hari lalu** (`JADWAL_JEDA_PO_HARI`, faktur sebelum hari itu, dari sumber mana pun — sales, admin, WA, katalog; `cancelled` & `rejected` tidak dihitung) → masuk bagian lipat "✔️ Sudah PO – kunjungi minggu depan" berisi tanggal PO, nilai & siapa yang input. Ini yang bikin pola "PO → 2 minggu lagi, tidak PO → minggu depan lagi" jalan sendiri
  - Pengecualian, tetap **wajib**: `every_week = true` (toko yang harus didatangi tiap minggu) atau toko punya **tagihan jatuh tempo** (sisa > 0 setelah retur approved, jatuh tempo = `invoice_date` + termin, sama seperti `piutang.html`) — datang untuk nagih
  - Daftar wajib diurutkan: tagihan dulu, lalu yang paling lama tidak PO; yang sudah ✅ diabsen hari ini (`sales_visits`, oleh siapa pun) atau 🧾 PO hari ini turun ke bawah. Ringkasan "Sudah dikunjungi X/Y" + "Kurang N toko dari target" (`app_settings.visit_target_per_day`, default 12)
  - Tanggal pakai **tanggal lokal** (`localDateISO()`), bukan `todayISO()` yang UTC — sales berangkat sebelum jam 07:00 WIB
  - Tombol per toko: 🧾 Buat Faktur (pindah tab + pilih customer), 📍 Absen (kalau tab Absen tampil), 🗺️ Maps, 📞
- **Toko baru dari sales otomatis masuk jadwal**: customer baru yang dibuat **role sales** di halaman ini (dari form faktur maupun tombol "➕ Daftarkan toko baru" di tab Hari Ini) langsung di-insert ke `visit_schedules` untuk sales itu di hari ini dengan `needs_review = true` — **hanya kalau tab Hari Ini aktif untuk akun itu** (lihat `jadwal_tab_visible_for`) — muncul di kartu "🆕 perlu dicek" `jadwal-kunjungan.html`. Admin/super_admin yang membuka sales.html tidak ikut mengisi jadwal. Gagal masuk jadwal tidak membatalkan customer yang sudah tersimpan
- Subtotal readonly (auto-round `Math.ceil` ke kelipatan 100)
- Payment term: COD, 14 Hari, 15 Hari, 30 Hari
- Simpan `customer_phone` & `customer_address` saat submit
- Tab customer: link **🗺️ Buka Maps** per customer — pakai titik GPS hasil absen kalau ada (badge `titik GPS`), fallback pencarian teks alamat (`cari dari alamat`)
- Tab produk: search, scroll horizontal mobile
  - Badge diskon 🏷️ di bawah nama produk kalau ada aturan diskon aktif dari `product_discount_rules` (cuma rule per-produk, bukan grup — diskon grup butuh konteks isi keranjang jadi belum ditampilkan di sini; juga cuma aturan **umum**, aturan khusus customer nggak muncul di list ini karena belum ada konteks customer), format sama dengan `discounts.html` (contoh "20%+5% (≥72pcs)")
  - Di kartu item Buat Faktur & Edit Faktur: begitu qty memenuhi syarat rule, **Harga Satuan otomatis berubah ke harga setelah diskon** (badge yang aktif jadi ✅ hijau, evaluasi ulang tiap qty berubah). Badge di sini menampilkan aturan umum **dan** aturan khusus customer yang lagi dipilih (label 🏪 buat yang khusus toko), dievaluasi ulang tiap ganti customer juga — plus baris kecil "Harga normal: Rp X" di bawahnya. Yang disubmit ke `invoice_items` tetap `price` = harga katalog asli + `item_discount`/`item_discount2`/`discount_type` tercatat terpisah (bukan harga baru begitu aja) — biar laporan margin & histori diskon tetap akurat
- **Tab Absen** *(masih tahap testing — default cuma tampil buat admin/super_admin, di-ON-kan ke semua sales lewat toggle "Tampilkan tab Absen ke semua sales" di settings.html, key `app_settings.absen_tab_enabled`)*: bukti kunjungan sales — pilih customer, GPS + reverse-geocode alamat (OpenStreetMap Nominatim, gratis) diambil begitu tab dibuka, foto di-ambil lalu di-stempel nama toko+alamat+jam langsung ke pixel canvas (nggak bisa dihapus tanpa keliatan diedit) sambil di-compress, submit → simpan ke `sales_visits` (`supabase_migration27.sql`) + foto ke Storage bucket privat `visit-photos`, lalu foto asli (bukan link) di-attach otomatis ke share sheet WhatsApp HP via Web Share API (`navigator.share`) berisi teks lokasi+jam — sales pilih grup/kontak tujuan sendiri (nggak ada nomor/grup tetap, karena Web Share API cuma bisa buka share sheet umum, bukan target spesifik). Kalau browser nggak dukung file share (jarang, biasanya desktop), foto dibuka di tab baru via signed URL (30 hari) buat di-share manual. Jam yang tercatat di database pakai `default now()` server (bukan jam device) sebagai sumber kebenaran utama — stempel di foto pakai jam device, jadi kalau beda jauh dari jam server itu tanda kecurigaan. Koordinat kunjungan sekaligus ditempel ke `customers.latitude/longitude` lewat RPC `set_customer_location_from_visit()` (migration35) — kecuali titiknya sudah dikunci admin (`location_source = 'manual'`) — supaya link Buka Maps di tab Customer nunjuk titik toko yang sebenarnya, bukan nebak dari teks alamat. Gagal update koordinat tidak bikin absen dianggap gagal (absen sudah tersimpan duluan). Thumbnail foto (signed URL, expired 1 jam, di-generate ulang tiap load — cuma buat foto di halaman yang lagi ditampilkan) juga tampil di tabel "Riwayat Kunjungan" `laporan-sales.html`, dengan pagination 10 per halaman.

### jadwal-kunjungan.html
- Pengganti jadwal mingguan sales yang dulu dicetak di kertas HVS. Diisi sekali, **berulang otomatis tiap minggu** sampai diubah. `requireSuperAdmin()`
- Pilih sales → tab hari (Senin–Sabtu, Minggu opsional; jumlah toko per hari, kuning kalau di bawah target) → tabel toko: PO terakhir, centang **Selalu tiap minggu** (`every_week`), pindah hari, hapus dari jadwal (customer tidak ikut terhapus). Satu toko boleh di beberapa hari / sales (ditampilkan sebagai chip)
- **+ Tambah Toko**: modal pilih banyak toko sekaligus (cari + filter "Hanya yang belum ada jadwal", urut customer terbaru) + tambah customer baru langsung dari modal. Simpan via `upsert(..., { ignoreDuplicates: true })` pada unique key
- Tombol "📋 N toko belum ada jadwal" — customer yang dibuat admin di `customers.html` tidak tahu harinya, jadi ditempatkan manual dari sini
- Kartu **🆕 Toko baru dari sales — perlu dicek**: baris `needs_review = true`; super_admin bisa ganti sales/hari lalu ✓ Oke, atau hapus
- Target toko per hari (`app_settings.visit_target_per_day`) diedit di halaman ini
- Kartu **🧪 Tab "Hari Ini" di HP tampil untuk**: pilih satu akun (uji coba) / Semua sales / belum ke siapa pun → `app_settings.jadwal_tab_visible_for`. Jadwal tetap bisa disiapkan untuk semua sales walaupun tab-nya belum tampil
- **🖨️ Cetak Jadwal**: semua hari untuk sales terpilih, A4, kolom No/Toko/Alamat/Telepon/Ket./✓

### retur.html
- Print layout mirip invoice (3 kolom TTD)
- Retur **pending selalu tampil** di tabel walau di luar filter tanggal (default filter = bulan berjalan), dan diurutkan paling atas
- Retur dari gudang ditandai **🏬 Gudang** (+ 📷 kalau ada foto) di tabel; detail menampilkan siapa yang input + foto barang (signed URL 1 jam dari bucket privat `return-photos`). Disetujui/ditolak dengan tombol yang sama seperti retur buatan admin

### retur-toko.html
- Halaman **terpisah** untuk karyawan gudang/toko input retur barang dari toko pelanggan — sengaja tidak di `sales.html` supaya sales tidak bisa retur sembarangan. `requireGudang()`; tidak ada di sidebar admin (admin tetap memproses retur di `retur.html`)
- Layout untuk **tablet** (tombol & baris besar, dua kolom ≥ 900px: pilih barang | daftar retur; menumpuk di layar lebih kecil). Top bar sendiri, bukan sidebar. Dua tab: ➕ Input Retur, 📋 Riwayat
- Alur: pilih toko (TomSelect, dropdown di `body` karena `.card` ber-`overflow:hidden`) → **pilih faktur** (kartu ⚡ Otomatis + faktur toko itu yang masih ada sisa, terbaru dulu; kotak cari nomor faktur muncul kalau > 8 faktur) → muncul **barang** + sisa yang masih bisa diretur (format lusin) — mode Otomatis: gabungan semua faktur; faktur dipilih: cuma isi faktur itu ("Dibeli X di faktur ini"). Ganti faktur = daftar retur dikosongkan → + Retur, atur qty (stepper, maks = sisa, tombol "Semua") → alasan (chip sama dengan `retur.html`; "Lainnya" wajib diisi teks) → catatan & **foto opsional** → Kirim
- **Tidak ada harga** di halaman ini — query tidak mengambil kolom harga sama sekali
- Faktur dipilih → RPC `create_store_return(..., p_invoice_id)` cuma memakai faktur itu (qty melebihi sisanya = ditolak; faktur bukan milik toko / batal / ditolak verifikasi = ditolak)
- **Otomatis** (`p_invoice_id` NULL) → faktur dicari di database oleh RPC `create_store_return()` (migration43): faktur terbaru toko itu yang berisi barang tsb dulu, kalau qty-nya melebihi sisa di faktur itu sisanya diambil dari faktur sebelumnya → **1 retur per faktur** (satu pengajuan bisa jadi beberapa nomor RTR). Aturan sisa sama dengan `retur.html`: faktur bukan `cancelled`, verifikasi NULL/`approved`, sisa = terjual − retur `pending`+`approved`; harga retur = `invoice_items.price` (sama dengan `retur.html`). Semua dalam satu transaksi + advisory lock per toko — gagal satu barang = tidak ada yang tersimpan. Daftar sisa di layar (`fetchStoreData()` + `buildReturnable()`) cuma tampilan, rumusnya harus tetap sama dengan RPC
- Retur masuk `pending`, `source = 'gudang'` — stok & piutang baru berubah setelah admin menyetujui di `retur.html`
- Setelah retur terkirim, **seluruh form dikosongkan** (`resetInputForm()`): toko, faktur, pencarian barang, daftar retur, alasan, catatan, foto — retur berikutnya mulai dari pilih toko lagi supaya tidak salah toko/faktur karena sisa isian sebelumnya. Kalau kirim gagal, isian tetap utuh (cuma sisa qty dimuat ulang)
- Foto dikecilkan di browser (maks 1200px, WebP/JPEG, pola sama dengan foto produk) → bucket privat `return-photos` (1 MB, webp/jpeg). Diunggah sebelum RPC; kalau RPC gagal, foto dihapus lagi (policy owner delete)
- Riwayat: retur milik akun yang login (`created_by_id`), dikelompokkan per pengajuan (`created_at` + toko — satu transaksi, jadi sama persis), nomor RTR + nomor faktur + status per retur + alasan kalau ditolak
- Akun gudang dibuat super_admin di `settings.html` tab **👥 Akun Sales & Gudang** (pilih Jenis Akun saat tambah). `allSales` di halaman itu tetap cuma role sales (dipakai Target Omzet)

### profit-loss.html
- Rekap kas: gunakan `cash_paid`/`transfer_paid` langsung (bukan `payment_method × total`)
- Fallback untuk faktur lama yang belum punya kolom baru

### reports.html
- Pagination tabel pergerakan stok (20 per halaman)
- Super_admin only

### split-csv.html
- Tool mandiri pecah CSV besar, tidak butuh auth

### katalog-cetak.html
- **Brosur PDF (via print browser) untuk toko yang belum terbiasa pakai link katalog online.** Sengaja bukan cara pesan baru — cuma "lihat-lihat", supaya jaminan satuan/jumlah yang benar dari katalog online tidak hilang lagi (toko tetap pesan lewat link pribadinya). Tiap kartu produk tampil **harga satuan DAN harga lusin** (harga lusin cuma kalau `unit = 'pcs'`, sama seperti aturan di `pricing.js`/`hargaLusin()`)
- **Dua mode**, ditentukan oleh query string `?ids=`:
  - **Otomatis** (tanpa `?ids=`, diakses dari tombol **🖨️ Cetak Katalog Terlaris** di toolbar `products.html`): produk **terlaris company-wide** (bukan per toko, satu brosur untuk semua) — diranking dari total `quantity` terjual di `invoice_items` lintas semua faktur (faktur `cancelled`/`verification_status = 'rejected'` tidak ikut dihitung, sama seperti aturan di katalog online). Produk nonaktif atau `stock_quantity <= 0` **disaring keluar** — brosur tidak boleh menawarkan yang tidak bisa dibeli. Jumlah produk yang ditampilkan bisa diatur (default 24). Diagregasi di browser (dua `fetchAll()`: `invoices` + `invoice_items`) — **tidak ada fungsi SQL/migration baru**
  - **Manual** (`?ids=uuid1,uuid2,...`, diakses dari tombol **🖨️ Buat PDF** di bar aksi seleksi `products.html`): persis produk yang dicentang admin, urutan sesuai urutan dicentang. **Tidak disaring** aktif/stok — dicentang tangan berarti memang mau ditampilkan; kalau ada yang tidak ketemu (sudah dihapus), pesan status bilang berapa yang hilang tapi sisanya tetap tampil. Kontrol "Jumlah produk" disembunyikan di mode ini (jumlahnya sudah pasti dari yang dicentang)
- Foto pakai `photo_thumb_path` dari bucket `product-photos` (fallback kotak inisial kalau belum ada foto)
- **Harga coret (PROMO)**: sebuah produk dapat badge 🔴 PROMO + harga asli dicoret kalau punya aturan diskon aktif dari `product_discount_rules` yang **tanpa syarat qty/nominal minimum sungguhan** (`min_qty <= 1` dihitung tanpa syarat juga — 1 pcs adalah jumlah pesanan terkecil yang memang bisa dipesan, jadi bukan syarat nyata; `min_amount` harus `0`) **dan umum** (bukan khusus 1-2 customer via `product_discount_rule_customers`) — cuma kombinasi itu yang harganya pasti sama untuk siapa pun yang lihat brosur, tanpa perlu tahu qty pesanan atau siapa customernya. Berlaku untuk aturan **PRODUK maupun GRUP VARIAN** (lewat `discount_group_members`) — grup **tidak** otomatis dilewati, cuma grup yang **ada syarat qty/nominal** yang dilewati (itu dihitung dari total qty satu grup **di satu faktur**, lihat `findBestDiscountRule()` di `invoices.html` — tidak ada artinya tanpa keranjang; tapi kalau grupnya sendiri tanpa syarat, keanggotaannya tidak relevan lagi, diskonnya memang pasti berlaku ke tiap anggota). Aturan produk menang atas aturan grup kalau produk itu punya keduanya (sama seperti prioritas di `findBestDiscountRule()`). Kalau ada beberapa aturan yang cocok, dipilih yang harganya paling rendah. Rumus hitung (`hargaSetelahDiskon()`) sama persis dengan `invoices.html`: `percent` dihitung bertingkat (`discount_value2` dari hasil `discount_value`, bukan dijumlah), `nominal` dipotong langsung per pcs (dibatasi minimal 0) — hasilnya dibulatkan NAIK ke kelipatan 100 (`Math.ceil`, sama seperti aturan subtotal & harga lusin di seluruh ERP ini), karena persentase dikali harga jarang pas ratusan. Harga lusin ikut dicoret & dihitung ulang lewat `hargaLusin()` dari harga pcs promo yang **sudah dibulatkan** itu, bukan dari angka mentah sebelum dibulatkan
- Cetak/simpan PDF pakai `window.print()` bawaan browser (`@page { size: A4 }`) — pola sama dengan print faktur, area di luar `#print-area` (sidebar, topbar, kontrol) otomatis disembunyikan lewat `@media print`
- Tidak lewat nav sidebar utama di kedua mode
- `requireAdmin()`

## Page–Role Matrix

| Halaman | Auth | Role |
|---|---|---|
| `login.html`, `setup.html`, `split-csv.html` | — | Public |
| `sales.html` | `requireSales()` | Semua role kecuali gudang (dilempar ke `retur-toko.html`) |
| `retur-toko.html` | `requireGudang()` | gudang + admin + super_admin |
| `index.html`, `products.html`, `customers.html`, `invoices.html`, `verify-invoices.html`, `purchases.html`, `stock-out.html`, `retur.html`, `wishlist.html`, `discounts.html`, `katalog-cetak.html` | `requireAdmin()` | admin + super_admin |
| `reports.html`, `profit-loss.html`, `piutang.html`, `laporan-sales.html`, `settings.html`, `jadwal-kunjungan.html` | `requireSuperAdmin()` | super_admin only |

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
| `supabase_migration26.sql` | View `public_catalog_products` (read-only, kolom aman saja) untuk katalog publik di domain terpisah (`diana-kosmetik-katalog`) |
| `supabase_migration27.sql` | Tabel `sales_visits` + bucket Storage privat `visit-photos` untuk fitur Absen Kunjungan (foto+GPS+jam) di `sales.html` |
| `supabase_migration28.sql` | Kolom `item_discount2` di `invoice_items` — diskon bertingkat per item (contoh 20%+5%) di `invoices.html` |
| `supabase_migration29.sql` | Kolom `discount_value2` di `product_discount_rules` — diskon bertingkat di aturan diskon `discounts.html`, ikut ke-auto-apply ke faktur |
| `supabase_migration30.sql` | (Digantikan migration31) Kolom `customer_id` tunggal di `product_discount_rules` — diskon khusus 1 customer |
| `supabase_migration31.sql` | Ganti pendekatan migration30 jadi tabel junction `product_discount_rule_customers` (many-to-many) — 1 aturan diskon bisa berlaku buat beberapa toko sekaligus. Kolom `customer_id` lama di-drop |
| `supabase_migration35.sql` | Kolom `latitude`/`longitude`/`location_updated_at`/`location_source` di `customers` + fungsi `set_customer_location_from_visit()` — titik GPS toko ditempel otomatis dari Absen Kunjungan, dipakai link "Buka Maps" di `sales.html` & `customers.html` |
| `supabase_migration36.sql` | Tabel `product_cost_logs` + trigger `log_product_cost_change` di `products` — catat tiap perubahan `products.cost` (lama→baru, sumber, siapa, kapan). Sumber ditandai lewat GUC transaction-local `app.cost_source` (`increase_stock_on_purchase` → `purchase`, `edit_purchase()` ditulis ulang + `set_config()` → `purchase_edit`, sisanya `manual`). Termasuk backfill 1 baris awal per produk. Jalankan setelah migration34 |
| `supabase_migration34.sql` | **Wajib untuk Edit PO.** Fungsi `edit_purchase()` — seluruh rangkaian edit pembelian jadi satu transaksi (sebelumnya 4 panggilan terpisah dari browser: koneksi putus di tengah = stok berkurang + item PO hilang). Sekaligus `increase_stock_on_purchase()` cuma menulis `products.cost` kalau PO itu memang pembelian terbaru untuk produk tsb — sebelumnya edit PO lama menarik mundur harga modal |
| `supabase_migration43.sql` | **Wajib untuk Retur Toko.** Role `gudang`, kolom `returns.source`/`created_by_id`/`photo_path`, RPC `create_store_return()` (faktur dipilih karyawan atau dicari otomatis; `p_invoice_id` — versi awal 5 parameter di-DROP, aman dijalankan ulang), **RLS di `returns` & `return_items`** (sales tidak bisa menulis retur), trigger `guard_user_profile_role` (role akun cuma bisa diubah super_admin — `settings.html` sekarang menyimpan profil akun baru setelah sesi super_admin dipulihkan), bucket privat `return-photos`. Jalankan setelah migration22 |
| `supabase_migration42.sql` | **Wajib untuk Jadwal Kunjungan.** Tabel `visit_schedules` + setting `visit_target_per_day` (default 12) + `jadwal_tab_visible_for` (default kosong = tab Hari Ini belum tampil ke siapa pun). Tanpa ini tab Hari Ini di `sales.html` kosong dan `jadwal-kunjungan.html` menampilkan pesan error |
