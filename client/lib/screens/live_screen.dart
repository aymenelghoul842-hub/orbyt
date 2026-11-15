import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/live_service.dart';
import '../theme.dart';
import '../widgets.dart';

const Color _liveRed = Color(0xFFFF3B5C);

String _ago(int sinceMs) {
  final m = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(sinceMs)).inMinutes;
  if (m < 1) return 'just started';
  if (m < 60) return '$m min';
  return '${m ~/ 60} h ${m % 60} min';
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: _liveRed, borderRadius: BorderRadius.circular(6)),
        child: const Text('LIVE',
            style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8)),
      );
}

Color _avatarColor(String name) {
  const palette = [
    Color(0xFF8B6CFF), Color(0xFF3DF5C8), Color(0xFFFF5FA8),
    Color(0xFFFFC857), Color(0xFF4DA3FF), Color(0xFFC6FF4D),
  ];
  var h = 0;
  for (final c in name.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return palette[h % palette.length];
}

/// One live shown as a card: who is live, from which country, how many are watching.
class LiveCard extends StatelessWidget {
  const LiveCard({super.key, required this.info, required this.onTap});
  final LiveInfo info;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _avatarColor(info.name);
    final initial =
        info.name.isEmpty ? '?' : info.name.characters.first.toUpperCase();
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: GlassCard(
        glow: _liveRed,
        padding: const EdgeInsets.all(14),
        radius: 22,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const _LiveBadge(),
              const SizedBox(width: 8),
              Flexible(
                child: Text(_ago(info.since),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.muted, fontSize: 12)),
              ),
              const Spacer(),
              const Icon(Icons.remove_red_eye_rounded,
                  size: 15, color: AppColors.muted),
              const SizedBox(width: 4),
              Text('${info.viewers}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 13)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                      colors: [color, color.withOpacity(0.45)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                  border: Border.all(color: _liveRed, width: 2.5),
                ),
                child: Text(initial,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Colors.white)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(info.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 3),
                      Row(children: [
                        if (info.countryCode.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6)),
                            child: Text(info.countryCode.toUpperCase(),
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800)),
                          ),
                        Flexible(
                          child: Text(
                              info.country.isEmpty
                                  ? 'Unknown location'
                                  : info.country,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.muted, fontSize: 13)),
                        ),
                      ]),
                    ]),
              ),
            ]),
            const Spacer(),
            Text(info.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5, height: 1.2)),
          ],
        ),
      ),
    );
  }
}

/// The first card of every list: start your own live.
class GoLiveCard extends StatelessWidget {
  const GoLiveCard({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: _liveRed.withOpacity(0.12),
          border: Border.all(color: _liveRed.withOpacity(0.75), width: 1.6),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration:
                  const BoxDecoration(color: _liveRed, shape: BoxShape.circle),
              child: const Icon(Icons.videocam_rounded,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(height: 10),
            Text('Go live', style: display(size: 19)),
            const SizedBox(height: 2),
            const Text('Start your own live',
                style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}

/// 18+ confirmation (asked once per visit, for watching or going live).
Future<bool> confirmAdult(BuildContext context) async {
  if (liveAgeConfirmed) return true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Live is for adults (18+)'),
      content: const Text(
          'Lives are public and not pre-screened. Only continue if you are 18 or older. '
          'You can report any live and leave at any time.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.muted))),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("I'm 18 or older",
                style: TextStyle(
                    color: AppColors.lime, fontWeight: FontWeight.w800))),
      ],
    ),
  );
  if (ok == true) liveAgeConfirmed = true;
  return ok == true;
}

/// "Live" button: the list of lives with the Go live button.
/// Tapping a live opens it, and then you can swipe to the next one.
Future<void> openLiveList(BuildContext context, {String? username}) async {
  if (!await confirmAdult(context)) return;
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => LiveListScreen(username: username)));
}

