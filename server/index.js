'use strict';
// Orbyt - matchmaking + WebRTC signaling server (hardened for public use)
const path = require('path');
const fs = require('fs');
const http = require('http');
const crypto = require('crypto');
const express = require('express');
const { Server } = require('socket.io');
const geoip = require('geoip-country'); // offline country lookup (MaxMind GeoLite2) - nothing is sent to third parties

// ------------------------------------------------------------------ config
const env = process.env;
const PROD = env.NODE_ENV === 'production';
const PORT = parseInt(env.PORT || '3000', 10);
const ALLOWED_ORIGINS = (env.ALLOWED_ORIGINS || '').split(',').map((s) => s.trim()).filter(Boolean);
const PROXY_HOPS = parseInt(env.TRUST_PROXY_HOPS || '0', 10); // 1 when directly behind Caddy/nginx
// Header that carries the real visitor IP, set by a proxy you trust (Render/Cloudflare: cf-connecting-ip).
// On Render (it sets RENDER=true) every request passes through Cloudflare, which sets cf-connecting-ip.
const CLIENT_IP_HEADER = (env.CLIENT_IP_HEADER || (env.RENDER ? 'cf-connecting-ip' : '')).toLowerCase();
const DATA_DIR = env.DATA_DIR || path.join(__dirname, 'data');
const IP_SALT = env.IP_SALT || 'dev-salt-change-me';
const BAN_HOURS = parseFloat(env.BAN_HOURS || '72');
const BAN_SCORE = parseInt(env.BAN_SCORE || '3', 10);       // weighted unique reports in 24 h
const MAX_CONN_PER_IP = parseInt(env.MAX_CONN_PER_IP || '20', 10);
const RELAX_AFTER_MS = 8000;                                 // match with anyone after this
const STUN_URLS = (env.STUN_URLS || 'stun:stun.l.google.com:19302,stun:stun1.l.google.com:19302')
  .split(',').map((s) => s.trim()).filter(Boolean);
const TURN_URLS = (env.TURN_URLS || '').split(',').map((s) => s.trim()).filter(Boolean);
const TURN_SECRET = env.TURN_SECRET || '';
const TURN_USERNAME = env.TURN_USERNAME || '';     // static creds (e.g. free Metered / Open Relay TURN)
const TURN_CREDENTIAL = env.TURN_CREDENTIAL || '';

if (PROD && !env.IP_SALT) console.warn('[warn] IP_SALT is not set - set a long random value in production.');
fs.mkdirSync(DATA_DIR, { recursive: true });

// Links / bare domains are blocked in chat and usernames (stops scams, phishing, spam bots).
const LINK_RE = /(?:https?:\/\/|www\.)\S+|\b[a-z0-9-]{2,}\.(?:com|net|org|io|ly|gg|xyz|me|co|ru|tk|cc|info|link|app|shop|top|site|online)\b(?:\/\S*)?/gi;

// --------------------------------------------------------------- utilities
function ipFromReq(req) {
  if (CLIENT_IP_HEADER) { // trusted header only; never fall back to the spoofable X-Forwarded-For
    const v = req.headers[CLIENT_IP_HEADER];
    return v ? String(v).split(',')[0].trim() : (req.socket && req.socket.remoteAddress) || '';
  }
  if (PROXY_HOPS > 0) {
    const xff = String(req.headers['x-forwarded-for'] || '').split(',').map((s) => s.trim()).filter(Boolean);
    if (xff.length) return xff[Math.max(0, xff.length - PROXY_HOPS)];
  }
  return (req.socket && req.socket.remoteAddress) || '';
}
// We never store raw IPs: only a salted hash.
const uidOf = (ip) => crypto.createHmac('sha256', IP_SALT).update(String(ip)).digest('hex').slice(0, 24);

function originOk(req) {
  const origin = req.headers.origin;
  if (!origin) return true; // non-browser client
  if (!PROD && ALLOWED_ORIGINS.length === 0) return true;
  if (ALLOWED_ORIGINS.includes(origin)) return true;
  try { return new URL(origin).host === req.headers.host; } catch (_) { return false; }
}

// ------------------------------------------------- country + display names
const regionNames = (() => { try { return new Intl.DisplayNames(['en'], { type: 'region' }); } catch (_) { return null; } })();
function countryOf(ip) {
  const clean = String(ip || '').replace(/^::ffff:/i, '');
  try {
    const g = geoip.lookup(clean);
    if (g && g.country) {
      let name = g.name || g.country;
      try { name = (regionNames && regionNames.of(g.country)) || name; } catch (_) { /* keep */ }
      return { code: g.country, name };
    }
  } catch (_) { /* fall through */ }
  return { code: '', name: 'Unknown location' };
}
const RESERVED_NAME = /(admin|moderat|support|orbyt|official|staff|anonymous)/i;
// Returns a safe username, or null (= "Anonymous").
function cleanName(raw) {
  if (typeof raw !== 'string') return null;
  let n = raw.normalize('NFKC').replace(/[^\p{L}\p{N} _.\-]/gu, '').replace(/\s+/g, ' ').trim().slice(0, 20);
  if (n.length < 2) return null;
  if (new RegExp(LINK_RE.source, 'i').test(n) || RESERVED_NAME.test(n)) return null;
  return n;
}

// ---------------------------------------------------------- persistent bans
const BANS_FILE = path.join(DATA_DIR, 'bans.json');
const REPORTS_FILE = path.join(DATA_DIR, 'reports.jsonl');
let bans = {}; // uid -> expiry ms
try { bans = JSON.parse(fs.readFileSync(BANS_FILE, 'utf8')); } catch (_) { bans = {}; }
let saveTimer = null;
function saveBans() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    fs.writeFile(BANS_FILE, JSON.stringify(bans), (e) => e && console.error('[bans] save failed', e.message));
  }, 500);
}
function pruneBans() {
  const now = Date.now();
  let changed = false;
  for (const [k, exp] of Object.entries(bans)) if (exp <= now) { delete bans[k]; changed = true; }
  if (changed) saveBans();
}
pruneBans();
setInterval(pruneBans, 3600 * 1000).unref();
const isBanned = (uid) => !!bans[uid] && bans[uid] > Date.now();

