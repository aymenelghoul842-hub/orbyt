// Server URL. Override at build time:
//   flutter build web --dart-define=SERVER_URL=https://chat.example.com
// An empty SERVER_URL means "same origin as the page" (when the Node server
// serves the built web app, which is what the Dockerfile does).
const String _env =
    String.fromEnvironment('SERVER_URL', defaultValue: 'http://localhost:3000');
String get kServerUrl => _env.isEmpty ? Uri.base.origin : _env;

/// Fallback ICE config, used only if the server's /api/ice endpoint is
/// unreachable. In production the server hands out STUN + short-lived TURN
/// credentials (see .env.example) so nothing secret lives in the client.
const Map<String, dynamic> kIceConfig = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
  ],
};

/// Text copied by the Share button (together with the site link).
const String kShareText =
    'Orbyt - meet someone new, instantly. Free anonymous video & text chat. '
    'No sign-up, no profile. 18+ only.';
