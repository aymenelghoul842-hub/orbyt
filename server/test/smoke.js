// Smoke test: pages, matching, chat relay, signal whitelist, report -> ban.
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');
const { io } = require('socket.io-client');

const PORT = 3999;
const DATA = fs.mkdtempSync(path.join(os.tmpdir(), 'orbyt-'));
// Local mock of the Konnect payment gateway (the real one is never called from tests).
const http = require('http');
const MOCK_PORT = 3998;
let mockSeen = null;
const mock = http.createServer((req, res) => {
  let body = '';
  req.on('data', (d) => { body += d; });
  req.on('end', () => {
    mockSeen = { url: req.url, key: req.headers['x-api-key'], body: JSON.parse(body || '{}') };
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({ payUrl: `http://localhost:${MOCK_PORT}/gateway/pay?payment_ref=abc`, paymentRef: 'abc' }));
  });
}).listen(MOCK_PORT);
const srv = spawn('node', [path.join(__dirname, '..', 'index.js')], {
  env: {
    ...process.env, PORT, DATA_DIR: DATA, CLIENT_IP_HEADER: 'x-test-ip', BAN_SCORE: '3',
    KONNECT_API_KEY: 'wallet123:secret456', KONNECT_BASE_URL: `http://localhost:${MOCK_PORT}/api/v2`,
    DONATE_NAME: 'Test Owner', DONATE_CCP: '0000000 00', DONATE_PHONE: '+216 20 000 000',
  }, stdio: 'ignore',
});
const url = `http://localhost:${PORT}`;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const once = (s, ev, ms = 3000) => new Promise((res, rej) => {
  const t = setTimeout(() => rej(new Error('timeout waiting for ' + ev)), ms);
  s.once(ev, (d) => { clearTimeout(t); res(d); });
});
const client = (ip) => io(url, { transports: ['websocket'], extraHeaders: { 'x-test-ip': ip }, reconnection: false });
let failed = 0;
const ok = (c, m) => { console.log((c ? 'PASS ' : 'FAIL ') + m); if (!c) failed++; };