// --------------------------------------------------------------- http app
const app = express();
app.disable('x-powered-by');
if (PROXY_HOPS > 0) app.set('trust proxy', PROXY_HOPS);

// Content-Security-Policy: only our own origin plus what Flutter Web needs (CanvasKit + Google Fonts).
// If the page ever goes blank after a Flutter upgrade, set env CSP=off to test, then tell me.
function cspFor(req) {
  const host = String(req.headers.host || '').replace(/[^a-zA-Z0-9.:\-]/g, '');
  const ws = host ? ` wss://${host} ws://${host}` : '';
  return [
    "default-src 'self'",
    "script-src 'self' 'unsafe-inline' 'unsafe-eval' 'wasm-unsafe-eval' https://www.gstatic.com",
    "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
    "font-src 'self' data: https://fonts.gstatic.com https://www.gstatic.com",
    "img-src 'self' data: blob: https:",
    "media-src 'self' blob: mediastream: data:",
    `connect-src 'self'${ws} data: blob: https://fonts.gstatic.com https://fonts.googleapis.com https://www.gstatic.com https://storage.googleapis.com`,
    "worker-src 'self' blob:",
    "child-src 'self' blob:",
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
  ].join('; ');
}

app.use((req, res, next) => {
  if (env.CSP !== 'off') res.setHeader('Content-Security-Policy', cspFor(req));
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  res.setHeader('Permissions-Policy', 'camera=(self), microphone=(self), geolocation=()');
  if (PROD && (req.headers['x-forwarded-proto'] === 'https' || req.secure)) {
    res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
  }
  next();
});

// tiny in-memory HTTP rate limiter (per IP, per minute)
const hits = new Map();
setInterval(() => hits.clear(), 60 * 1000).unref();
function limit(max) {
  return (req, res, next) => {
    const k = ipFromReq(req);
    const n = (hits.get(k) || 0) + 1;
    hits.set(k, n);
    if (n > max) return res.status(429).json({ error: 'too_many_requests' });
    next();
  };
}

const server = http.createServer(app);
const ioOpts = {
  maxHttpBufferSize: 32 * 1024,
  pingTimeout: 20000,
  allowRequest: (req, cb) => cb(null, originOk(req)),
};
if (ALLOWED_ORIGINS.length) ioOpts.cors = { origin: ALLOWED_ORIGINS };
else if (!PROD) ioOpts.cors = { origin: '*' };
const io = new Server(server, ioOpts);

app.get('/health', limit(120), (_req, res) => res.json({ ok: true, online: io.engine.clientsCount }));

// ICE servers. TURN uses short-lived credentials (coturn "use-auth-secret").
app.get('/api/ice', limit(60), (_req, res) => {
  const iceServers = STUN_URLS.map((u) => ({ urls: u }));
  if (TURN_URLS.length && TURN_SECRET) {
    const username = `${Math.floor(Date.now() / 1000) + 3600}:orbyt`;
    const credential = crypto.createHmac('sha1', TURN_SECRET).update(username).digest('base64');
    iceServers.push({ urls: TURN_URLS, username, credential });
  } else if (TURN_URLS.length && TURN_USERNAME && TURN_CREDENTIAL) {
    iceServers.push({ urls: TURN_URLS, username: TURN_USERNAME, credential: TURN_CREDENTIAL });
  }
  res.setHeader('Cache-Control', 'no-store');
  res.json({ iceServers });
});

// ------------------------------------------------ "Buy me a coffee" (optional gifts)
// Card details NEVER touch this server. The visitor types their card on the payment gateway's own hosted
// page (Konnect: bank cards, e-DINAR, wallet) and the gateway settles the money into the owner's account.
// Bank/postal transfer details (CCP / RIB / mobile wallet number) are optional and shown only if you set them.
const KONNECT_KEY = env.KONNECT_API_KEY || '';                          // "walletId:secret" from the Konnect dashboard
const KONNECT_WALLET = env.KONNECT_WALLET_ID || KONNECT_KEY.split(':')[0] || '';
const KONNECT_SANDBOX = env.KONNECT_SANDBOX !== 'false';                // test mode until you set KONNECT_SANDBOX=false
const KONNECT_BASE = (env.KONNECT_BASE_URL ||
  `https://${KONNECT_SANDBOX ? 'api.sandbox' : 'api'}.konnect.network/api/v2`).replace(/\/+$/, '');
const clipText = (v, n) => String(v || '').replace(/[^\p{L}\p{N} .,:+\-_/()@]/gu, '').trim().slice(0, n);
const DONATE_TRANSFER = {
  name: clipText(env.DONATE_NAME, 60),     // account holder
  rib: clipText(env.DONATE_RIB || '10016131101497378895', 40),       // RIB (STB)
  ccp: clipText(env.DONATE_CCP, 40),       // CCP number
  phone: clipText(env.DONATE_PHONE, 24),   // mobile wallet / D17 number
};
const hasTransfer = !!(DONATE_TRANSFER.rib || DONATE_TRANSFER.ccp || DONATE_TRANSFER.phone);
const hasCard = !!(KONNECT_KEY && KONNECT_WALLET);
const DONATE_MIN = 1, DONATE_MAX = 500; // TND

app.get('/api/donate', limit(60), (_req, res) => {
  const transfer = {};
  if (hasTransfer) for (const [k, v] of Object.entries(DONATE_TRANSFER)) if (v) transfer[k] = v;
  res.setHeader('Cache-Control', 'no-store');
  res.json({
    currency: 'TND', min: DONATE_MIN, max: DONATE_MAX, presets: [2, 5, 10, 20],
    card: hasCard, test: hasCard && KONNECT_SANDBOX,
    transfer: hasTransfer ? transfer : null,
  });
});

