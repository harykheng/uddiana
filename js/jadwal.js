// ============================================================
// JADWAL KUNJUNGAN — helper bersama jadwal-kunjungan.html & sales.html
// Tabel: visit_schedules (supabase_migration42.sql)
// ============================================================

// Index = ISO day of week (1 = Senin ... 7 = Minggu), sama dengan kolom day_of_week
const HARI = ['', 'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];

// Toko yang PO-nya kurang dari sekian hari lalu tidak perlu didatangi minggu ini.
// 10, bukan 7: PO yang masuk di luar hari kunjungan (mis. lewat WA hari Sabtu)
// baru 9 hari saat jadwal Senin depannya, jadi toko itu belum perlu didatangi.
const JADWAL_JEDA_PO_HARI = 10;
// Riwayat faktur yang diambil untuk "PO terakhir" — lebih lama dari ini ditampilkan
// sebagai "tidak ada PO 90 hari terakhir"
const JADWAL_RIWAYAT_HARI = 90;

function isoDow(date) {
  const d = date.getDay();
  return d === 0 ? 7 : d;
}

// Tanggal LOKAL (WIB), bukan UTC. todayISO() di utils.js pakai toISOString(), jadi
// sebelum jam 07:00 WIB tanggalnya masih kemarin — padahal sales berangkat pagi.
function localDateISO(date = new Date()) {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function parseLocalDate(iso) {
  const [y, m, d] = String(iso).slice(0, 10).split('-').map(Number);
  return new Date(y, m - 1, d);
}

function addDaysISO(iso, n) {
  const d = parseLocalDate(iso);
  d.setDate(d.getDate() + n);
  return localDateISO(d);
}

// Selisih hari kalender a - b (dua-duanya 'YYYY-MM-DD')
function daysBetweenISO(a, b) {
  return Math.round((parseLocalDate(a) - parseLocalDate(b)) / 86400000);
}

// Sama dengan termDays() di piutang.html: 'cod' = 0, '14_days' = 14, dst
function jadwalTermDays(term) {
  if (!term || term === 'cod') return 0;
  return parseInt(term) || 0;
}

function namaToko(c) {
  if (!c) return '—';
  return c.store_name ? `${c.store_name} — ${c.name}` : c.name;
}

// "Sen, 5 Okt"
function formatTanggalPendek(iso) {
  const d = parseLocalDate(iso);
  const bln = ['Jan','Feb','Mar','Apr','Mei','Jun','Jul','Agu','Sep','Okt','Nov','Des'];
  return `${HARI[isoDow(d)].slice(0, 3)}, ${d.getDate()} ${bln[d.getMonth()]}`;
}

// Kumpulkan fakta faktur per customer, relatif terhadap refISO (hari yang dilihat):
//   { [customer_id]: {
//       lastPo:  faktur terakhir SEBELUM refISO   { invoice_date, total, sales_name }
//       poOnRef: faktur di tanggal refISO itu sendiri (PO hasil kunjungan hari ini)
//       overdueSum, overdueCount: sisa tagihan yang jatuh tempo <= refISO
//   } }
// PO dihitung dari semua sumber (sales, admin, WA, katalog) — yang penting toko
// sudah order. Faktur cancelled / ditolak verifikasi tidak dihitung.
async function fetchVisitFacts(customerIds, refISO) {
  const facts = {};
  const ids = [...new Set((customerIds || []).filter(Boolean))];
  ids.forEach(id => { facts[id] = { lastPo: null, poOnRef: null, overdueSum: 0, overdueCount: 0 }; });
  if (!ids.length) return facts;

  const sejak = addDaysISO(refISO, -JADWAL_RIWAYAT_HARI);
  const CHUNK = 200;   // jaga panjang URL query .in()
  const recent = [], unpaid = [];

  for (let i = 0; i < ids.length; i += CHUNK) {
    const part = ids.slice(i, i + CHUNK);
    const [r1, r2] = await Promise.all([
      fetchAll(() => supabase.from('invoices')
        .select('id,customer_id,invoice_date,total,sales_name')
        .in('customer_id', part)
        .neq('status', 'cancelled')
        .or('verification_status.is.null,verification_status.neq.rejected')
        .gte('invoice_date', sejak)
        .lte('invoice_date', refISO)),
      fetchAll(() => supabase.from('invoices')
        .select('id,customer_id,invoice_date,total,paid_amount,payment_term')
        .in('customer_id', part)
        .eq('status', 'pending')
        .or('verification_status.is.null,verification_status.eq.approved')),
    ]);
    if (r1.error) throw r1.error;
    if (r2.error) throw r2.error;
    recent.push(...r1.data);
    unpaid.push(...r2.data);
  }

  recent.forEach(inv => {
    const f = facts[inv.customer_id];
    if (!f) return;
    if (inv.invoice_date === refISO) {
      if (!f.poOnRef) f.poOnRef = inv;
    } else if (!f.lastPo || inv.invoice_date > f.lastPo.invoice_date) {
      f.lastPo = inv;
    }
  });

  // Retur approved mengurangi tagihan (invoices.total tidak diubah oleh retur)
  const jatuhTempo = unpaid.filter(inv =>
    addDaysISO(inv.invoice_date, jadwalTermDays(inv.payment_term)) <= refISO);
  const returByInv = await fetchReturnTotals(jatuhTempo.map(i => i.id));
  jatuhTempo.forEach(inv => {
    const f = facts[inv.customer_id];
    if (!f) return;
    const sisa = Number(inv.total || 0) - Number(returByInv[inv.id] || 0) - Number(inv.paid_amount || 0);
    if (sisa <= 0) return;
    f.overdueSum += sisa;
    f.overdueCount += 1;
  });

  return facts;
}

// Status satu baris jadwal untuk hari refISO.
//   wajib  = perlu didatangi hari itu
//   reasons = alasan yang ditampilkan ke sales
function computeVisitStatus(schedule, fact, refISO) {
  const f = fact || { lastPo: null, poOnRef: null, overdueSum: 0, overdueCount: 0 };
  const daysSincePo = f.lastPo ? daysBetweenISO(refISO, f.lastPo.invoice_date) : null;
  const recentPo = daysSincePo != null && daysSincePo < JADWAL_JEDA_PO_HARI;
  const overdue = f.overdueSum > 0;
  const wajib = !recentPo || !!schedule.every_week || overdue;

  const reasons = [];
  if (overdue) reasons.push({ icon: '💰', tone: 'danger',
    text: `Tagihan jatuh tempo ${formatCurrency(f.overdueSum)}${f.overdueCount > 1 ? ` (${f.overdueCount} faktur)` : ''}` });
  if (recentPo && schedule.every_week) reasons.push({ icon: '📌', tone: 'info',
    text: `Selalu tiap minggu · PO ${formatTanggalPendek(f.lastPo.invoice_date)}` });
  else if (recentPo && overdue) reasons.push({ icon: '🧾', tone: 'muted',
    text: `PO ${formatTanggalPendek(f.lastPo.invoice_date)} — datang untuk nagih` });
  else if (!recentPo) {
    if (daysSincePo == null) reasons.push({ icon: '🔁', tone: 'warning',
      text: `Tidak ada PO ${JADWAL_RIWAYAT_HARI} hari terakhir` });
    else reasons.push({ icon: '🔁', tone: daysSincePo >= 21 ? 'warning' : 'muted',
      text: `PO terakhir ${daysSincePo} hari lalu (${formatTanggalPendek(f.lastPo.invoice_date)})` });
  }

  // Urutan di daftar wajib: tagihan dulu, lalu yang paling lama tidak order
  const priority = (overdue ? 1e6 : 0) + (daysSincePo == null ? 9999 : daysSincePo);

  return { wajib, recentPo, overdue, daysSincePo, poOnRef: f.poOnRef, lastPo: f.lastPo, reasons, priority };
}