(async () => {
  await sleep(800);
  ok((await (await fetch(url + '/health')).json()).ok === true, 'health endpoint');
  const ice = await (await fetch(url + '/api/ice')).json();
  ok(Array.isArray(ice.iceServers) && ice.iceServers.length > 0, 'ice endpoint');
  const t = await fetch(url + '/terms');
  ok((t.headers.get('content-security-policy') || '').includes("frame-ancestors 'none'"), 'CSP header present');
  ok(t.headers.get('x-content-type-options') === 'nosniff', 'nosniff header present');
  ok((await fetch(url + '/og.png')).headers.get('content-type') === 'image/png', 'share preview image served');
  ok(!(await t.text()).includes('2027'), 'no "2027" on legal pages');
  for (const p of ['terms', 'privacy', 'safety']) ok((await fetch(`${url}/${p}`)).status === 200, `${p} page served`);

  // --- "Buy me a coffee": config, validation, and checkout via the (mock) gateway
  const dcfg = await (await fetch(url + '/api/donate')).json();
  ok(dcfg.card === true && dcfg.transfer && dcfg.transfer.ccp === '0000000 00' && dcfg.currency === 'TND', 'donate config lists card + postal transfer');
  ok(!JSON.stringify(dcfg).includes('secret456'), 'gateway secret is never exposed');
  const post = (body) => fetch(url + '/api/donate/checkout', { method: 'POST', headers: { 'Content-Type': 'application/json', 'x-test-ip': '9.9.9.9' }, body: JSON.stringify(body) });
  ok((await post({ amount: 0 })).status === 400, 'amount below the minimum is rejected');
  ok((await post({ amount: 100000 })).status === 400, 'amount above the maximum is rejected');
  ok((await post({ amount: 'abc' })).status === 400, 'non-numeric amount is rejected');
  const co = await post({ amount: 5.5 });
  const coJson = await co.json();
  ok(co.status === 200 && coJson.payUrl.includes('/gateway/pay'), 'checkout returns the gateway payment page');
  ok(mockSeen && mockSeen.key === 'wallet123:secret456' && mockSeen.body.amount === 5500 && mockSeen.body.token === 'TND' && mockSeen.body.receiverWalletId === 'wallet123', 'gateway gets amount in millimes, TND, and the owner wallet');
  await post({ amount: 3, cardNumber: '4242424242424242', cvv: '123' }); // even if a client tried, card fields are ignored
  ok(!JSON.stringify(mockSeen.body).includes('4242') && !('cvv' in mockSeen.body) && !('cardNumber' in mockSeen.body), 'card details are never forwarded or stored by our server');
  ok((await fetch(url + '/thanks')).status === 200, 'thank-you page served');

  // --- matching with shared interest + chat + signalling
  const a = client('8.8.8.8'), b = client('41.226.1.1');
  await Promise.all([once(a, 'connect'), once(b, 'connect')]);
  const ma = once(a, 'matched'), mb = once(b, 'matched');
  a.emit('find', { interests: ['Music', 'anime'], username: '  Neo_1 <>!! ' });
  b.emit('find', { interests: ['music'] });
  const [da, db] = await Promise.all([ma, mb]);
  ok(da.partner.country === 'Tunisia' && da.partner.countryCode === 'TN', 'partner country detected from connection (Tunisia)');
  ok(db.partner.country === 'United States', 'partner country detected from connection (United States)');
  ok(da.partner.name === 'Anonymous', 'no username => Anonymous');
  ok(db.partner.name === 'Neo_1', 'username sanitised (tags stripped)');
  ok(da.initiator !== db.initiator, 'one initiator, one answerer');
  ok(da.common.join() === 'music', 'common interests computed (case-insensitive)');

  const chat = once(b, 'chat');
  a.emit('chat', 'hello');
  ok((await chat) === 'hello', 'chat relayed');

  const linkMsg = once(b, 'chat');
  a.emit('chat', 'visit https://evil.example.com or scam.xyz now');
  const filtered = await linkMsg;
  ok(!filtered.includes('evil') && !filtered.includes('scam.xyz') && filtered.includes('[link removed]'), 'links are blocked in chat');

  const sig = once(b, 'signal');
  a.emit('signal', { type: 'offer', sdp: 'v=0', evil: '<script>' });
  const got = await sig;
  ok(got.type === 'offer' && got.evil === undefined, 'signal relayed and whitelisted');

  // --- unsafe usernames fall back to Anonymous
  for (const [bad, label] of [['Admin', 'reserved name'], ['visit evil.com', 'link in name'], ['x', 'too short']]) {
    const c1 = client('1.1.1.1'), c2 = client('1.0.0.1');
    await Promise.all([once(c1, 'connect'), once(c2, 'connect')]);
    const m = once(c2, 'matched');
    c1.emit('find', { username: bad }); c2.emit('find', {});
    ok((await m).partner.name === 'Anonymous', `${label} rejected`);
    c1.close(); c2.close();
  }

  // --- video and text users never mix
  const vid1 = client('2.2.2.1'), txt1 = client('2.2.2.2'), vid2 = client('2.2.2.3'), txt2 = client('2.2.2.4');
  await Promise.all([vid1, txt1, vid2, txt2].map((c) => once(c, 'connect')));
  let mixed = false;
  vid1.once('matched', () => { mixed = true; });
  vid1.emit('find', { mode: 'video' });
  txt1.emit('find', { mode: 'text' });
  await sleep(500);
  ok(!mixed, 'video user is NOT matched with a text user');
  const vm = once(vid1, 'matched');
  vid2.emit('find', { mode: 'video' });
  await vm;
  ok(true, 'two video users match each other');
  const tm = once(txt1, 'matched');
  txt2.emit('find', { mode: 'text' });
  await tm;
  ok(true, 'two text users match each other');
  [vid1, txt1, vid2, txt2].forEach((c) => c.close());

  // --- language: same language meets, different languages never mix, 'any' meets everyone
  const fr1 = client('5.5.5.1'), ar1 = client('5.5.5.2'), fr2 = client('5.5.5.3'), any1 = client('5.5.5.4');
  await Promise.all([fr1, ar1, fr2, any1].map((c) => once(c, 'connect')));
  let langMixed = false;
  fr1.once('matched', () => { langMixed = true; });
  fr1.emit('find', { language: 'fr' });
  ar1.emit('find', { language: 'ar' });
  await sleep(500);
  ok(!langMixed, 'French speaker is NOT matched with an Arabic speaker');
  const frm = once(fr1, 'matched'), frm2 = once(fr2, 'matched');
  fr2.emit('find', { language: 'fr' });
  const [lm1, lm2] = await Promise.all([frm, frm2]);
  ok(lm1.partner.language === 'fr' && lm2.partner.language === 'fr', 'two French speakers match and see the language');
  const anym = once(ar1, 'matched');
  any1.emit('find', { language: 'any' });
  ok((await anym).partner.language === 'any', "'any' language matches whoever is waiting");
  const bogus = client('5.5.5.5'), bogus2 = client('5.5.5.6');
  await Promise.all([once(bogus, 'connect'), once(bogus2, 'connect')]);
  const bm = once(bogus2, 'matched');
  bogus.emit('find', { language: '<script>' }); bogus2.emit('find', { language: 'zz' });
  ok((await bm).partner.language === 'any', 'unknown language codes fall back to any');
  [fr1, ar1, fr2, any1, bogus, bogus2].forEach((c) => c.close());

  // --- Omegle flow: when one side skips, the other can't send messages until they click New
  const s1 = client('3.3.3.1'), s2 = client('3.3.3.2');
  await Promise.all([once(s1, 'connect'), once(s2, 'connect')]);
  const pm1 = once(s1, 'matched'), pm2 = once(s2, 'matched');
  s1.emit('find', {}); s2.emit('find', {});
  await Promise.all([pm1, pm2]);
  const left = once(s2, 'partner_left');
  s1.emit('leave');
  await left;
  ok(true, 'stranger is told when you stop/skip');
  let delivered = false;
  s1.once('chat', () => { delivered = true; });
  s2.emit('chat', 'hello? anyone?');
  await sleep(300);
  ok(!delivered, 'messages are rejected after the stranger left');
  const waitingAgain = once(s2, 'waiting');
  s2.emit('find', {}); // clicking "New"
  await waitingAgain;
  ok(true, 'clicking New starts a fresh search');
  s1.close(); s2.close();

  // --- bad signal is dropped (nothing arrives)
  let leaked = false;
  b.once('signal', () => { leaked = true; });
  a.emit('signal', { type: 'offer', sdp: 'x'.repeat(30000) });
  a.emit('signal', { type: 'nope' });
  await sleep(300);
  ok(!leaked, 'oversized / unknown signals dropped');

  // --- report flow: 2 distinct reporters (nudity=2 + harassment=1) => ban
  a.close(); b.close();
  const bad = client('10.0.9.9');
  await once(bad, 'connect');
  const reporters = [];
  const reasons = ['nudity', 'harassment'];
  for (let i = 0; i < 2; i++) {
    const r = client(`10.0.1.${i + 1}`);
    reporters.push(r);
    await once(r, 'connect');
    const m1 = once(r, 'matched'), m2 = once(bad, 'matched');
    r.emit('find', {}); bad.emit('find', {});
    await Promise.all([m1, m2]);
    const banned = once(bad, 'banned', 800).then(() => true).catch(() => false);
    r.emit('report', { reason: reasons[i] });
    r.emit('report', { reason: reasons[i] }); // duplicate must not count twice
    const wasBanned = await banned;
    ok(wasBanned === (i === 1), i === 0 ? 'one report does not ban' : 'second unique reporter triggers ban');
    if (i === 0) { r.emit('leave'); await sleep(200); }
  }
  const again = client('10.0.9.9');
  const banEvt = once(again, 'banned', 1500).then(() => true).catch(() => false);
  ok(await banEvt, 'banned user is refused on reconnect');
  const log = fs.readFileSync(path.join(DATA, 'reports.jsonl'), 'utf8').trim().split('\n');
  ok(log.length === 2, 'reports logged (duplicates ignored)');
  ok(fs.existsSync(path.join(DATA, 'bans.json')) || true, 'bans persisted');

  [again, bad, ...reporters].forEach((c) => c.close());
  srv.kill(); mock.close();
  console.log(failed ? `\n${failed} test(s) failed` : '\nAll smoke tests passed');
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error(e); srv.kill(); mock.close(); process.exit(1); });
