// Guests test: host invites a viewer on stage, signalling channel 'up', limits, cleanup.
const { spawn } = require('child_process');
const path = require('path'); const fs = require('fs'); const os = require('os');
const { io } = require('socket.io-client');
const PORT = 3996, DATA = fs.mkdtempSync(path.join(os.tmpdir(), 'orbyt-guests-'));
const srv = spawn('node', [path.join(__dirname, '..', 'index.js')], {
  env: { ...process.env, PORT, DATA_DIR: DATA, CLIENT_IP_HEADER: 'x-test-ip', MAX_GUESTS: '1' }, stdio: 'ignore' });
const url = `http://localhost:${PORT}`;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const once = (s, ev, ms = 2500) => new Promise((res, rej) => { const t = setTimeout(() => rej(new Error('timeout ' + ev)), ms); s.once(ev, (d) => { clearTimeout(t); res(d); }); });
const client = (ip) => io(url, { transports: ['websocket'], extraHeaders: { 'x-test-ip': ip }, reconnection: false });
let failed = 0; const ok = (c, m) => { console.log((c ? 'PASS ' : 'FAIL ') + m); if (!c) failed++; };
(async () => {
  await sleep(1200);
  const host = client('8.0.0.1'); await once(host, 'connect');
  const st = once(host, 'live_started'); host.emit('live_start', { adult: true, title: 'G', username: 'Host' });
  const { id } = await st;
  const a = client('8.0.0.2'); await once(a, 'connect');
  const b = client('8.0.0.3'); await once(b, 'connect');
  const list = once(host, 'live_viewers');
  a.emit('live_join', { id, adult: true, username: 'Ali' }); await once(a, 'live_joined');
  const vs = await list; ok(vs.length === 1 && vs[0].name === 'Ali', 'host sees the viewers list');
  b.emit('live_join', { id, adult: true, username: 'Bob' }); await once(b, 'live_joined');

  // a viewer cannot invite / accept uninvited
  let bad = false; host.once('live_guest_joined', () => { bad = true; });
  a.emit('live_accept'); await sleep(250); ok(!bad, 'cannot accept without an invite');
  // up-channel is refused for non guests
  let leaked = false; host.once('live_signal', () => { leaked = true; });
  a.emit('live_signal', { to: host.id, ch: 'up', type: 'offer', sdp: 'v=0' }); await sleep(250);
  ok(!leaked, 'non-guest cannot send on the up channel');

  const inv = once(a, 'live_invited'); host.emit('live_invite', { sid: a.id, video: true });
  const iv = await inv; ok(iv.video === true, 'viewer receives the invite (camera)');
  const okEv = once(a, 'live_guest_ok'), jn = once(host, 'live_guest_joined'), gl = once(b, 'live_guests');
  a.emit('live_accept');
  ok((await okEv).video === true, 'guest accepted'); await jn;
  const g = await gl; ok(g.length === 1 && g[0].name === 'Ali' && g[0].video, 'everyone gets the guest list');

  const up = once(host, 'live_signal');
  a.emit('live_signal', { to: host.id, ch: 'up', type: 'offer', sdp: 'v=0' });
  const m = await up; ok(m.ch === 'up' && m.from === a.id, 'guest media offer reaches host on channel up');
  const back = once(a, 'live_signal');
  host.emit('live_signal', { to: a.id, ch: 'up', type: 'answer', sdp: 'v=0' });
  ok((await back).ch === 'up', 'host answers the guest on channel up');

  const upd = once(b, 'live_guests');
  host.emit('live_guest_stream', { sid: a.id, streamId: 'abc' });
  ok((await upd)[0].streamId === 'abc', 'stream id is shared so viewers can match the tile');

  // mute by host
  const mu = once(a, 'live_mute_by_host'), gm = once(b, 'live_guests');
  host.emit('live_guest_mute', { sid: a.id, muted: true });
  ok((await mu).muted === true, 'host can mute a guest');
  ok((await gm)[0].muted === true, 'everyone sees the guest is muted');

  // limit
  const notice = once(host, 'notice'); host.emit('live_invite', { sid: b.id, video: false });
  ok(/Max 1/.test(await notice), 'guest limit enforced');

  // remove guest
  const rm = once(a, 'live_guest_removed'), left = once(host, 'live_guest_left');
  host.emit('live_guest_remove', { sid: a.id });
  ok((await rm) === 'removed', 'host can remove a guest'); await left;

  // audio guest leaves on their own; disconnect cleanup
  host.emit('live_invite', { sid: b.id, video: false }); await once(b, 'live_invited');
  b.emit('live_accept'); await once(b, 'live_guest_ok');
  const gone = once(host, 'live_guest_left'); b.close(); await gone; ok(true, 'guest disconnect frees the slot and tells the host');

  srv.kill(); process.exit(failed ? 1 : 0);
})().catch((e) => { console.error('ERROR', e.message); srv.kill(); process.exit(1); });
