async function requireAdmin() {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) { window.location.href = 'login.html'; return null; }
  const { data: profile } = await supabase.from('user_profiles').select('*').eq('id', session.user.id).single();
  if (!profile || !profile.is_active) { await supabase.auth.signOut(); window.location.href = 'login.html'; return null; }
  if (profile.role !== 'admin') { window.location.href = 'sales.html'; return null; }
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
}
