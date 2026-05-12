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

function formatDate(dateStr) {
  if (!dateStr) return '-';
  return new Intl.DateTimeFormat('id-ID', {
    day: '2-digit', month: 'short', year: 'numeric'
  }).format(new Date(dateStr));
}

function formatDateInput(dateStr) {
  if (!dateStr) return '';
  return new Date(dateStr).toISOString().split('T')[0];
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
