const CACHE = 'uddiana-v2';
const SHELL = [
  '/',
  '/sales.html',
  '/login.html',
  '/manifest.json',
  '/logo.png',
  '/favicon.ico',
  '/js/config.js',
  '/js/utils.js',
  '/js/auth.js',
  '/css/style.css',
];

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  const url = new URL(e.request.url);
  if (url.hostname.includes('supabase') || url.hostname.includes('cdn.jsdelivr.net')) return;

  const isHTML = url.origin === self.location.origin &&
    (url.pathname === '/' || url.pathname.endsWith('.html'));

  if (isHTML) {
    // Network-first untuk HTML — selalu fresh, fallback ke cache kalau offline
    e.respondWith(
      fetch(e.request)
        .then(res => {
          if (res.ok) {
            const clone = res.clone();
            caches.open(CACHE).then(c => c.put(e.request, clone));
          }
          return res;
        })
        .catch(() => caches.match(e.request))
    );
  } else {
    // Cache-first untuk JS/CSS/gambar
    e.respondWith(
      caches.match(e.request).then(cached => {
        const network = fetch(e.request).then(res => {
          if (res.ok && url.origin === self.location.origin) {
            const clone = res.clone();
            caches.open(CACHE).then(c => c.put(e.request, clone));
          }
          return res;
        });
        return cached || network;
      })
    );
  }
});
