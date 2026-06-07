// sw.js — Service Worker for Afya Nyumbani PWA
// Caches the app shell so the app opens instantly and works offline.
// PowerSync handles data sync separately via its own IndexedDB storage.

const CACHE     = 'afya-nyumbani-v1';
const PRECACHE  = ['/', '/index.html', '/manifest.json',
                   '/icons/icon-192.png', '/icons/icon-512.png'];

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE).then(c => c.addAll(PRECACHE)).then(() => self.skipWaiting())
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
  // Only handle GET requests for same-origin or CDN assets
  if (e.request.method !== 'GET') return;

  const url = new URL(e.request.url);

  // Let Supabase / PowerSync API calls go straight to network
  if (url.hostname.includes('supabase.co') ||
      url.hostname.includes('powersync.journeyapps.com') ||
      url.hostname.includes('esm.sh')) {
    return;
  }

  // Network-first for HTML (get latest app), cache-first for assets
  if (e.request.destination === 'document' || url.pathname === '/') {
    e.respondWith(
      fetch(e.request)
        .then(r => { caches.open(CACHE).then(c => c.put(e.request, r.clone())); return r; })
        .catch(() => caches.match('/index.html'))
    );
  } else {
    e.respondWith(
      caches.match(e.request).then(cached => cached || fetch(e.request))
    );
  }
});