const donateJson = express.json({ limit: '2kb' });
app.post('/api/donate/checkout', limit(10),
  (req, res, next) => donateJson(req, res, (e) => (e ? res.status(400).json({ error: 'bad_request' }) : next())),
  async (req, res) => {
    if (!originOk(req)) return res.status(403).json({ error: 'forbidden' });
    if (!hasCard) return res.status(503).json({ error: 'card_disabled' });
    const amount = Number(req.body && req.body.amount);
    if (!Number.isFinite(amount) || amount < DONATE_MIN || amount > DONATE_MAX) {
      return res.status(400).json({ error: 'bad_amount' });
    }
    const origin = publicOrigin(req);
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), 10000);
    try {
      const r = await fetch(`${KONNECT_BASE}/payments/init-payment`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Api-Key': KONNECT_KEY },
        body: JSON.stringify({
          receiverWalletId: KONNECT_WALLET,
          token: 'TND',
          amount: Math.round(amount * 1000), // millimes
          type: 'immediate',
          description: 'Orbyt - Buy me a coffee',
          acceptedPaymentMethods: ['wallet', 'bank_card', 'e-DINAR'],
          lifespan: 20, // minutes
          orderId: crypto.randomBytes(8).toString('hex'),
          theme: 'dark',
          successUrl: `${origin}/thanks`,
          failUrl: `${origin}/`,
        }),
        signal: ctl.signal,
      });
      const j = await r.json().catch(() => ({}));
      if (!r.ok || typeof j.payUrl !== 'string') {
        console.error('[donate] gateway refused, status', r.status);
        return res.status(502).json({ error: 'gateway_error' });
      }
      // Only ever send visitors to the gateway's own domain.
      const u = new URL(j.payUrl);
      const okHost = u.protocol === 'https:' && u.hostname.endsWith('konnect.network');
      const testHost = u.host === new URL(KONNECT_BASE).host; // lets the smoke test use a local mock
      if (!okHost && !testHost) {
        console.error('[donate] unexpected payUrl host');
        return res.status(502).json({ error: 'gateway_error' });
      }
      res.setHeader('Cache-Control', 'no-store');
      return res.json({ payUrl: j.payUrl });
    } catch (e) {
      console.error('[donate] gateway unreachable:', e.name);
      return res.status(502).json({ error: 'gateway_error' });
    } finally {
      clearTimeout(timer);
    }
  });

