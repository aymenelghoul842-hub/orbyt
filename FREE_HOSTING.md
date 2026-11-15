# Run Orbyt public for FREE

Camera and microphone only work on **HTTPS** - every option below gives you HTTPS for free.

## Option C - NO Flutter on your PC (recommended): GitHub builds it, Render hosts it
One free link serves BOTH the Flutter web app and the server (`https://orbyt-xxxx.onrender.com`).

1. Create a free account at github.com and a **new repository** (e.g. `orbyt`).
2. Upload this project to it. Easiest with git (install from git-scm.com), inside the `orbyt` folder:
       git init
       git add -A
       git commit -m "Orbyt"
       git branch -M main
       git remote add origin https://github.com/YOUR-NAME/orbyt.git
       git push -u origin main
   (Make sure the hidden `.github` folder and `web-dist` are included - git does this for you.)
3. On GitHub open the **Actions** tab -> "Build Flutter web" -> **Run workflow**. Wait ~5 minutes until it is green.
   It builds the Flutter app and saves it into `web-dist` for you. (It re-runs by itself whenever you change `client/`.)
4. Go to render.com -> sign up with GitHub -> **New +** -> **Blueprint** -> pick the repo -> Apply.
5. When the deploy finishes, open your `.onrender.com` link. Done - app + server on one address.

Free Render sleeps after ~15 min idle (first visit ~30 s) and forgets bans on restart.

---

## Option A - From your own PC, live in 10 minutes (Cloudflare Tunnel)
Best for trying it with friends. Your PC must stay on.

1. Build the app once (needs Flutter):
       cd client
       flutter pub get
       flutter build web --release --dart-define=SERVER_URL=
2. Start the server (IMPORTANT: CLIENT_IP_HEADER=cf-connecting-ip, otherwise everyone looks like one IP, one ban hits all, and every country shows as wrong):
   - Windows (cmd):  `cd server && npm install && set CLIENT_IP_HEADER=cf-connecting-ip && npm start`
   - Mac/Linux:      `cd server && npm install && CLIENT_IP_HEADER=cf-connecting-ip npm start`
3. Install cloudflared (free, no account needed for quick tunnels):
   - Windows: `winget install Cloudflare.cloudflared`   - Mac: `brew install cloudflared`
4. In another terminal:  `cloudflared tunnel --url http://localhost:3000`
5. It prints a link like `https://random-words.trycloudflare.com` - that's your public site. Share it.
   (The link changes each time you restart the tunnel.)

## Option B - Permanent free link (Render.com)
Gives `https://orbyt-xxxx.onrender.com`. Free plan sleeps after ~15 min idle (first visit takes ~30 s to wake) and
forgets bans when it restarts. Fine for starting out.

1. Build the app once on your PC (same as step 1 above), then copy the result:
       Windows:  xcopy /E /I client\build\web web-dist
       Mac/Linux: cp -r client/build/web web-dist
2. Put the whole `orbyt` folder in a new **GitHub** repository (free): github.com -> New repository -> upload files
   (make sure `web-dist/` is included).
3. Go to render.com -> sign up with GitHub -> **New +** -> **Blueprint** -> choose your repo -> Apply.
   It reads `render.yaml` automatically.
4. Wait for the build (~3 min). Open your `.onrender.com` link.

## Video not connecting for some people?
That's the missing TURN relay (strict networks / mobile data). Free fix: create a free account at
metered.ca (Open Relay), copy the TURN details, and add these environment variables
(Render: Environment tab; local: set before `npm start`):

    TURN_URLS=turn:YOUR-HOST:80,turns:YOUR-HOST:443?transport=tcp
    TURN_USERNAME=...
    TURN_CREDENTIAL=...

## Free domain name (optional)
Use the free `.onrender.com` link, or get a free name at duckdns.org / a cheap domain later and add it in Render -> Settings -> Custom Domains.

## Still do before sharing widely
Edit `server/public/terms.html`, `privacy.html`, `safety.html` (replace `[OPERATOR NAME]`, `[CONTACT EMAIL]`, `[COUNTRY]`) and read the "BEFORE YOU LAUNCH" section of README.md.
