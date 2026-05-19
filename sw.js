// Avis Basé — Service Worker
// Strategy: network-first for HTML (so updates apply instantly like big social apps),
// cache-first for static assets, no caching for Supabase API calls.
//
// v0.28.0 — Bump VERSION pour buster les caches a chaque release importante.
//           Refonte profils createurs (cover, stats cards, mutual followers, sticky CTA).

const VERSION = 'v0.28.0';
const SHELL_CACHE = `avis-shell-${VERSION}`;
const STATIC_CACHE = `avis-static-${VERSION}`;

const SHELL_ASSETS = [
  '/',
  '/index.html',
  '/manifest.json',
  '/icon.svg',
  '/offline.html'
];

// Install: pre-cache shell
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(SHELL_CACHE)
      .then((cache) => cache.addAll(SHELL_ASSETS))
      .then(() => self.skipWaiting())
  );
});

// Activate: clean old caches
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(
        keys.filter((k) => k !== SHELL_CACHE && k !== STATIC_CACHE)
            .map((k) => caches.delete(k))
      ))
      .then(() => self.clients.claim())
  );
});

// Fetch handler
self.addEventListener('fetch', (event) => {
  const { request } = event;
  const url = new URL(request.url);

  // Skip non-GET
  if (request.method !== 'GET') return;

  // Never cache Supabase, analytics, or external API calls
  if (
    url.hostname.includes('supabase.co') ||
    url.hostname.includes('supabase.in') ||
    url.hostname.includes('cloudflareinsights.com') ||
    url.hostname.includes('google-analytics.com') ||
    url.pathname.startsWith('/rest/') ||
    url.pathname.startsWith('/auth/') ||
    url.pathname.startsWith('/storage/')
  ) {
    return;
  }

  // Cross-origin (fonts, favicons): cache-first
  if (url.origin !== self.location.origin) {
    event.respondWith(cacheFirst(request, STATIC_CACHE));
    return;
  }

  // HTML / SPA shell: network-first (instant updates)
  if (request.mode === 'navigate' || request.destination === 'document' || url.pathname === '/' || url.pathname.endsWith('.html')) {
    event.respondWith(networkFirst(request, SHELL_CACHE));
    return;
  }

  // Static same-origin assets (svg, json, css, js): network-first with cache fallback
  event.respondWith(networkFirst(request, STATIC_CACHE));
});

async function networkFirst(request, cacheName) {
  try {
    const response = await fetch(request);
    if (response && response.ok) {
      const cache = await caches.open(cacheName);
      cache.put(request, response.clone());
    }
    return response;
  } catch (err) {
    const cached = await caches.match(request);
    if (cached) return cached;
    if (request.mode === 'navigate') {
      // v0.26.3 — Essaie d'abord /index.html (SPA), sinon /offline.html
      const fallback = await caches.match('/index.html') || await caches.match('/offline.html');
      if (fallback) return fallback;
    }
    throw err;
  }
}

async function cacheFirst(request, cacheName) {
  const cached = await caches.match(request);
  if (cached) return cached;
  try {
    const response = await fetch(request);
    if (response && response.ok) {
      const cache = await caches.open(cacheName);
      cache.put(request, response.clone());
    }
    return response;
  } catch (err) {
    return cached || Response.error();
  }
}

// Listen for skipWaiting message from page (manual update trigger)
self.addEventListener('message', (event) => {
  if (event.data === 'SKIP_WAITING') self.skipWaiting();
});