// ------------------------------------------------------------- visitor statistics
// Counts everybody who opens the site (not only people who start a chat). No raw IPs are stored:
// a visitor is a salted hash, and only per-day counters are kept (last 60 days).
const STATS_FILE = path.join(DATA_DIR, 'stats.json');
const STATS_KEY = env.STATS_KEY || '';
const todayStr = () => new Date().toISOString().slice(0, 10);
let stats = { days: {}, total: { views: 0, visitors: 0, chats: 0, lives: 0 }, seen: { day: todayStr(), ids: [] } };
try {
  const raw = JSON.parse(fs.readFileSync(STATS_FILE, 'utf8'));
  if (raw && raw.days && raw.total) stats = { ...stats, ...raw };
} catch (_) { /* first run */ }
let seenToday = new Set(stats.seen && stats.seen.day === todayStr() ? stats.seen.ids : []);
let seenDay = todayStr();
let statsTimer = null;
function saveStats() {
  if (statsTimer) return;
  statsTimer = setTimeout(() => {
    statsTimer = null;
    const keep = Object.keys(stats.days).sort().slice(-60);
    for (const d of Object.keys(stats.days)) if (!keep.includes(d)) delete stats.days[d];
    stats.seen = { day: seenDay, ids: [...seenToday] };
    fs.writeFile(STATS_FILE, JSON.stringify(stats), (e) => e && console.error('[stats] save failed', e.message));
  }, 5000);
  statsTimer.unref();
}
function dayRec() {
  const d = todayStr();
  if (d !== seenDay) { seenDay = d; seenToday = new Set(); }
  return (stats.days[d] = stats.days[d] || { views: 0, visitors: 0, chats: 0, lives: 0, countries: {} });
}
const BOT_RE = /bot|crawl|spider|slurp|preview|facebookexternalhit|whatsapp|telegram|monitor|uptime|curl|wget|python|headless|lighthouse/i;
function countVisit(req) {
  if (BOT_RE.test(String(req.headers['user-agent'] || ''))) return;
  const rec = dayRec();
  rec.views++; stats.total.views++;
  const ip = ipFromReq(req);
  const uid = uidOf(ip);
  if (!seenToday.has(uid)) {
    seenToday.add(uid);
    rec.visitors++; stats.total.visitors++;
    const c = countryOf(ip);
    const code = (c && c.code) || '??';
    rec.countries[code] = (rec.countries[code] || 0) + 1;
  }
  saveStats();
}
function bumpStat(kind) { const r = dayRec(); r[kind] = (r[kind] || 0) + 1; stats.total[kind] = (stats.total[kind] || 0) + 1; saveStats(); }
app.use((req, res, next) => {
  if (req.method === 'GET' && (req.path === '/' || req.path === '/index.html')) countVisit(req);
  next();
});
const statsNow = () => {
  const rec = dayRec();
  return { today: { views: rec.views, visitors: rec.visitors, chats: rec.chats, matched: rec.matched || 0, lives: rec.lives }, total: stats.total, online: io.engine.clientsCount, lives: lives.size };
};
// Public, harmless numbers (shown on the home page)
app.get('/api/visits', limit(60), (_req, res) => {
  res.setHeader('Cache-Control', 'public, max-age=20');
  const n = statsNow();
  res.json({ today: { visitors: n.today.visitors, views: n.today.views }, total: { visitors: n.total.visitors, views: n.total.views }, online: n.online });
});
// Private dashboard: /stats?key=YOUR_STATS_KEY
function statsKeyOk(req) {
  const k = String(req.query.key || '');
  if (!STATS_KEY || !k) return false;
  const h = (x) => crypto.createHash('sha256').update(x).digest();
  return crypto.timingSafeEqual(h(k), h(STATS_KEY));
}
app.get('/api/stats', limit(20), (req, res) => {
  if (!STATS_KEY) return res.status(503).json({ error: 'Set STATS_KEY first' });
  if (!statsKeyOk(req)) return res.status(401).json({ error: 'bad key' });
  res.setHeader('Cache-Control', 'no-store');
  res.json({ now: statsNow(), days: stats.days });
});
app.get('/stats', limit(20), (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Robots-Tag', 'noindex');
  if (!STATS_KEY) return res.status(503).type('text').send('Set the STATS_KEY environment variable (any long secret), redeploy, then open /stats?key=THAT_SECRET');
  if (!statsKeyOk(req)) return res.status(401).type('text').send('Wrong or missing key.');
  const n = statsNow();
  const days = Object.keys(stats.days).sort().reverse().slice(0, 14);
  const fmt = (x) => Number(x || 0).toLocaleString('en-US');
  const top = {};
  for (const d of days) for (const [c, v] of Object.entries(stats.days[d].countries || {})) top[c] = (top[c] || 0) + v;
  const topRows = Object.entries(top).sort((a, b) => b[1] - a[1]).slice(0, 10)
    .map(([c, v]) => `<tr><td>${String(c).replace(/[^A-Za-z?]/g, '')}</td><td>${fmt(v)}</td></tr>`).join('');
  const rows = days.map((d) => { const r = stats.days[d]; return `<tr><td>${d}</td><td>${fmt(r.visitors)}</td><td>${fmt(r.views)}</td><td>${fmt(r.chats)}</td><td>${fmt(r.matched)}</td><td>${fmt(r.lives)}</td></tr>`; }).join('');
  res.type('html').send(`<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="refresh" content="30"><title>Orbyt stats</title>
<style>:root{color-scheme:dark}body{margin:0;padding:20px;background:#05060a;color:#f2f3f8;font:16px system-ui,sans-serif}h1{margin:0 0 4px}h2{margin:28px 0 8px;font-size:17px;color:#9a9cb5}
.g{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px}.c{background:#10121c;border:1px solid #23263a;border-radius:16px;padding:14px}.c b{display:block;font-size:30px;color:#c6ff4d}.c span{color:#9a9cb5;font-size:13px}
table{width:100%;max-width:640px;border-collapse:collapse}td,th{padding:8px 10px;border-bottom:1px solid #23263a;text-align:left}th{color:#9a9cb5;font-weight:600;font-size:13px}.s{color:#9a9cb5;font-size:13px}</style></head><body>
<h1>Orbyt stats</h1><div class="s">Updates every 30 s. Visitors = different people (counted once per day). Page views = every page load.</div>
<h2>Right now</h2><div class="g"><div class="c"><b>${fmt(n.online)}</b><span>online now</span></div><div class="c"><b>${fmt(n.lives)}</b><span>lives running</span></div></div>
<h2>Today</h2><div class="g"><div class="c"><b>${fmt(n.today.visitors)}</b><span>visitors</span></div><div class="c"><b>${fmt(n.today.views)}</b><span>page views</span></div><div class="c"><b>${fmt(n.today.chats)}</b><span>started a chat</span></div><div class="c"><b>${fmt(n.today.lives)}</b><span>went live</span></div></div>
<h2>All time (since the last server reset)</h2><div class="g"><div class="c"><b>${fmt(n.total.visitors)}</b><span>visitors</span></div><div class="c"><b>${fmt(n.total.views)}</b><span>page views</span></div><div class="c"><b>${fmt(n.total.chats)}</b><span>started a chat</span></div><div class="c"><b>${fmt(n.total.lives)}</b><span>lives</span></div></div>
<h2>Last 14 days</h2><table><tr><th>Day</th><th>Visitors</th><th>Page views</th><th>Start</th><th>Matched</th><th>Lives</th></tr>${rows || '<tr><td colspan="5">No data yet</td></tr>'}</table>
<h2>Top countries (14 days)</h2><table><tr><th>Country</th><th>Visitors</th></tr>${topRows || '<tr><td colspan="2">No data yet</td></tr>'}</table>
</body></html>`);
});

// Legal / safety pages, then the built Flutter app
app.get('/robots.txt', (req, res) => res.type('text/plain').send(`User-agent: *\nAllow: /\nDisallow: /api/\nSitemap: ${(req.get('x-forwarded-proto') || req.protocol).split(',')[0]}://${req.get('host')}/sitemap.xml\n`));
app.get('/sitemap.xml', (req, res) => res.type('application/xml').send(`<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><url><loc>${(req.get('x-forwarded-proto') || req.protocol).split(',')[0]}://${req.get('host')}/</loc><changefreq>weekly</changefreq></url></urlset>\n`));
app.use(express.static(path.join(__dirname, 'public'), { extensions: ['html'] }));
// Built Flutter app: client/build/web (local build) or web-dist (committed build for free hosts)
const webDir = [path.join(__dirname, '..', 'client', 'build', 'web'), path.join(__dirname, '..', 'web-dist')]
  .find((d) => fs.existsSync(path.join(d, 'index.html')));
function publicOrigin(req) {
  if (env.PUBLIC_URL) return env.PUBLIC_URL.replace(/\/+$/, '');
  const proto = String(req.headers['x-forwarded-proto'] || req.protocol || 'http').split(',')[0].trim();
  const host = String(req.headers.host || '').replace(/[^a-zA-Z0-9.:\-]/g, '');
  return host ? `${proto === 'https' ? 'https' : 'http'}://${host}` : '';
}
if (webDir) {
  // Fill in the real site address so WhatsApp / Facebook / X show a proper preview card when the link is shared.
  app.get(['/', '/index.html'], (req, res, next) => {
    fs.readFile(path.join(webDir, 'index.html'), 'utf8', (err, html) => {
      if (err) return next();
      res.setHeader('Cache-Control', 'no-cache');
      res.type('html').send(html.replace(/\{\{ORIGIN\}\}/g, publicOrigin(req)));
    });
  });
  app.use(express.static(webDir, {
    setHeaders: (res, file) => {
      const base = path.basename(file);
      if (['index.html', 'flutter_service_worker.js', 'flutter_bootstrap.js', 'version.json'].includes(base)) {
        res.setHeader('Cache-Control', 'no-cache');
      }
    },
  }));
} else {
  app.get('/', (_req, res) => res.type('text').send('Orbyt server is running. Build the client: see README.'));
}