/// Open one live; the other lives are one swipe away.
Future<void> watchLive(BuildContext context, LiveInfo l,
    {String? username}) async {
  if (!await confirmAdult(context)) return;
  if (!context.mounted) return;
  final all = await fetchLives();
  if (!context.mounted) return;
  final order = [l, ...all.where((x) => x.id != l.id)];
  await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => LiveFeedScreen(lives: order, username: username)));
}

/// TikTok style: swipe up / down (or use the arrows) to go from one live to the next.
/// Only the live on screen is joined, the others show a placeholder.
class LiveFeedScreen extends StatefulWidget {
  const LiveFeedScreen({super.key, required this.lives, this.username});
  final List<LiveInfo> lives;
  final String? username;
  @override
  State<LiveFeedScreen> createState() => _LiveFeedScreenState();
}

class _LiveFeedScreenState extends State<LiveFeedScreen> {
  late final List<LiveInfo> _lives = List.of(widget.lives);
  final _pc = PageController();
  int _cur = 0;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 8), (_) => _refresh());
    if (_lives.length > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Swipe up or down for the next live')));
        }
      });
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    _pc.dispose();
    super.dispose();
  }

  // new lives that started meanwhile are added at the end
  Future<void> _refresh() async {
    final f = await fetchLives();
    if (!mounted) return;
    final known = _lives.map((l) => l.id).toSet();
    final fresh = f.where((l) => !known.contains(l.id)).toList();
    if (fresh.isNotEmpty) setState(() => _lives.addAll(fresh));
  }

  // this live is over (or full / kicked): move on to the next one
  void _gone(String id, String msg) {
    if (!mounted) return;
    final i = _lives.indexWhere((l) => l.id == id);
    if (i < 0) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    if (_lives.length == 1) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _lives.removeAt(i);
      if (_cur >= _lives.length) _cur = _lives.length - 1;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pc.hasClients) _pc.jumpToPage(_cur);
    });
  }

  void _go(int delta) {
    final n = _cur + delta;
    if (n < 0 || n >= _lives.length) return;
    _pc.animateToPage(n,
        duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
  }

  Widget _placeholder(LiveInfo l) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_avatarColor(l.name).withOpacity(0.5), AppColors.surface],
          ),
        ),
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const _LiveBadge(),
          const SizedBox(height: 12),
          Text(l.name, style: display(size: 24)),
          const SizedBox(height: 16),
          const CircularProgressIndicator(),
        ]),
      );

  Widget _arrow(IconData icon, String tip, VoidCallback onTap) => Material(
        color: Colors.black54,
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tip,
          onPressed: onTap,
          icon: Icon(icon, color: Colors.white),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.stylus,
            PointerDeviceKind.trackpad,
          }),
          child: PageView.builder(
            controller: _pc,
            scrollDirection: Axis.vertical,
            itemCount: _lives.length,
            onPageChanged: (i) => setState(() => _cur = i),
            itemBuilder: (ctx, i) {
              final l = _lives[i];
              if (i != _cur) return _placeholder(l);
              return LiveRoomScreen.viewer(
                key: ValueKey('live-${l.id}'),
                info: l,
                username: widget.username,
                onGone: (m) => _gone(l.id, m),
              );
            },
          ),
        ),
        if (_lives.length > 1)
          Positioned(
            right: 8,
            top: 0,
            bottom: 0,
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (_cur > 0)
                  _arrow(Icons.keyboard_arrow_up_rounded, 'Previous live',
                      () => _go(-1)),
                const SizedBox(height: 8),
                if (_cur < _lives.length - 1)
                  _arrow(Icons.keyboard_arrow_down_rounded, 'Next live',
                      () => _go(1)),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// Bottom sheet: pick a title, confirm 18+, go live.
Future<void> goLive(BuildContext context, {String? username}) async {
  final titleCtrl = TextEditingController();
  bool adult = liveAgeConfirmed;
  final start = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const _LiveBadge(),
            const SizedBox(width: 10),
            Text('Go live', style: display(size: 24)),
          ]),
          const SizedBox(height: 14),
          TextField(
            controller: titleCtrl,
            maxLength: 40,
            decoration: InputDecoration(
              counterText: '',
              hintText: 'Title (optional) e.g. Chill & chat',
              hintStyle: const TextStyle(color: AppColors.muted),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: adult,
            onChanged: (v) => setS(() => adult = v ?? false),
            activeColor: AppColors.lime,
            checkColor: AppColors.onCta,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text(
                "I'm 18 or older, and I agree to the Terms. No nudity, hate, violence or illegal content.",
                style: TextStyle(fontSize: 13.5, height: 1.4)),
          ),
          const Text(
              'Your camera and microphone go live to everyone who joins. Your country is shown on your live.',
              style: TextStyle(
                  color: AppColors.muted, fontSize: 12.5, height: 1.4)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: GradientButton(
              label: 'Start live',
              icon: Icons.videocam_rounded,
              onPressed: adult ? () => Navigator.pop(ctx, true) : null,
            ),
          ),
        ]),
      ),
    ),
  );
  final title = titleCtrl.text.trim();
  titleCtrl.dispose();
  if (start == true && context.mounted) {
    liveAgeConfirmed = true;
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => LiveRoomScreen.host(title: title, username: username)));
  }
}

