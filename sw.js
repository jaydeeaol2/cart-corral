// Minimal service worker — its only real job is to exist, since some
// browsers (Chrome/Android) require a registered service worker as
// part of their "installable PWA" criteria alongside the manifest.
// It caches the app shell so the icon/name show up instantly and the
// app opens even on a flaky connection; live data always comes from
// Supabase over the network, not from this cache.

const CACHE_NAME = 'cart-corral-shell-v1';
const SHELL_FILES = ['./index.html', './terms.html', './manifest.json'];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(SHELL_FILES)).catch(()=>{})
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  // Network-first for everything (this app is live-data-driven);
  // fall back to cache only if the network fails.
  event.respondWith(
    fetch(event.request).catch(() => caches.match(event.request))
  );
});