// ------------------------------------------------------------- matchmaking
let waiting = []; // [{socket, interests, relaxed, timer}]
const partners = new Map();   // socket.id -> partner socket.id
const chatLogs = new Map();   // pairKey -> last messages (evidence for reports only)
const reportsAgainst = new Map(); // uid -> Map(reporterUid -> {w, ts})
const connPerUid = new Map();

const connRate = new Map();
setInterval(() => connRate.clear(), 60 * 1000).unref();

const pairKey = (a, b) => (a < b ? `${a}|${b}` : `${b}|${a}`);
const cleanInterests = (list) =>
  Array.isArray(list)
    ? [...new Set(list.map((x) => String(x).toLowerCase().trim().slice(0, 24)).filter(Boolean))].slice(0, 5)
    : [];
const overlap = (a, b) => a.filter((x) => b.includes(x));

// Languages people can pick on the home page ('any' = match with everyone). Keep in sync with client/lib/languages.dart.
const LANGS = new Set(['any', 'en', 'fr', 'ar', 'es', 'pt', 'de', 'it', 'tr', 'ru', 'uk', 'pl', 'nl', 'ro', 'el',
  'sv', 'he', 'fa', 'ur', 'hi', 'bn', 'id', 'vi', 'th', 'zh', 'ja', 'ko']);
const cleanLang = (x) => {
  const v = String(x || '').toLowerCase().trim().slice(0, 5);
  return LANGS.has(v) ? v : 'any';
};
// Language is a hard filter: two people only meet if they picked the same language, or one of them picked 'any'.
const langOk = (a, b) => a.lang === 'any' || b.lang === 'any' || a.lang === b.lang;
// Interests are a soft filter (relaxed after RELAX_AFTER_MS); language is never relaxed.
const compatible = (a, b) =>
  langOk(a, b) && (
    a.relaxed || b.relaxed || !a.interests.length || !b.interests.length ||
    overlap(a.interests, b.interests).length > 0);

function pair(a, b) {
  partners.set(a.socket.id, b.socket.id);
  partners.set(b.socket.id, a.socket.id);
  chatLogs.set(pairKey(a.socket.id, b.socket.id), []);
  const common = overlap(a.interests, b.interests);
  const info = (x) => ({ name: x.name || 'Anonymous', country: x.socket.data.country.name, countryCode: x.socket.data.country.code, language: x.lang });
  bumpStat('matched');
  a.socket.emit('matched', { initiator: true, common, partner: info(b) });
  b.socket.emit('matched', { initiator: false, common, partner: info(a) });
}

function tryMatch(e) {
  waiting = waiting.filter((x) => x.socket.connected);
  const i = waiting.findIndex((x) =>
    x.socket.id !== e.socket.id && x.mode === e.mode && compatible(e, x));
  if (i < 0) return false;
  const other = waiting.splice(i, 1)[0];
  waiting = waiting.filter((x) => x !== e);
  clearTimeout(other.timer);
  clearTimeout(e.timer);
  pair(e, other);
  return true;
}

function leave(s) {
  const pid = partners.get(s.id);
  if (pid) {
    partners.delete(s.id);
    partners.delete(pid);
    chatLogs.delete(pairKey(s.id, pid));
    io.to(pid).emit('partner_left');
  }
  waiting = waiting.filter((x) => {
    if (x.socket.id === s.id) { clearTimeout(x.timer); return false; }
    return true;
  });
}

function banUid(uid) {
  bans[uid] = Date.now() + BAN_HOURS * 3600 * 1000;
  saveBans();
  for (const sock of io.sockets.sockets.values()) {
    if (sock.data.uid === uid) { sock.emit('banned'); sock.disconnect(true); }
  }
}

const REASONS = new Set(['nudity', 'minor', 'harassment', 'spam', 'other']);

// ------------------------------------------------------------------- Live (one host, many viewers, comments)
// Video goes host -> each viewer over WebRTC (this server only relays signalling + comments, never video).
// Safety: hosts and viewers must confirm 18+, links are blocked, comments are rate limited, viewers can report
// a live (same ban scoring as random chat), and the host can remove a viewer or end the live at any time.
const lives = new Map(); // id -> { id, hostSid, hostUid, title, name, country, countryCode, since, viewers:Set, kicked:Set, log:[] }
const MAX_LIVES = parseInt(env.MAX_LIVES || '30', 10);
const MAX_LIVE_VIEWERS = parseInt(env.MAX_LIVE_VIEWERS || '10', 10); // host sends video to each viewer directly (see README for scaling)
const MAX_GUESTS = parseInt(env.MAX_GUESTS || '3', 10); // viewers invited on stage (audio or camera)
const guestList = (l) => [...l.guests.entries()].map(([sid, g]) => ({ sid, name: g.name, video: g.video, muted: !!g.muted, streamId: g.streamId || '' }));
const sendGuests = (l) => io.to(`live:${l.id}`).emit('live_guests', guestList(l));
const sendViewers = (l) => io.to(l.hostSid).emit('live_viewers', [...l.viewers].map((sid) => {
  const v = io.sockets.sockets.get(sid);
  return { sid, name: (v && v.data.liveName) || 'Anonymous', guest: l.guests.has(sid), invited: l.invited.has(sid) };
}));
const livePublic = (l) => ({
  id: l.id, title: l.title, name: l.name, country: l.country, countryCode: l.countryCode,
  viewers: l.viewers.size, since: l.since,
});
app.get('/api/lives', limit(90), (_req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  const list = [...lives.values()].sort((a, b) => b.viewers.size - a.viewers.size || b.since - a.since).map(livePublic);
  res.json({ lives: list, maxViewers: MAX_LIVE_VIEWERS });
});
function endLive(l) {
  if (!lives.has(l.id)) return;
  lives.delete(l.id);
  io.to(`live:${l.id}`).emit('live_ended', { id: l.id });
  for (const sid of [...l.viewers, l.hostSid]) {
    const sock = io.sockets.sockets.get(sid);
    if (sock) { sock.leave(`live:${l.id}`); if (sock.data.liveView === l.id) sock.data.liveView = null; if (sock.data.liveHost === l.id) sock.data.liveHost = null; }
  }
}
function leaveLiveView(s) {
  const id = s.data.liveView;
  if (!id) return;
  s.data.liveView = null;
  s.leave(`live:${id}`);
  const l = lives.get(id);
  if (!l) return;
  l.viewers.delete(s.id);
  l.invited.delete(s.id);
  const wasGuest = l.guests.delete(s.id);
  io.to(`live:${id}`).emit('live_count', l.viewers.size);
  io.to(l.hostSid).emit('live_viewer_left', { vid: s.id });
  if (wasGuest) { io.to(l.hostSid).emit('live_guest_left', { sid: s.id }); sendGuests(l); }
  sendViewers(l);
}
function cleanTitle(raw) {
  const t = clipText(String(raw || '').replace(LINK_RE, ''), 40);
  return t.length >= 2 ? t : 'Live on Orbyt';
}

