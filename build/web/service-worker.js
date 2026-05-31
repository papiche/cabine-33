const CACHE = 'atom4love-v1';
const ASSETS = ["./", "./index.html", "./index.audio.position.worklet.js", "./index.audio.worklet.js", "./index.js", "./nostr.bundle.js", "./service-worker.js", "./index.wasm", "./index.pck", "./icon.png", "./index.apple-touch-icon.png", "./index.icon.png", "./index.png"];

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
      .then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
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
