// ============================================================
// UTILITY FUNCTIONS
// ============================================================

// Klik di mana saja pada input tanggal langsung buka date picker
document.addEventListener('click', e => {
  if (e.target.type === 'date') {
    try { e.target.showPicker(); } catch (_) {}
  }
});

function formatCurrency(amount) {
  return new Intl.NumberFormat('id-ID', {
    style: 'currency',
    currency: 'IDR',
    minimumFractionDigits: 0
  }).format(amount || 0);
}

// Harga per lusin (1 lusin = 12 pcs), dibulatkan ke kelipatan 100.
// Formula sama dengan yang dipakai di products.html & sales.html.
function hargaLusin(price) {
  return Math.round((Number(price || 0) * 12) / 100) * 100;
}

function formatDate(dateStr) {
  if (!dateStr) return '-';
  return new Intl.DateTimeFormat('id-ID', {
    day: '2-digit', month: 'short', year: 'numeric'
  }).format(new Date(dateStr));
}


function todayISO() {
  return new Date().toISOString().split('T')[0];
}

function showToast(message, type = 'success') {
  const existing = document.querySelector('.toast');
  if (existing) existing.remove();

  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;
  const icons = { success: '✓', error: '✕', warning: '⚠' };
  toast.innerHTML = `<span class="toast-icon">${icons[type] || icons.success}</span><span>${message}</span>`;
  document.body.appendChild(toast);

  requestAnimationFrame(() => toast.classList.add('show'));
  setTimeout(() => {
    toast.classList.remove('show');
    setTimeout(() => toast.remove(), 300);
  }, 3500);
}

function showConfirm(message) {
  return confirm(message);
}

function showFullLoading(message) {
  let el = document.getElementById('full-loading-overlay');
  if (!el) {
    el = document.createElement('div');
    el.id = 'full-loading-overlay';
    el.className = 'full-loading-overlay';
    el.innerHTML = '<div class="full-loading-box"><span class="spinner spinner-lg"></span><span class="full-loading-text"></span></div>';
    document.body.appendChild(el);
  }
  el.querySelector('.full-loading-text').textContent = message || 'Memproses...';
  el.classList.add('show');
}

function hideFullLoading() {
  const el = document.getElementById('full-loading-overlay');
  if (el) el.classList.remove('show');
}

function setLoading(btn, loading) {
  if (!btn) return;
  if (loading) {
    btn.disabled = true;
    btn.dataset.original = btn.innerHTML;
    btn.innerHTML = '<span class="spinner"></span> Memproses...';
  } else {
    btn.disabled = false;
    btn.innerHTML = btn.dataset.original || btn.innerHTML;
  }
}

function openModal(id) {
  const el = document.getElementById(id);
  if (el) { el.classList.add('open'); document.body.style.overflow = 'hidden'; }
}

function closeModal(id) {
  const el = document.getElementById(id);
  if (el) { el.classList.remove('open'); document.body.style.overflow = ''; }
}

function escapeHtml(str) {
  const div = document.createElement('div');
  div.appendChild(document.createTextNode(str || ''));
  return div.innerHTML;
}

function stockBadge(qty, min) {
  if (qty <= 0) return `<span class="badge badge-danger">Habis</span>`;
  if (qty <= min) return `<span class="badge badge-warning">Menipis</span>`;
  return `<span class="badge badge-success">Normal</span>`;
}

function debounce(fn, delay = 400) {
  let timer;
  return (...args) => { clearTimeout(timer); timer = setTimeout(() => fn(...args), delay); };
}

// ── NUMBER FORMAT (1.000 / 10.000 / 100.000) ─────────────────
// Tambahkan atribut data-number pada input untuk auto-format
// Gunakan parseFormattedNumber() saat membaca nilainya
function parseFormattedNumber(val) {
  return parseFloat(String(val || '').replace(/\./g, '').replace(',', '.')) || 0;
}

function applyNumberFormat(input) {
  const raw = input.value.replace(/[^0-9]/g, '');
  if (!raw) { input.value = ''; return; }
  // Simpan posisi cursor relatif dari kanan agar tidak loncat
  const rightOffset = input.value.length - (input.selectionStart || 0);
  const formatted = parseInt(raw, 10).toLocaleString('id-ID');
  input.value = formatted;
  // Kembalikan posisi cursor
  const newPos = Math.max(0, formatted.length - rightOffset);
  try { input.setSelectionRange(newPos, newPos); } catch (_) {}
}