io.on('connection', (s) => {
  const uid = uidOf(ipFromReq(s.request));
  s.data.uid = uid;
  s.data.country = countryOf(ipFromReq(s.request)); // from the connection itself; cannot be typed in by the user
  s.data.reported = new Set();

  if (isBanned(uid)) { s.emit('banned'); s.disconnect(true); return; }
  const rate = (connRate.get(uid) || 0) + 1;
  connRate.set(uid, rate);
  if (rate > 40) { s.emit('notice', 'Too many connection attempts. Please wait a minute.'); s.disconnect(true); return; }
  const open = (connPerUid.get(uid) || 0) + 1;
  if (open > MAX_CONN_PER_IP) { s.emit('notice', 'Too many open connections from your network.'); s.disconnect(true); return; }
  connPerUid.set(uid, open);
  s.emit('online', io.engine.clientsCount);

  // per-socket limiters
  let chatStamps = [];
  let findStamps = [];
  const within = (arr, windowMs, max) => {
    const now = Date.now();
    while (arr.length && now - arr[0] > windowMs) arr.shift();
    if (arr.length >= max) return false;
    arr.push(now);
    return true;
  };

  s.on('find', (data) => {
    if (!s.data.statChat) { s.data.statChat = true; bumpStat('chats'); }
    if (!within(findStamps, 60000, 20)) { s.emit('notice', 'Slow down a little - too many skips.'); return; }
    leave(s);
    const e = {
      socket: s,
      interests: cleanInterests(data && data.interests),
      name: cleanName(data && data.username), // null => Anonymous
      mode: data && data.mode === 'video' ? 'video' : 'text', // video only meets video, text only meets text
      lang: cleanLang(data && data.language),                  // 'any' = no language preference
      relaxed: false,
      timer: null,
    };
    if (tryMatch(e)) return;
    waiting.push(e);
    s.emit('waiting');
    if (e.interests.length) {
      e.timer = setTimeout(() => { e.relaxed = true; tryMatch(e); }, RELAX_AFTER_MS);
    }
  });

  s.on('signal', (data) => {
    const pid = partners.get(s.id);
    if (!pid || !data || typeof data !== 'object') return;
    // Whitelist + size-limit what we relay
    if (data.type === 'offer' || data.type === 'answer') {
      if (typeof data.sdp !== 'string' || data.sdp.length > 20000) return;
      io.to(pid).emit('signal', { type: data.type, sdp: data.sdp });
    } else if (data.type === 'candidate') {
      if (typeof data.candidate !== 'string' || data.candidate.length > 2000) return;
      io.to(pid).emit('signal', {
        type: 'candidate',
        candidate: data.candidate,
        sdpMid: typeof data.sdpMid === 'string' ? data.sdpMid.slice(0, 32) : null,
        sdpMLineIndex: Number.isInteger(data.sdpMLineIndex) ? data.sdpMLineIndex : 0,
      });
    }
  });

  s.on('chat', (msg) => {
    const pid = partners.get(s.id);
    if (!pid || typeof msg !== 'string' || !msg.trim()) return;
    if (!within(chatStamps, 5000, 6)) { s.emit('notice', 'You are sending messages too fast.'); return; }
    const original = msg.slice(0, 500);
    const text = original.replace(LINK_RE, '[link removed]');
    if (text !== original) s.emit('notice', 'Links are blocked in chat for everyone\'s safety.');
    io.to(pid).emit('chat', text);
    const log = chatLogs.get(pairKey(s.id, pid));
    if (log) { log.push({ t: Date.now(), from: uid, text: original }); if (log.length > 20) log.shift(); }
  });

  s.on('typing', (v) => {
    const pid = partners.get(s.id);
    if (pid) io.to(pid).emit('typing', !!v);
  });

  s.on('report', (data) => {
    const pid = partners.get(s.id);
    const target = pid && io.sockets.sockets.get(pid);
    if (!target || s.data.reported.has(pid)) return; // one report per partner
    s.data.reported.add(pid);

    const reason = data && REASONS.has(data.reason) ? data.reason : 'other';
    const weight = reason === 'nudity' || reason === 'minor' ? 2 : 1;
    const tid = target.data.uid;
    if (tid === uid) return;

    const now = Date.now();
    const rec = reportsAgainst.get(tid) || new Map();
    for (const [k, v] of rec) if (now - v.ts > 86400000) rec.delete(k);
    const prev = rec.get(uid);
    rec.set(uid, { w: Math.max(weight, prev ? prev.w : 0), ts: now });
    reportsAgainst.set(tid, rec);
    const score = [...rec.values()].reduce((n, v) => n + v.w, 0);

    const entry = {
      ts: new Date(now).toISOString(), reason, reported: tid, reporter: uid, score,
      lastMessages: (chatLogs.get(pairKey(s.id, pid)) || []).map((m) => ({
        t: new Date(m.t).toISOString(), from: m.from === tid ? 'reported' : 'reporter', text: m.text,
      })),
    };
    fs.appendFile(REPORTS_FILE, JSON.stringify(entry) + '\n', (e) => e && console.error('[report] log failed', e.message));
    console.log(`[report] ${reason} -> ${tid} score=${score}`);
    if (score >= BAN_SCORE) banUid(tid);
  });


  // ---------------- Live
  let liveStamps = [];
  let liveChatStamps = [];
  s.on('live_start', (data) => {
    if (!data || data.adult !== true) { s.emit('live_error', 'adult_required'); return; }
    if (s.data.liveHost) return;
    if (!within(liveStamps, 3600000, 6)) { s.emit('live_error', 'rate'); return; }
    if (lives.size >= MAX_LIVES) { s.emit('live_error', 'busy'); return; }
    leave(s); leaveLiveView(s); // leave random chat / another live
    const id = crypto.randomBytes(6).toString('hex');
    const l = {
      id, hostSid: s.id, hostUid: uid, title: cleanTitle(data.title),
      name: cleanName(data.username) || 'Anonymous',
      country: s.data.country.name, countryCode: s.data.country.code,
      since: Date.now(), viewers: new Set(), kicked: new Set(), log: [], reported: new Set(), guests: new Map(), invited: new Map(),
    };
    lives.set(id, l);
    s.data.liveHost = id;
    s.data.liveName = l.name;
    s.join(`live:${id}`);
    bumpStat('lives');
    s.emit('live_started', { id, maxViewers: MAX_LIVE_VIEWERS });
  });

  s.on('live_join', (data) => {
    if (!data || data.adult !== true) { s.emit('live_error', 'adult_required'); return; }
    leaveLiveView(s);
    const l = lives.get(String(data.id || ''));
    if (!l || l.hostSid === s.id) { s.emit('live_error', 'not_found'); return; }
    if (l.kicked.has(uid)) { s.emit('live_error', 'kicked'); return; }
    if (l.viewers.size >= MAX_LIVE_VIEWERS) { s.emit('live_error', 'full'); return; }
    leave(s); // leave random chat
    l.viewers.add(s.id);
    s.data.liveView = l.id;
    s.data.liveName = cleanName(data.username) || 'Anonymous';
    s.join(`live:${l.id}`);
    s.emit('live_joined', { id: l.id, title: l.title, name: l.name, country: l.country, viewers: l.viewers.size });
    io.to(`live:${l.id}`).emit('live_count', l.viewers.size);
    io.to(l.hostSid).emit('live_viewer', { vid: s.id });
    s.emit('live_guests', guestList(l));
    sendViewers(l);
  });

  s.on('live_signal', (data) => {
    if (!data || typeof data !== 'object' || typeof data.to !== 'string') return;
    // ch 'up' = a guest on stage sending their camera/mic to the host; default = host -> viewer
    const ch = data.ch === 'up' ? 'up' : 'down';
    let ok = false;
    if (s.data.liveHost) {
      const l = lives.get(s.data.liveHost);
      ok = !!l && l.viewers.has(data.to) && (ch === 'down' || l.guests.has(data.to));
    } else if (s.data.liveView) {
      const l = lives.get(s.data.liveView);
      ok = !!l && l.hostSid === data.to && (ch === 'down' || l.guests.has(s.id));
    }
    if (!ok) return;
    if (data.type === 'offer' || data.type === 'answer') {
      if (typeof data.sdp !== 'string' || data.sdp.length > 20000) return;
      io.to(data.to).emit('live_signal', { from: s.id, ch, type: data.type, sdp: data.sdp });
    } else if (data.type === 'candidate') {
      if (typeof data.candidate !== 'string' || data.candidate.length > 2000) return;
      io.to(data.to).emit('live_signal', {
        from: s.id, ch, type: 'candidate', candidate: data.candidate,
        sdpMid: typeof data.sdpMid === 'string' ? data.sdpMid.slice(0, 32) : null,
        sdpMLineIndex: Number.isInteger(data.sdpMLineIndex) ? data.sdpMLineIndex : 0,
      });
    }
  });

  // ---- Guests: the host invites a viewer on stage (audio only or with camera).
  // The guest sends their media to the host; the host relays it to everybody else.
  s.on('live_invite', (data) => {
    const l = s.data.liveHost && lives.get(s.data.liveHost);
    const sid = data && typeof data.sid === 'string' ? data.sid : '';
    if (!l || !l.viewers.has(sid) || l.guests.has(sid)) return;
    if (l.guests.size + l.invited.size >= MAX_GUESTS) { s.emit('notice', `Max ${MAX_GUESTS} guests on stage.`); return; }
    const v = io.sockets.sockets.get(sid);
    if (!v) return;
    const video = !!(data && data.video);
    l.invited.set(sid, video);
    v.emit('live_invited', { video, host: l.name });
    sendViewers(l);
  });

  s.on('live_invite_cancel', (data) => {
    const l = s.data.liveHost && lives.get(s.data.liveHost);
    const sid = data && typeof data.sid === 'string' ? data.sid : '';
    if (!l || !l.invited.delete(sid)) return;
    io.to(sid).emit('live_invite_cancelled');
    sendViewers(l);
  });

  s.on('live_accept', () => {
    const l = s.data.liveView && lives.get(s.data.liveView);
    if (!l || !l.invited.has(s.id)) return;
    const video = l.invited.get(s.id);
    l.invited.delete(s.id);
    if (l.guests.size >= MAX_GUESTS) { s.emit('live_guest_removed', 'full'); sendViewers(l); return; }
    l.guests.set(s.id, { name: s.data.liveName || 'Anonymous', video, streamId: '' });
    s.emit('live_guest_ok', { video });
    io.to(l.hostSid).emit('live_guest_joined', { sid: s.id });
    sendGuests(l); sendViewers(l);
  });

  s.on('live_decline', () => {
    const l = s.data.liveView && lives.get(s.data.liveView);
    if (!l || !l.invited.delete(s.id)) return;
    io.to(l.hostSid).emit('notice', `${s.data.liveName || 'Someone'} declined.`);
    sendViewers(l);
  });

  // the guest leaves the stage by themselves, or the host removes them
  const dropGuest = (l, sid, why) => {
    if (!l.guests.delete(sid)) return;
    io.to(sid).emit('live_guest_removed', why);
    io.to(l.hostSid).emit('live_guest_left', { sid });
    sendGuests(l); sendViewers(l);
  };
  s.on('live_guest_leave', () => {
    const l = s.data.liveView && lives.get(s.data.liveView);
    if (l) dropGuest(l, s.id, 'left');
  });
  s.on('live_guest_remove', (data) => {
    const l = s.data.liveHost && lives.get(s.data.liveHost);
    if (l && data && typeof data.sid === 'string') dropGuest(l, data.sid, 'removed');
  });
  // host mutes / unmutes a guest's microphone (the guest cannot unmute while muted by the host)
  s.on('live_guest_mute', (data) => {
    const l = s.data.liveHost && lives.get(s.data.liveHost);
    const g = l && data && typeof data.sid === 'string' ? l.guests.get(data.sid) : null;
    if (!g) return;
    g.muted = !!data.muted;
    io.to(data.sid).emit('live_mute_by_host', { muted: g.muted });
    sendGuests(l);
  });
  // host tells everyone which incoming stream belongs to which guest
  s.on('live_guest_stream', (data) => {
    const l = s.data.liveHost && lives.get(s.data.liveHost);
    const g = l && data && typeof data.sid === 'string' ? l.guests.get(data.sid) : null;
    if (!g || typeof data.streamId !== 'string' || data.streamId.length > 100) return;
    g.streamId = data.streamId;
    sendGuests(l);
  });

  s.on('live_chat', (msg) => {
    const id = s.data.liveHost || s.data.liveView;
    const l = id && lives.get(id);
    if (!l || typeof msg !== 'string' || !msg.trim()) return;
    if (!within(liveChatStamps, 5000, 5)) { s.emit('notice', 'You are commenting too fast.'); return; }
    const original = msg.slice(0, 200);
    const text = original.replace(LINK_RE, '[link removed]');
    if (text !== original) s.emit('notice', 'Links are blocked in comments for everyone\'s safety.');
    io.to(`live:${l.id}`).emit('live_chat', { sid: s.id, name: s.data.liveName || 'Anonymous', host: l.hostSid === s.id, text });
    l.log.push({ t: Date.now(), from: uid, host: l.hostSid === s.id, text: original });
    if (l.log.length > 30) l.log.shift();
  });

  s.on('live_kick', (data) => {
    const l = s.data.liveHost && lives.get(s.data.liveHost);
    const sid = data && typeof data.sid === 'string' ? data.sid : '';
    if (!l || !l.viewers.has(sid)) return;
    const v = io.sockets.sockets.get(sid);
    if (v) { l.kicked.add(v.data.uid); v.emit('live_kicked'); leaveLiveView(v); }
  });

  s.on('live_report', (data) => {
    const l = s.data.liveView && lives.get(s.data.liveView);
    if (!l || l.reported.has(uid) || l.hostUid === uid) return;
    l.reported.add(uid);
    const reason = data && REASONS.has(data.reason) ? data.reason : 'other';
    const weight = reason === 'nudity' || reason === 'minor' ? 2 : 1;
    const now = Date.now();
    const rec = reportsAgainst.get(l.hostUid) || new Map();
    for (const [k, v] of rec) if (now - v.ts > 86400000) rec.delete(k);
    const prev = rec.get(uid);
    rec.set(uid, { w: Math.max(weight, prev ? prev.w : 0), ts: now });
    reportsAgainst.set(l.hostUid, rec);
    const score = [...rec.values()].reduce((n, v) => n + v.w, 0);
    const entry = {
      ts: new Date(now).toISOString(), kind: 'live', reason, reported: l.hostUid, reporter: uid, score, title: l.title,
      lastMessages: l.log.map((m) => ({ t: new Date(m.t).toISOString(), from: m.host ? 'host' : 'viewer', text: m.text })),
    };
    fs.appendFile(REPORTS_FILE, JSON.stringify(entry) + '\n', (e) => e && console.error('[report] log failed', e.message));
    console.log(`[report] live ${reason} -> ${l.hostUid} score=${score}`);
    if (score >= BAN_SCORE) { endLive(l); banUid(l.hostUid); }
  });

  s.on('live_leave', () => leaveLiveView(s));
  s.on('live_end', () => { const l = s.data.liveHost && lives.get(s.data.liveHost); if (l) endLive(l); });

  s.on('leave', () => leave(s));
  s.on('disconnect', () => {
    leave(s);
    leaveLiveView(s);
    { const hl = s.data.liveHost && lives.get(s.data.liveHost); if (hl) endLive(hl); }
    const left = (connPerUid.get(uid) || 1) - 1;
    if (left <= 0) connPerUid.delete(uid); else connPerUid.set(uid, left);
  });
});

// Throttled "online" broadcast (instead of one per connect/disconnect)
let lastOnline = -1;
setInterval(() => {
  const n = io.engine.clientsCount;
  if (n !== lastOnline) { lastOnline = n; io.emit('online', n); }
}, 2000).unref();

// Keep-alive: Render's free plan puts the site to sleep after ~15 min without visitors.
// Calling our own public address every 10 minutes counts as traffic, so it stays awake.
// (Render sets RENDER_EXTERNAL_URL by itself. Turn off with KEEP_ALIVE=0.)
if (env.RENDER_EXTERNAL_URL && env.KEEP_ALIVE !== '0' && typeof fetch === 'function') {
  setInterval(() => {
    fetch(`${env.RENDER_EXTERNAL_URL}/health`).catch(() => {});
  }, 10 * 60 * 1000).unref();
}

server.listen(PORT, () => console.log(`Orbyt server running on http://localhost:${PORT} (${PROD ? 'production' : 'dev'})`));

function shutdown() {
  console.log('Shutting down...');
  io.close(() => server.close(() => process.exit(0)));
  setTimeout(() => process.exit(0), 5000).unref();
}
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

module.exports = { server, io };
