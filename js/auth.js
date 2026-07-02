async function requireAdmin() {
  document.querySelector('.sidebar')?.classList.add('sidebar-loading');
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) { window.location.href = 'login.html'; return null; }
  const { data: profile } = await supabase.from('user_profiles').select('*').eq('id', session.user.id).single();
  if (!profile || !profile.is_active) { await supabase.auth.signOut(); window.location.href = 'login.html'; return null; }
  if (profile.role !== 'admin' && profile.role !== 'super_admin') { window.location.href = 'sales.html'; return null; }
  updateSidebarUser(profile);
  return { session, profile };
}

async function requireSuperAdmin() {
  document.querySelector('.sidebar')?.classList.add('sidebar-loading');
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) { window.location.href = 'login.html'; return null; }
  const { data: profile } = await supabase.from('user_profiles').select('*').eq('id', session.user.id).single();
  if (!profile || !profile.is_active) { await supabase.auth.signOut(); window.location.href = 'login.html'; return null; }
  if (profile.role !== 'super_admin') { window.location.href = 'index.html'; return null; }
  updateSidebarUser(profile);
  return { session, profile };
}

async function requireSales() {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) { window.location.href = 'login.html'; return null; }
  const { data: profile } = await supabase.from('user_profiles').select('*').eq('id', session.user.id).single();
  if (!profile || !profile.is_active) { await supabase.auth.signOut(); window.location.href = 'login.html'; return null; }
  return { session, profile };
}

async function signOut() {
  await supabase.auth.signOut();
  window.location.href = 'login.html';
}

function updateSidebarUser(profile) {
  document.querySelector('.sidebar')?.classList.remove('sidebar-loading');
  const footer = document.querySelector('.sidebar-footer');
  if (!footer) return;
  footer.innerHTML = `
    <div style="display:flex;align-items:center;gap:10px;padding:12px 0 4px">
      <div style="width:32px;height:32px;border-radius:50%;background:var(--primary);display:flex;align-items:center;justify-content:center;color:#fff;font-weight:700;font-size:13px;flex-shrink:0">
        ${profile.name.charAt(0).toUpperCase()}
      </div>
      <div style="flex:1;min-width:0">
        <div style="font-size:12px;font-weight:600;color:#e2e8f0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${escapeHtml(profile.name)}</div>
        <div style="font-size:10px;color:#94a3b8;text-transform:uppercase">${profile.role}</div>
      </div>
    </div>
    <button onclick="signOut()" style="width:100%;margin-top:8px;padding:7px;background:rgba(255,255,255,0.08);border:none;border-radius:6px;color:#94a3b8;font-size:12px;cursor:pointer;transition:background .2s" onmouseover="this.style.background='rgba(255,255,255,0.15)'" onmouseout="this.style.background='rgba(255,255,255,0.08)'">
      🚪 Keluar
    </button>
    <div style="margin-top:8px;font-size:10px;color:#475569;text-align:center">© 2025 StokManager</div>
  `;

  // Super admin: tambah class ke body agar CSS [data-super-admin] tampil
  // Admin biasa: CSS body:not(.is-super-admin) sudah hide otomatis
  if (profile.role === 'super_admin') {
    document.body.classList.add('is-super-admin');
  } else {
    // Sembunyikan nav-label "Laporan" karena semua itemnya hidden untuk admin biasa
    document.querySelectorAll('.nav-label').forEach(label => {
      let next = label.nextElementSibling;
      let hasVisible = false;
      while (next && !next.classList.contains('nav-label')) {
        if (next.classList.contains('nav-item') && !next.hasAttribute('data-super-admin')) {
          hasVisible = true; break;
        }
        next = next.nextElementSibling;
      }
      if (!hasVisible) label.style.display = 'none';
    });
  }

  initMobileSidebar();
}

function initMobileSidebar() {
  // Inject hamburger ke topbar (hanya sekali)
  if (document.getElementById('sidebar-hamburger')) return;

  const topbar = document.querySelector('.topbar');
  if (!topbar) return;

  // Backdrop overlay
  const overlay = document.createElement('div');
  overlay.id = 'sidebar-overlay';
  overlay.onclick = closeMobileSidebar;
  document.body.appendChild(overlay);

  // Hamburger button
  const btn = document.createElement('button');
  btn.id = 'sidebar-hamburger';
  btn.innerHTML = `<span></span><span></span><span></span>`;
  btn.onclick = toggleMobileSidebar;
  topbar.prepend(btn);

  // Tutup sidebar saat klik nav-item di mobile
  document.querySelectorAll('.nav-item').forEach(a => {
    a.addEventListener('click', () => {
      if (window.innerWidth <= 768) closeMobileSidebar();
    });
  });
}

function toggleMobileSidebar() {
  const sidebar = document.querySelector('.sidebar');
  const overlay = document.getElementById('sidebar-overlay');
  const isOpen  = sidebar.classList.contains('sidebar-open');
  if (isOpen) closeMobileSidebar();
  else {
    sidebar.classList.add('sidebar-open');
    overlay.classList.add('sidebar-overlay-show');
    document.body.style.overflow = 'hidden';
  }
}

function closeMobileSidebar() {
  const sidebar = document.querySelector('.sidebar');
  const overlay = document.getElementById('sidebar-overlay');
  sidebar.classList.remove('sidebar-open');
  overlay.classList.remove('sidebar-overlay-show');
  document.body.style.overflow = '';
}