// Global handler: input dengan data-number otomatis diformat
document.addEventListener('input', e => {
  if (e.target.hasAttribute('data-number')) applyNumberFormat(e.target);
});

// ── FETCH ALL (bypass Supabase 1000 row limit) ────────────────
// Usage: const { data, error } = await fetchAll(() =>
//   supabase.from('products').select('*').eq('is_active', true).order('name')
// );
async function fetchAll(queryFn, pageSize = 1000) {
  let from = 0, all = [];
  while (true) {
    const { data, error } = await queryFn().range(from, from + pageSize - 1);
    if (error) return { data: null, error };
    all = all.concat(data || []);
    if (!data || data.length < pageSize) break;
    from += pageSize;
  }
  return { data: all, error: null };
}

// ── TOMSELECT DROPDOWN: tinggi adaptif + auto-flip ke atas ────
// Patch global — berlaku ke semua instance TomSelect di semua halaman,
// tidak perlu ubah kode init di masing-masing halaman.
// Masalah yang dibenahi: dropdown fixed 220px (cuma ~6 baris) dan kalau
// baris item ada di bawah layar, list-nya kepotong viewport jadi susah discroll.
(function patchTomSelectDropdown() {
  if (typeof TomSelect === 'undefined') return;

  const MIN_H = 180;  // minimal tinggi list sebelum memutuskan flip ke atas
  const MAX_H = 420;  // batas atas biar nggak makan seluruh layar
  const GAP   = 12;   // jarak aman ke tepi viewport

  function fit(ts) {
    const dd = ts.dropdown;
    if (!dd || !ts.isOpen) return;
    const content = ts.dropdown_content || dd.querySelector('.ts-dropdown-content');
    if (!content) return;

    const rect  = ts.control.getBoundingClientRect();
    const below = window.innerHeight - rect.bottom - GAP;
    const above = rect.top - GAP;
    const flip  = below < MIN_H && above > below;
    const avail = flip ? above : below;

    // Clamp terakhir ke tinggi viewport supaya di layar pendek pun tidak meluber
    const h = Math.min(MAX_H, Math.max(MIN_H, avail), window.innerHeight - 2 * GAP);
    content.style.maxHeight = h + 'px';

    if (ts.settings.dropdownParent === 'body') {
      // TomSelect sudah menaruhnya tepat di bawah control; kalau flip, geser ke atas
      if (flip) dd.style.top = (rect.top + window.scrollY - dd.offsetHeight - 2) + 'px';
    } else {
      // Dropdown absolute di dalam .ts-wrapper
      dd.style.top    = flip ? 'auto' : '';
      dd.style.bottom = flip ? '100%' : '';
    }
  }

  const _position = TomSelect.prototype.positionDropdown;
  TomSelect.prototype.positionDropdown = function () {
    const r = _position.apply(this, arguments);
    fit(this);
    return r;
  };

  // Jumlah opsi berubah tiap ketik → tinggi & posisi dihitung ulang
  const _refresh = TomSelect.prototype.refreshOptions;
  TomSelect.prototype.refreshOptions = function () {
    const r = _refresh.apply(this, arguments);
    if (this.isOpen) this.positionDropdown();
    return r;
  };

  // Dropdown dengan dropdownParent:'body' tidak ikut scroll container-nya.
  // Reposisi selama terbuka supaya tidak "lepas" dari input saat modal discroll.
  let openTS = null;
  const reposition = () => { if (openTS && openTS.isOpen) openTS.positionDropdown(); };

  const _open = TomSelect.prototype.open;
  TomSelect.prototype.open = function () {
    const r = _open.apply(this, arguments);
    if (this.isOpen) {
      openTS = this;
      this.positionDropdown();
      window.addEventListener('scroll', reposition, true);
      window.addEventListener('resize', reposition);
    }
    return r;
  };

  const _close = TomSelect.prototype.close;
  TomSelect.prototype.close = function () {
    const r = _close.apply(this, arguments);
    if (openTS === this) {
      openTS = null;
      window.removeEventListener('scroll', reposition, true);
      window.removeEventListener('resize', reposition);
    }
    return r;
  };
})();

