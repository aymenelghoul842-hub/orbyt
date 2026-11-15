# Orbyt - Meet someone new. Instantly.

Anonymous random video + text chat (18+). Flutter Web client + Node.js (Socket.IO) server.

## What's new
- **Language picker:** choose the language you speak on the home page (defaults to your browser language, or "Any language"). You only meet people who picked the same language; if nobody is around after 20 s you get a one-tap "Match with anyone" button. The stranger's language is shown in the chat.
- **Buy me a coffee:** optional gift button on the home page (amount -> payment method). Card / e-DINAR payments happen on the payment provider's own page; postal / bank transfer details are shown with copy buttons.
- **Live (cards + clear voice):** anyone 18+ can tap *Go live* (camera + mic) and anyone 18+ can open the live list (strip at the top of the home page + the *Live* page), watch and write comments. Hosts can remove a viewer (tap their comment) or end the live; viewers can report a live (same ban scoring as random chat). Links are blocked in titles and comments.
- **Trailer:** an auto-playing, looping mini-video on the home page (people connecting, chatting in different languages, Stop -> Really? -> New). Tap it to pause.
- **New look:** ink-black base, solar-lime/mint accents, Space Grotesk headlines, dot-grid aurora, glass bento cards, branded splash screen
- **Interest chips**, live "N online now" counter on the home page
- **Safer by design:** categorised reports (nudity / under 18 / harassment / spam), unique-reporter ban scoring (can't be gamed by one person), persistent temporary bans, hashed IPs (no raw IPs stored), report evidence log, per-IP connection caps, chat + skip rate limits, validated WebRTC signalling, strict Origin check
- **Real TURN support** with short-lived credentials (coturn) so video works behind strict NATs
- **Terms, Privacy and Safety pages** (templates - edit placeholders!) at `/terms`, `/privacy`, `/safety`
- **One-command HTTPS deployment** (Docker Compose: app + Caddy + coturn)
- Fixed: crash when camera permission was denied; stale typing indicator; reconnect handling

## Security features
- Content-Security-Policy, nosniff, frame blocking, HSTS (behind HTTPS), strict Origin check on the live connection
- Links and bare domains are blocked in chat (anti-scam / anti-spam)
- Rate limits on messages, skips, new connections and HTTP calls; per-network connection cap
- Validated + size-limited WebRTC signalling; raw IPs never stored (salted hash only)
- Unique-reporter ban scoring, persistent temporary bans, report evidence log
- Country of the person you meet is detected offline from their connection (MaxMind GeoLite2) and shown with their username (or "Anonymous")
- Omegle-style chat: Stranger video on top / you below, chat on the right, Stop -> "Really?" -> New (Esc works too), emoji picker, "You:" / "Stranger:" log, typing indicator; when someone leaves, chat is locked until the other clicks New
- Share previews (WhatsApp / Facebook / X) with a proper image and description
- **Screen capture:** no website can block screenshots or recording (it happens in the OS). Orbyt only hides the other
  person's video when the tab is not in front, blocks right-click, and warns users that anyone can capture.

## Language matching
- Home page -> "Language you speak" -> pick one of 26 languages (list in `client/lib/languages.dart`, same codes as `LANGS` in `server/index.js`).
- Language is a hard filter on the server: same language, or at least one side on "Any". Interests still relax after 8 s, language never does.
- To add a language: add it to both lists (client + server) and redeploy.

## Buy me a coffee (gifts)
Flow: visitor writes an amount -> picks a method -> pays. Nothing is shown until you configure it (see `.env.example`).
- **Card / e-DINAR / wallet (Konnect):** set `KONNECT_API_KEY` (`walletId:secret` from the Konnect dashboard). It starts in TEST mode; set `KONNECT_SANDBOX=false` for real money. The visitor types the card on Konnect's own page. **Card numbers never touch this app or server** (do not add a card form: it would make you responsible for card data, and it looks like phishing). Check with Konnect that your account type can withdraw to your La Poste account.
- **Transfer (La Poste Tunisienne / bank / mobile wallet):** set any of `DONATE_NAME`, `DONATE_CCP`, `DONATE_RIB`, `DONATE_PHONE`. They are shown publicly with copy buttons.
- The button is only on the home page, never inside chats (the Safety page tells people that nobody legitimate asks for money in a chat).
- Server tests mock the gateway; run `cd server && npm test`.

## Trailer
The trailer is drawn in code (`client/lib/trailer.dart`), so it needs no video file and loads instantly. It uses illustrated people, not real footage. To show a real recorded video instead (only with the written consent of everyone who appears in it), put the mp4 in the project and replace `TrailerPreview` on the home page with a muted, looping video player.

## Run locally
    # terminal 1
    cd server && npm install && npm start          # http://localhost:3000
    # terminal 2
    cd client && flutter pub get && flutter run -d chrome
Or double-click `start.bat` (Windows) / run `./start.sh`. Open two tabs to test matching.
Server tests: `cd server && npm test`

## Free hosting: see FREE_HOSTING.md (GitHub Actions + Render, or Cloudflare Tunnel)

## Go public on a VPS (Docker Compose)
1. Get a VPS (Ubuntu) with Docker, and point a domain's DNS A record at it.
2. `cp .env.example .env` and fill in `DOMAIN`, `PUBLIC_IP`, `IP_SALT`, `TURN_SECRET` (use `openssl rand -hex 32`).
3. Open firewall ports: **80, 443** (TCP/UDP), **3478** (TCP/UDP), **49160-49200** (UDP).
4. `docker compose up -d --build` - Caddy gets a free HTTPS certificate automatically (camera/mic **require** HTTPS).
5. Open `https://your-domain`. Done.

Moderation data lives in the `orbyt-data` volume: `reports.jsonl` (reports + last messages) and `bans.json`.
To lift a ban, edit `bans.json` inside the volume and restart the app container.

### Without Docker
    cd client && flutter build web --release --dart-define=SERVER_URL=
    cd ../server && npm install --omit=dev
    NODE_ENV=production TRUST_PROXY_HOPS=1 IP_SALT=... node index.js   # (Render/Cloudflare: CLIENT_IP_HEADER=cf-connecting-ip instead)
Put nginx/Caddy/Cloudflare in front for HTTPS, and run coturn yourself (see `docker-compose.yml` flags).

## BEFORE YOU LAUNCH - please read
Omegle shut down in 2023 largely because of abuse and child-safety problems. Everything in this repo reduces
risk but **does not make a random-video app safe on its own**. You are the operator and legally responsible. Before real traffic:
1. **Edit and legally review** `server/public/terms.html`, `privacy.html`, `safety.html` (replace `[OPERATOR NAME]`, `[CONTACT EMAIL]`, `[COUNTRY]`).
2. **Add automated visual moderation** for video (nudity / minors), e.g. a vendor API on periodic frame samples, and be ready to act on it. This repo has no such scanner.
3. **Have a human review process** for `reports.jsonl` and a way to respond to law-enforcement requests; report child sexual abuse material to the relevant authority (in many places: NCMEC CyberTipline / local equivalent) - never keep or forward the material yourself.
4. Consider stronger age assurance than a checkbox (the checkbox alone will not stop minors).
5. Remember IP-based bans can affect people sharing a network (mobile carriers, campuses). Consider accounts or device attestation later.
6. Start small (invite-only / low traffic) and watch the logs.


## Live (how it works and its limits)
- **Guests on stage:** the host taps the group icon in the live and invites a viewer to talk (voice) or appear (camera), up to 3 guests (`MAX_GUESTS`). The guest sends their media to the host, who relays it to the other viewers, so the host uploads a bit more. Viewers can accept or refuse, and leave the stage any time; the host can remove a guest.
- Video goes **host -> each viewer directly (WebRTC)**; the server only relays signalling and comments. That keeps hosting free, but the host's phone/PC uploads one video stream per viewer, so the default cap is **10 viewers per live** (`MAX_LIVE_VIEWERS`) and **30 lives** at once (`MAX_LIVES`).
- For hundreds of viewers you need a media server (SFU) such as LiveKit: ask for that upgrade when you grow.
- TURN is important for Live too (viewers behind strict networks): see `TURN_*` in `.env.example`.
- Lives are not recorded or stored. Reports are written to `reports.jsonl` with `"kind":"live"` and the last comments.
- Server test for Live: `cd server && node test/live.js`.

## Voice quality
Echo cancellation, noise suppression and auto gain are switched on for the microphone, your own self-view never plays your own voice back (that caused the echo), and the voice codec (Opus) is set to resist packet loss (crackling). If someone still hears noise, ask them to use headphones, since speakers feeding the mic back is physics, not code.


## Visitor statistics
Every page load of the site is counted (not only people who start a chat): visitors (different people, once per day), page views, chats started, lives started, top countries. Bots and link-preview crawlers are ignored, and no raw IPs are stored.
- **Private dashboard:** `https://YOUR-SITE/stats?key=YOUR_STATS_KEY`. On Render, `STATS_KEY` is generated for you: Dashboard > your service > Environment > `STATS_KEY`.
- A small public line on the home page shows visitors today / online now.
- On Render's free plan the disk is erased on every restart/redeploy, so the counters restart from zero then. Add a persistent disk and set `DATA_DIR` to keep them.
- Test: `cd server && node test/stats.js`.
