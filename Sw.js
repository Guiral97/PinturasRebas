// Service worker de Pinturas Rebas: guarda la app en el equipo para que la
// caja abra y venda sin internet. Las consultas a Supabase NO se guardan aquí
// (la caja maneja su propio catálogo y su cola de ventas en IndexedDB).
// Al cambiar archivos de la app, sube este número para forzar la actualización.
const VERSION = 'rebas-v2';

const APP = ['./', 'index.html', 'config.js', 'recibo.js'];
const LIBRERIAS = [
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2',
  'https://cdn.jsdelivr.net/npm/html5-qrcode@2.3.8/html5-qrcode.min.js'
];
const HOSTS_LIBRERIAS = ['cdn.jsdelivr.net', 'fonts.googleapis.com', 'fonts.gstatic.com'];

self.addEventListener('install', (e) => {
  e.waitUntil((async () => {
    const cache = await caches.open(VERSION);
    // Uno por uno: si alguno falla, los demás igual quedan guardados
    await Promise.all([...APP, ...LIBRERIAS].map(async (url) => {
      try {
        const r = await fetch(url, { cache: 'no-cache' });
        if (r.ok) await cache.put(url, r);
      } catch (_) { /* se guardará la próxima vez que se pida con internet */ }
    }));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', (e) => {
  e.waitUntil((async () => {
    const nombres = await caches.keys();
    await Promise.all(nombres.filter((n) => n !== VERSION).map((n) => caches.delete(n)));
    await self.clients.claim();
  })());
});

// Primero la red (para recibir cambios), con límite de tiempo; si no hay, lo guardado
async function redPrimero(req) {
  const cache = await caches.open(VERSION);
  try {
    const r = await Promise.race([
      fetch(req),
      new Promise((_, mal) => setTimeout(() => mal(new Error('tiempo')), 4000))
    ]);
    if (r && r.ok) cache.put(req, r.clone());
    return r;
  } catch (_) {
    const guardado = await cache.match(req, { ignoreSearch: true });
    if (guardado) return guardado;
    if (req.mode === 'navigate') {
      const inicio = await cache.match('index.html');
      if (inicio) return inicio;
    }
    return new Response('Sin conexión', { status: 503, headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
  }
}

// Librerías con versión fija y fuentes: lo guardado primero
async function guardadoPrimero(req) {
  const cache = await caches.open(VERSION);
  const guardado = await cache.match(req);
  if (guardado) return guardado;
  try {
    const r = await fetch(req);
    if (r && (r.ok || r.type === 'opaque')) cache.put(req, r.clone());
    return r;
  } catch (_) {
    return new Response('', { status: 503 });
  }
}

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.hostname.endsWith('.supabase.co') || url.hostname.endsWith('.supabase.in')) return;   // datos: siempre en vivo
  if (url.origin === self.location.origin) { e.respondWith(redPrimero(req)); return; }
  if (HOSTS_LIBRERIAS.includes(url.hostname)) { e.respondWith(guardadoPrimero(req)); return; }
});