// ---------------------------------------------------------------- strip on the home page
/// Horizontal strip at the top of the home page: who is live right now.
class LiveStrip extends StatefulWidget {
  const LiveStrip({super.key, this.username});
  final String? username;
  @override
  State<LiveStrip> createState() => _LiveStripState();
}

class _LiveStripState extends State<LiveStrip> {
  List<LiveInfo> _lives = const [];
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _load();
    _t = Timer.periodic(const Duration(seconds: 8), (_) => _load());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final l = await fetchLives();
    if (mounted) setState(() => _lives = l);
  }

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      SizedBox(
        width: 150,
        child: GoLiveCard(
            onTap: () => goLive(context, username: widget.username)),
      ),
      for (final l in _lives)
        SizedBox(
          width: 250,
          child: LiveCard(
              info: l,
              onTap: () => watchLive(context, l, username: widget.username)),
        ),
      if (_lives.isEmpty)
        SizedBox(
          width: 230,
          child: Center(
            child: Text('Nobody is live yet.\nBe the first!',
                style: TextStyle(color: AppColors.muted, fontSize: 14, height: 1.4)),
          ),
        ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const _LiveBadge(),
        const SizedBox(width: 8),
        Text(_lives.isEmpty ? 'Live' : 'Live now · ${_lives.length}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const Spacer(),
        TextButton(
          onPressed: () => openLiveList(context, username: widget.username),
          child: const Text('See all',
              style: TextStyle(
                  color: AppColors.mint, fontWeight: FontWeight.w700)),
        ),
      ]),
      const SizedBox(height: 6),
      SizedBox(
        height: 140,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) => items[i],
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- full list page
class LiveListScreen extends StatefulWidget {
  const LiveListScreen({super.key, this.username});
  final String? username;
  @override
  State<LiveListScreen> createState() => _LiveListScreenState();
}

