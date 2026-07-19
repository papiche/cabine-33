// ATOM4LOVE PWA Service Worker — v1.0 build 202607190138
const CACHE = 'atom4love-1.0-202607190138';
const ASSETS = ["./", "./index.html", "./index.audio.position.worklet.js", "./index.audio.worklet.js", "./index.js", "./nostr.bundle.js", "./index.wasm", "./index.pck", "./icon.png", "./index.apple-touch-icon.png", "./index.icon.png", "./index.png", "./manifest.json"];

self.addEventListener('install', ev => {
  ev.waitUntil(
    caches.open(CACHE)
      .then(c => c.addAll(ASSETS))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', ev => {
  ev.waitUntil(
    caches.keys()
      .then(ks => Promise.all(
        ks.filter(k => k !== CACHE).map(k => {
          console.log('[SW] Suppression ancien cache:', k);
          return caches.delete(k);
        })
      ))
      .then(() => {
        // Notifier tous les clients qu'une mise à jour est disponible
        self.clients.matchAll().then(clients =>
          clients.forEach(c => c.postMessage({ type: 'SW_UPDATED', version: '1.0' }))
        );
        return self.clients.claim();
      })
  );
});

self.addEventListener('fetch', ev => {
  ev.respondWith(
    caches.match(ev.request).then(cached => {
      if (cached) return cached;
      return fetch(ev.request).then(resp => {
        const clone = resp.clone();
        caches.open(CACHE).then(c => c.put(ev.request, clone));
        return resp;
      });
    })
  );
});
