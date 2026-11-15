// Live test: start, list, join, signalling, comments, kick, report -> ban, end.
const { spawn } = require('child_process');
const path = require('path'); const fs = require('fs'); const os = require('os');
const { io } = require('socket.io-client');
const PORT = 3997, DATA = fs.mkdtempSync(path.join(os.tmpdir(), 'orbyt-live-'));
const srv = spawn('node', [path.join(__dirname, '..', 'index.js')], {
  env: { ...process.env, PORT, DATA_DIR: DATA, CLIENT_IP_HEADER: 'x-test-ip', BAN_SCORE: '3', MAX_LIVE_VIEWERS: '2' }, stdio: 'ignore' });
const url = `http://localhost:${PORT}`;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const once = (s, ev, ms = 2500) => new Promise((res, rej) => { const t = setTimeout(() => rej(new Error('timeout ' + ev)), ms); s.once(ev, (d) => { clearTimeout(t); res(d); }); });
const client = (ip) => io(url, { transports: ['websocket'], extraHeaders: { 'x-test-ip': ip }, reconnection: false });
const lives = async () => (await (await fetch(url + '/api/lives')).json()).lives;
let failed = 0; const ok = (c, m) => { console.log((c ? 'PASS ' : 'FAIL ') + m); if (!c) failed++; };
(async () => {
  await sleep(1200);
  const host = client('9.0.0.1'); await once(host, 'connect');
  const e1 = once(host, 'live_error'); host.emit('live_start', { title: 'x' });
  ok((await e1) === 'adult_required', 'going live requires 18+ confirmation');
  const st = once(host, 'live_started');
  host.emit('live_start', { adult: true, title: 'Hello visit evil.com now', username: 'Sami' });
  const { id } = await st;
  let L = await lives();
  ok(L.length === 1 && L[0].id === id && L[0].name === 'Sami' && !/evil\.com/.test(L[0].title), 'live is listed, links stripped from title');

  const v1 = client('9.0.0.2'); await once(v1, 'connect');
  const noAdult = once(v1, 'live_error'); v1.emit('live_join', { id });
  ok((await noAdult) === 'adult_required', 'viewer must confirm 18+');
  const vv = once(host, 'live_viewer'), joined = once(v1, 'live_joined');
  v1.emit('live_join', { id, adult: true, username: 'Ali' });
  const { vid } = await vv; await joined;
  ok(vid === v1.id, 'host is told a viewer joined');

  const gotOffer = once(v1, 'live_signal');
  host.emit('live_signal', { to: vid, type: 'offer', sdp: 'v=0' });
  const o = await gotOffer; ok(o.type === 'offer' && o.from === host.id, 'offer relayed host -> viewer');
  const gotAns = once(host, 'live_signal');
  v1.emit('live_signal', { to: host.id, type: 'answer', sdp: 'v=0' });
  ok((await gotAns).from === v1.id, 'answer relayed viewer -> host');
  const stranger = client('9.0.0.9'); await once(stranger, 'connect');
  let leaked = false; v1.once('live_signal', () => { leaked = true; });
  stranger.emit('live_signal', { to: v1.id, type: 'offer', sdp: 'x' }); await sleep(300);
  ok(!leaked, 'outsiders cannot send signals to viewers');

  const c1 = once(host, 'live_chat'), c2 = once(v1, 'live_chat');
  v1.emit('live_chat', 'hi from tunis www.spam.com');
  const m = await c1; await c2;
  ok(m.name === 'Ali' && m.host === false && m.text.includes('[link removed]'), 'comments reach host + viewers, links removed');

  const v2 = client('9.0.0.3'); await once(v2, 'connect'); v2.emit('live_join', { id, adult: true }); await once(v2, 'live_joined');
  const v3 = client('9.0.0.4'); await once(v3, 'connect');
  const full = once(v3, 'live_error'); v3.emit('live_join', { id, adult: true });
  ok((await full) === 'full', 'viewer cap enforced');
  const kicked = once(v2, 'live_kicked'); host.emit('live_kick', { sid: v2.id }); await kicked;
  const again = once(v2, 'live_error'); v2.emit('live_join', { id, adult: true });
  ok((await again) === 'kicked', 'kicked viewer cannot rejoin');
  v3.emit('live_join', { id, adult: true }); await once(v3, 'live_joined'); ok(true, 'slot frees after kick');

  // reports: nudity(2) + harassment(1) from two viewers => host banned, live ended
  const ended = once(v1, 'live_ended'); const banned = once(host, 'banned');
  v1.emit('live_report', { reason: 'nudity' }); v3.emit('live_report', { reason: 'harassment' });
  await ended; await banned; ok(true, 'enough reports end the live and ban the host');
  ok((await lives()).length === 0, 'list is empty after the live ended');

  const h2 = client('9.1.0.1'); await once(h2, 'connect'); const st2 = once(h2, 'live_started');
  h2.emit('live_start', { adult: true, title: 'Second' }); const { id: id2 } = await st2;
  const v4 = client('9.1.0.2'); await once(v4, 'connect'); v4.emit('live_join', { id: id2, adult: true }); await once(v4, 'live_joined');
  const e2 = once(v4, 'live_ended'); h2.emit('live_end'); await e2; ok((await lives()).length === 0, 'host can end the live');
  const h3 = client('9.1.0.3'); await once(h3, 'connect'); const st3 = once(h3, 'live_started'); h3.emit('live_start', { adult: true }); await st3;
  h3.close(); await sleep(400); ok((await lives()).length === 0, 'live disappears when host disconnects');
  srv.kill(); process.exit(failed ? 1 : 0);
})().catch((e) => { console.error('ERROR', e.message); srv.kill(); process.exit(1); });