class _LiveListScreenState extends State<LiveListScreen> {
  List<LiveInfo> _lives = const [];
  bool _loaded = false;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _load();
    _t = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final l = await fetchLives();
    if (mounted) {
      setState(() {
        _lives = l;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final cols = w > 900 ? 3 : (w > 560 ? 2 : 1);
    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                child: Column(children: [
                  Row(children: [
                    IconButton(
                      tooltip: 'Back',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const _LiveBadge(),
                    const SizedBox(width: 10),
                    Text('Live now',
                        style: display(size: 26, letterSpacing: -0.6)),
                    const Spacer(),
                    GradientButton(
                      label: 'Go live',
                      icon: Icons.videocam_rounded,
                      height: 44,
                      onPressed: () =>
                          goLive(context, username: widget.username),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  Expanded(
                    child: !_loaded
                        ? const Center(child: CircularProgressIndicator())
                        : GridView.builder(
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: cols,
                                  mainAxisSpacing: 14,
                                  crossAxisSpacing: 14,
                                  mainAxisExtent: 160,
                                ),
                                itemCount: _lives.length + 1,
                                itemBuilder: (_, i) => i == 0
                                    ? GoLiveCard(
                                        onTap: () => goLive(context,
                                            username: widget.username))
                                    : LiveCard(
                                        info: _lives[i - 1],
                                        onTap: () => watchLive(
                                            context, _lives[i - 1],
                                            username: widget.username)),
                              ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- the live room (host + viewer)
class LiveRoomScreen extends StatefulWidget {
  const LiveRoomScreen.host({super.key, required this.title, this.username})
      : isHost = true,
        info = null,
        onGone = null;
  const LiveRoomScreen.viewer(
      {super.key, required this.info, this.username, this.onGone})
      : isHost = false,
        title = '';
  /// Used by the swipe feed: called instead of closing the screen when this live is over.
  final void Function(String message)? onGone;
  final bool isHost;
  final String title;
  final LiveInfo? info;
  final String? username;
  @override
  State<LiveRoomScreen> createState() => _LiveRoomScreenState();
}

class _LiveRoomScreenState extends State<LiveRoomScreen> {
  late final LiveService svc;
  final _comments = <LiveComment>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _hasVideo = false;
  bool _closing = false;
  String _status = 'Starting...';
  int _count = 0;
  bool _mic = true, _cam = true;
  final _viewersTick = ValueNotifier<int>(0);
  bool _inviteDialogOpen = false;

  @override
  void initState() {
    super.initState();
    svc = widget.isHost
        ? LiveService.host(title: widget.title, username: widget.username)
        : LiveService.viewer(liveId: widget.info!.id, username: widget.username);
    svc.onInfo = () {
      if (mounted) setState(() {});
    };
    svc.onStatus = (s) {
      if (mounted) setState(() => _status = s);
    };
    svc.onCount = (n) {
      if (mounted) setState(() => _count = n);
    };
    svc.onVideo = () {
      if (mounted) setState(() => _hasVideo = true);
    };
    svc.onComment = (c) {
      if (!mounted) return;
      setState(() {
        _comments.add(c);
        if (_comments.length > 80) _comments.removeAt(0);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    };
    svc.onNotice = (t) => _snack(t);
    svc.onGuests = () {
      if (mounted) setState(() {});
    };
    svc.onViewers = () {
      _viewersTick.value++;
    };
    svc.onInvite = (video, host) => _askInvite(video, host);
    svc.onGuestState = (st) {
      if (!mounted) return;
      if (st == 'guest') {
        setState(() {
          _mic = true;
          _cam = true;
        });
        _snack('You are on stage. Everyone can hear you now.');
      } else if (st == 'muted' || st == 'unmuted') {
        setState(() => _mic = svc.micOn);
        _snack(st == 'muted'
            ? 'The host muted your microphone.'
            : 'The host unmuted you.');
      } else if (st == 'removed') {
        setState(() {});
        _snack('The host ended your guest spot.');
      } else if (st == 'left') {
        setState(() {});
      } else if (st == 'full') {
        _snack('The stage is full right now.');
      } else if (st == 'cancelled') {
        if (_inviteDialogOpen && Navigator.of(context, rootNavigator: true).canPop()) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      }
    };
    svc.onEnded = (why) {
      if (!mounted || _closing) return;
      _closing = true;
      final msg = why == 'kicked'
          ? 'The host removed you from this live.'
          : why == 'banned'
              ? 'This live was ended.'
              : widget.isHost
                  ? 'Your live ended.'
                  : 'This live has ended.';
      _leaveWith(msg);
    };
    svc.onError = (code) {
      if (!mounted || _closing) return;
      _closing = true;
      const m = {
        'camera': 'Camera/microphone permission was denied.',
        'full': 'This live is full right now. Try again in a minute.',
        'not_found': 'This live is over.',
        'kicked': 'The host removed you from this live.',
        'busy': 'Too many lives right now. Try again soon.',
        'rate': 'You started too many lives. Please wait a bit.',
        'adult_required': 'You must confirm you are 18+.',
      };
      _leaveWith(code == 'camera' && svc.cameraProblem.isNotEmpty
          ? svc.cameraProblem
          : (m[code] ?? 'Could not open the live.'));
    };
    svc.init();
  }

  void _leaveWith(String msg) {
    if (!mounted) return;
    if (widget.onGone != null) {
      widget.onGone!(msg);
      return;
    }
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    nav.pop();
    messenger.showSnackBar(SnackBar(content: Text(msg)));
  }

  void _snack(String t) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
    }
  }

  @override
  void dispose() {
    svc.dispose();
    _input.dispose();
    _scroll.dispose();
    _viewersTick.dispose();
    super.dispose();
  }

  void _send() {
    final t = _input.text.trim();
    if (t.isEmpty) return;
    svc.comment(t);
    _input.clear();
  }

  Future<bool> _confirmEnd() async {
    if (!widget.isHost) return true;
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('End your live?'),
        content: const Text('Everyone watching will be disconnected.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep going',
                  style: TextStyle(color: AppColors.muted))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('End live',
                  style: TextStyle(color: _liveRed, fontWeight: FontWeight.w800))),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _close() async {
    if (await _confirmEnd() && mounted) {
      _closing = true;
      Navigator.pop(context);
    }
  }

  Future<void> _report() async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Report this live',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          ),
          for (final r in const [
            ['nudity', 'Nudity or sexual content'],
            ['minor', 'Looks under 18'],
            ['harassment', 'Harassment or hate'],
            ['spam', 'Spam or scam'],
            ['other', 'Something else'],
          ])
            ListTile(
              title: Text(r[1]),
              onTap: () => Navigator.pop(ctx, r[0]),
            ),
        ]),
      ),
    );
    if (reason != null) {
      svc.report(reason);
      _snack('Thanks. Your report was sent.');
    }
  }

  // viewer: the host invites me on stage
  Future<void> _askInvite(bool video, String host) async {
    if (!mounted || _inviteDialogOpen) return;
    _inviteDialogOpen = true;
    final yes = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(video ? 'Join live with camera?' : 'Join live with your voice?'),
        content: Text(video
            ? '${host.isEmpty ? "The host" : host} invites you on stage. Your camera and microphone will be seen and heard by everyone in this live. You can leave the stage at any time.'
            : '${host.isEmpty ? "The host" : host} invites you to talk. Your microphone will be heard by everyone in this live. No camera. You can leave the stage at any time.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not now',
                  style: TextStyle(color: AppColors.muted))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(video ? 'Join with camera' : 'Join with voice',
                  style: const TextStyle(
                      color: AppColors.lime, fontWeight: FontWeight.w800))),
        ],
      ),
    );
    _inviteDialogOpen = false;
    if (!mounted) return;
    if (yes == true) {
      await svc.acceptInvite(video);
    } else if (yes == false) {
      svc.declineInvite();
    }
  }

  // host: list of viewers with invite buttons
  Future<void> _peopleSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: ValueListenableBuilder<int>(
            valueListenable: _viewersTick,
            builder: (_, __, ___) {
              final list = svc.viewerList;
              return Column(mainAxisSize: MainAxisSize.min, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Row(children: [
                    Text('Invite on stage', style: display(size: 20)),
                    const Spacer(),
                    Text('${svc.guests.length}/3',
                        style: const TextStyle(color: AppColors.muted)),
                  ]),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                        'Pick a viewer to talk with you (voice) or appear (camera).',
                        style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  ),
                ),
                if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(28),
                    child: Text('Nobody is watching yet.',
                        style: TextStyle(color: AppColors.muted)),
                  )
                else
                  Flexible(
                    child: ListView(shrinkWrap: true, children: [
                      for (final v in list)
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _avatarColor(v.name),
                            child: Text(
                                v.name.isEmpty ? '?' : v.name.characters.first.toUpperCase(),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900)),
                          ),
                          title: Text(v.name,
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: v.guest
                              ? const Text('On stage',
                                  style: TextStyle(color: AppColors.lime))
                              : v.invited
                                  ? const Text('Invite sent...',
                                      style: TextStyle(color: AppColors.muted))
                                  : null,
                          trailing: v.guest
                              ? Row(mainAxisSize: MainAxisSize.min, children: [
                                  IconButton(
                                    tooltip: 'Mute / unmute',
                                    icon: Icon(
                                        svc.guests.any((g) => g.sid == v.sid && g.muted)
                                            ? Icons.mic_off_rounded
                                            : Icons.mic_rounded,
                                        color: AppColors.mint),
                                    onPressed: () => svc.muteGuest(
                                        v.sid,
                                        !svc.guests.any((g) => g.sid == v.sid && g.muted)),
                                  ),
                                  TextButton(
                                      onPressed: () => svc.removeGuest(v.sid),
                                      child: const Text('Remove',
                                          style: TextStyle(color: _liveRed))),
                                  IconButton(
                                    tooltip: 'Block',
                                    icon: const Icon(Icons.block_rounded,
                                        color: _liveRed),
                                    onPressed: () => svc.kick(v.sid),
                                  ),
                                ])
                              : v.invited
                                  ? TextButton(
                                      onPressed: () => svc.cancelInvite(v.sid),
                                      child: const Text('Cancel',
                                          style: TextStyle(color: AppColors.muted)))
                                  : Row(mainAxisSize: MainAxisSize.min, children: [
                                      IconButton(
                                        tooltip: 'Block',
                                        icon: const Icon(Icons.block_rounded,
                                            color: _liveRed),
                                        onPressed: () => svc.kick(v.sid),
                                      ),
                                      IconButton(
                                        tooltip: 'Invite with voice',
                                        icon: const Icon(Icons.mic_rounded,
                                            color: AppColors.mint),
                                        onPressed: () => svc.invite(v.sid, false),
                                      ),
                                      IconButton(
                                        tooltip: 'Invite with camera',
                                        icon: const Icon(Icons.videocam_rounded,
                                            color: AppColors.lime),
                                        onPressed: () => svc.invite(v.sid, true),
                                      ),
                                    ]),
                        ),
                    ]),
                  ),
                const SizedBox(height: 8),
              ]);
            },
          ),
        ),
      ),
    );
  }

  Future<void> _guestMenu(GuestInfo g) async {
    if (!widget.isHost) return;
    final act = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(g.muted ? Icons.mic_rounded : Icons.mic_off_rounded,
                color: AppColors.mint),
            title: Text(g.muted ? 'Unmute ${g.name}' : 'Mute ${g.name}'),
            onTap: () => Navigator.pop(ctx, 'mute'),
          ),
          ListTile(
            leading: const Icon(Icons.person_remove_rounded, color: _liveRed),
            title: Text('Remove ${g.name} from the stage'),
            onTap: () => Navigator.pop(ctx, 'remove'),
          ),
          ListTile(
            leading: const Icon(Icons.block_rounded, color: _liveRed),
            title: Text('Block ${g.name} from your live'),
            onTap: () => Navigator.pop(ctx, 'block'),
          ),
        ]),
      ),
    );
    if (act == 'mute') svc.muteGuest(g.sid, !g.muted);
    if (act == 'remove') svc.removeGuest(g.sid);
    if (act == 'block') svc.kick(g.sid);
  }

  /// Small tiles of the people on stage (row under the title).
  Widget _guestTiles() {
    final tiles = <Widget>[];
    Widget tile(String name, bool video, RTCVideoRenderer? r,
        {bool mirror = false, bool muted = false, VoidCallback? onTap, VoidCallback? onLeave}) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: 84,
          height: 112,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.lime.withOpacity(0.8), width: 1.6),
            color: AppColors.surface,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(fit: StackFit.expand, children: [
              if (r != null)
                RTCVideoView(r,
                    mirror: mirror,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
              if (!video)
                Container(
                  color: AppColors.surface,
                  alignment: Alignment.center,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: _avatarColor(name),
                      child: Text(
                          name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(height: 6),
                    Icon(muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        size: 16, color: muted ? _liveRed : AppColors.lime),
                  ]),
                ),
              if (video && muted)
                const Positioned(
                    left: 4,
                    top: 4,
                    child: Icon(Icons.mic_off_rounded, size: 16, color: _liveRed)),
              if (onLeave != null)
                Positioned(
                  right: 3,
                  top: 3,
                  child: GestureDetector(
                    onTap: onLeave,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                          color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(Icons.close_rounded, size: 16),
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  color: Colors.black54,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ),
        ),
      );
    }

    if (!widget.isHost && svc.isGuest) {
      tiles.add(tile('You', svc.guestVideo, svc.guestVideo ? svc.localRenderer : null,
          mirror: true, muted: svc.hostMuted || !_mic, onLeave: svc.leaveStage));
    }
    for (final g in svc.guests) {
      if (!widget.isHost && g.sid == svc.mySid) continue;
      tiles.add(tile(g.name, g.video, svc.guestRenderers[g.sid],
          muted: g.muted,
          onTap: widget.isHost ? () => _guestMenu(g) : null));
    }
    if (tiles.isEmpty) {
      return const Positioned(left: 0, top: 0, child: SizedBox.shrink());
    }
    return Positioned(
      left: 12,
      right: 12,
      top: 108,
      child: SingleChildScrollView(
          scrollDirection: Axis.horizontal, child: Row(children: tiles)),
    );
  }

  Future<void> _commentMenu(LiveComment c) async {
    if (!widget.isHost || c.host || c.sid.isEmpty) return;
    final act = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.mic_rounded, color: AppColors.mint),
            title: Text('Invite ${c.name} to talk (voice)'),
            onTap: () => Navigator.pop(ctx, 'voice'),
          ),
          ListTile(
            leading: const Icon(Icons.videocam_rounded, color: AppColors.lime),
            title: Text('Invite ${c.name} with camera'),
            onTap: () => Navigator.pop(ctx, 'video'),
          ),
          ListTile(
            leading: const Icon(Icons.person_remove_rounded, color: _liveRed),
            title: Text('Remove ${c.name} from your live'),
            onTap: () => Navigator.pop(ctx, 'kick'),
          ),
        ]),
      ),
    );
    if (act == 'kick') svc.kick(c.sid);
    if (act == 'voice') svc.invite(c.sid, false);
    if (act == 'video') svc.invite(c.sid, true);
  }

  Widget _video() {
    final renderer = widget.isHost ? svc.localRenderer : svc.remoteRenderer;
    return Stack(fit: StackFit.expand, children: [
      Container(color: Colors.black),
      RTCVideoView(renderer,
          mirror: widget.isHost,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
      if (!widget.isHost && !_hasVideo)
        Container(
          color: AppColors.bg,
          alignment: Alignment.center,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 14),
            Text(_status.isEmpty ? 'Connecting...' : _status,
                style: const TextStyle(color: AppColors.muted)),
          ]),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isHost
        ? (widget.title.isEmpty ? 'Your live' : widget.title)
        : (svc.liveTitle.isEmpty ? widget.info!.title : svc.liveTitle);
    final who = widget.isHost
        ? 'You'
        : (svc.hostName.isEmpty ? widget.info!.name : svc.hostName);
    return PopScope(
      canPop: !widget.isHost,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _close();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(fit: StackFit.expand, children: [
                      _video(),
                      // top bar
                      Positioned(
                        left: 10,
                        right: 10,
                        top: 10,
                        child: Row(children: [
                          const _LiveBadge(),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(20)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.remove_red_eye_rounded,
                                  size: 14, color: Colors.white),
                              const SizedBox(width: 4),
                              Text('$_count',
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700)),
                            ]),
                          ),
                          const Spacer(),
                          if (!widget.isHost)
                            RoundIconButton(
                                icon: Icons.flag_rounded,
                                tooltip: 'Report',
                                onPressed: _report),
                          const SizedBox(width: 8),
                          RoundIconButton(
                              icon: Icons.close_rounded,
                              tooltip: widget.isHost ? 'End live' : 'Leave',
                              onPressed: _close),
                        ]),
                      ),
                      // title + host name
                      Positioned(
                        left: 14,
                        right: 14,
                        top: 58,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 17,
                                      shadows: [
                                        Shadow(blurRadius: 6, color: Colors.black)
                                      ])),
                              Text(
                                  svc.hostCountry.isEmpty
                                      ? who
                                      : '$who · ${svc.hostCountry}',
                                  style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                      shadows: [
                                        Shadow(blurRadius: 6, color: Colors.black)
                                      ])),
                            ]),
                      ),
                      _guestTiles(),
                      if (widget.isHost || svc.isGuest)
                        Positioned(
                          right: 12,
                          bottom: 190,
                          child: Column(children: [
                            RoundIconButton(
                              icon: _mic
                                  ? Icons.mic_rounded
                                  : Icons.mic_off_rounded,
                              tooltip: 'Mic',
                              onPressed: () {
                                svc.toggleMic();
                                setState(() => _mic = svc.micOn);
                              },
                            ),
                            if (widget.isHost || svc.guestVideo) ...[
                              const SizedBox(height: 8),
                              RoundIconButton(
                                icon: _cam
                                    ? Icons.videocam_rounded
                                    : Icons.videocam_off_rounded,
                                tooltip: 'Camera',
                                onPressed: () {
                                  svc.toggleCam();
                                  setState(() => _cam = svc.camOn);
                                },
                              ),
                            ],
                            if (widget.isHost) ...[
                              const SizedBox(height: 8),
                              RoundIconButton(
                                icon: Icons.group_add_rounded,
                                tooltip: 'Invite viewers on stage',
                                onPressed: _peopleSheet,
                              ),
                            ] else ...[
                              const SizedBox(height: 8),
                              RoundIconButton(
                                icon: Icons.call_end_rounded,
                                tooltip: 'Leave the stage',
                                danger: true,
                                onPressed: svc.leaveStage,
                              ),
                            ],
                          ]),
                        ),
                      // comments
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 180,
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black87],
                            ),
                          ),
                          child: ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(12, 30, 70, 10),
                            itemCount: _comments.length,
                            itemBuilder: (_, i) {
                              final c = _comments[i];
                              return InkWell(
                                onTap: () => _commentMenu(c),
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 2),
                                  child: Text.rich(TextSpan(children: [
                                    TextSpan(
                                        text: '${c.name}${c.host ? " (host)" : ""}  ',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: c.host
                                                ? AppColors.lime
                                                : AppColors.mint,
                                            fontSize: 13.5)),
                                    TextSpan(
                                        text: c.text,
                                        style: const TextStyle(fontSize: 14)),
                                  ])),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
                // comment box
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        maxLength: 200,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: 'Write a comment...',
                          hintStyle: const TextStyle(color: AppColors.muted),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.06),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 12),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    RoundIconButton(
                        icon: Icons.send_rounded,
                        tooltip: 'Send',
                        onPressed: _send),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
