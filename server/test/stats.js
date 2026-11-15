// Visitor counter test: page visits counted without chatting, uniques per IP, bots ignored, private dashboard.
const { spawn } = require('child_process');
const path = require('path'); const fs = require('fs'); const os = require('os');
const PORT = 3996, DATA = fs.mkdtempSync(path.join(os.tmpdir(), 'orbyt-stats-'));
const srv = spawn('node', [path.join(__dirname, '..', 'index.js')], {
  env: { ...process.env, PORT, DATA_DIR: DATA, CLIENT_IP_HEADER: 'x-test-ip', STATS_KEY: 'secret-key-123' }, stdio: 'ignore' });
const url = `http://localhost:${PORT}`;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let failed = 0; const ok = (c, m) => { console.log((c ? 'PASS ' : 'FAIL ') + m); if (!c) failed++; };
const visit = (ip, ua = 'Mozilla/5.0 (Linux; Android 13) Chrome/120 Mobile') => fetch(url + '/', { headers: { 'x-test-ip': ip, 'user-agent': ua } });
(async () => {
  await sleep(1200);
  await visit('5.1.1.1'); await visit('5.1.1.1'); await visit('5.1.1.2');
  await visit('5.1.1.3', 'Googlebot/2.1'); await visit('5.1.1.4', 'WhatsApp/2.23');
  const v = await (await fetch(url + '/api/visits')).json();
  ok(v.today.views === 3, 'page views counted (3, bots ignored): ' + v.today.views);
  ok(v.today.visitors === 2, 'unique visitors counted once per person: ' + v.today.visitors);
  ok(typeof v.online === 'number', 'online number present');
  ok((await fetch(url + '/stats')).status === 401, 'dashboard needs the key');
  ok((await fetch(url + '/stats?key=wrong')).status === 401, 'wrong key refused');
  const page = await fetch(url + '/stats?key=secret-key-123'); const html = await page.text();
  ok(page.status === 200 && html.includes('Orbyt stats') && html.includes('visitors'), 'dashboard opens with the key');
  const j = await (await fetch(url + '/api/stats?key=secret-key-123')).json();
  ok(j.now.today.visitors === 2, 'private JSON stats work');
  await sleep(5600);
  ok(fs.existsSync(path.join(DATA, 'stats.json')), 'stats saved to disk');
  srv.kill(); process.exit(failed ? 1 : 0);
})().catch((e) => { console.error('ERROR', e.message); srv.kill(); process.exit(1); });