// ── RETUR vs FAKTUR ───────────────────────────────────────────
// Retur TIDAK mengubah invoices.total — nilai faktur asli harus tetap utuh untuk
// audit & cetak ulang. Konsekuensinya setiap halaman yang menghitung tagihan,
// piutang, atau omzet wajib mengurangkan nilai retur sendiri lewat helper ini.
//
// Hanya retur 'approved' yang mengurangi tagihan:
//   pending  = belum tentu diterima, stoknya juga belum dikembalikan
//   rejected = jelas tidak mengurangi apa pun
// (Tabel returns tidak punya status 'cancelled'. Filter lama .neq('status','cancelled')
//  lolos semua, jadi retur yang DITOLAK pun ikut memotong tagihan.)

// Map { invoice_id: total_nilai_retur } untuk sekumpulan faktur.
async function fetchReturnTotals(invoiceIds) {
  const map = {};
  const ids = (invoiceIds || []).filter(Boolean);
  if (!ids.length) return map;
  const CHUNK = 200;   // jaga panjang URL query .in()
  for (let i = 0; i < ids.length; i += CHUNK) {
    const { data, error } = await supabase.from('returns')
      .select('invoice_id,total_return_value')
      .in('invoice_id', ids.slice(i, i + CHUNK))
      .eq('status', 'approved');
    if (error) { console.error('fetchReturnTotals:', error.message); return map; }
    (data || []).forEach(r => {
      if (!r.invoice_id) return;
      map[r.invoice_id] = (map[r.invoice_id] || 0) + Number(r.total_return_value || 0);
    });
  }
  return map;
}

// Rincian retur satu faktur: total, qty per produk, dan daftar returnya.
async function fetchReturnDetail(invoiceId) {
  const kosong = { total: 0, qtyByProduct: {}, list: [] };
  if (!invoiceId) return kosong;
  const { data, error } = await supabase.from('returns')
    .select('id,return_number,return_date,total_return_value,return_items(product_id,product_name,quantity,unit_price,subtotal)')
    .eq('invoice_id', invoiceId)
    .eq('status', 'approved');
  if (error) { console.error('fetchReturnDetail:', error.message); return kosong; }

  const out = { total: 0, qtyByProduct: {}, list: data || [] };
  (data || []).forEach(r => {
    out.total += Number(r.total_return_value || 0);
    (r.return_items || []).forEach(it => {
      if (!it.product_id) return;
      out.qtyByProduct[it.product_id] = (out.qtyByProduct[it.product_id] || 0) + Number(it.quantity || 0);
    });
  });
  return out;
}

// ── SUBTOTAL BARIS FAKTUR ─────────────────────────────────────
// Satu formula dipakai SEMUA halaman (invoices, sales, verify-invoices) supaya
// faktur yang dibuat sales dan yang dibuat admin menghasilkan angka yang sama.
//
// Dulu sales.html menurunkan subtotal dari harga satuan yang sudah dibulatkan ke
// rupiah (karena kolom Harga Satuan di sana menampilkan harga setelah diskon),
// jadi ada DUA pembulatan: round() harga satuan lalu ceil() ke kelipatan 100.
// invoices.html cuma satu. Hasilnya beda Rp 100 pada ~14% kombinasi harga/qty/diskon.
// Sekarang subtotal selalu diturunkan dari harga katalog + diskon, sekali pembulatan.
//
// Diskon persen bertingkat/compound, bukan dijumlah: 20%+5% != 25%.
// Diskon nominal itu per-pcs: dikurangi dari harga satuan dulu, baru dikali qty.
function hitungSubtotalBaris(qty, price, discType, disc, disc2) {
  const q  = Number(qty)   || 0;
  const p  = Number(price) || 0;
  const d1 = Math.max(0, Number(disc)  || 0);
  const d2 = Math.max(0, Number(disc2) || 0);
  if (discType === 'nominal') {
    return Math.max(0, Math.ceil((q * Math.max(0, p - d1)) / 100) * 100);
  }
  const a = Math.min(d1, 100), b = Math.min(d2, 100);
  return Math.max(0, Math.ceil((q * p * (1 - a / 100) * (1 - b / 100)) / 100) * 100);
}
