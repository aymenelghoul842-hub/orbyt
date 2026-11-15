import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../languages.dart';
import '../services/chat_service.dart';
import '../theme.dart';
import '../widgets.dart';

enum _Kind { system, you, stranger }

class _Line {
  _Line(this.kind, this.text, {this.label = ''});
  final _Kind kind;
  final String text;
  final String label; // sender label for stranger lines
}

enum _Phase { searching, chatting, ended }

const _youColor = Color(0xFF4DA3FF); // "You:" (blue)
const _strangerColor = Color(0xFFFF5A5F); // "Stranger:" (red)

const _emojis = [
  '😀', '😁', '😂', '🤣', '😊', '😍', '😘', '😎', '🤔', '😅',
  '😢', '😭', '😡', '👍', '👎', '👋', '🙏', '❤️', '🔥', '🎉',
  '😴', '😜', '🤗', '😇', '🥳', '🤝', '💪', '🙈', '👀', '✨',
  '🌍', '😉', '😏', '🙂', '😮', '🤩', '😐', '🙄', '😬', '🤪',
];

class ChatScreen extends StatefulWidget {
  const ChatScreen(
      {super.key,
      required this.video,
      this.interests = const [],
      this.language = kAnyLang,
      this.username});
  final bool video;
  final List<String> interests;
  final String language; // language code, or 'any'
  final String? username;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  late final ChatService svc;
  final lines = <_Line>[];
  final input = TextEditingController();
  final inputFocus = FocusNode();
  final scroll = ScrollController();

  _Phase phase = _Phase.searching;
  bool confirmStop = false; // button shows "Really?"
  Timer? _confirmTimer;
  Timer? _typingTimer;
  Timer? _searchTimer; // after a while, offer to match with any language
  bool showAnyLang = false;
  int online = 0;
  bool typing = false; // the stranger is typing
  bool micOn = true, camOn = true;
  String partnerName = '';
  String partnerCountry = '';
  String partnerLang = kAnyLang;
  bool hidden = false; // tab not in front: hide the stranger's video

  String get strangerLabel =>
      (partnerName.isEmpty || partnerName == 'Anonymous') ? 'Stranger' : partnerName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    svc = ChatService(
        video: widget.video,
        interests: widget.interests,
        language: widget.language,
        username: widget.username);

    svc.onSearching = () {
      if (!mounted || phase == _Phase.searching && lines.isNotEmpty) return;
      setState(() {
        phase = _Phase.searching;
        confirmStop = false;
        typing = false;
        showAnyLang = false;
        lines
          ..clear()
          ..add(_Line(
              _Kind.system,
              svc.language == kAnyLang
                  ? 'Looking for someone you can chat with. Hold on...'
                  : 'Looking for someone who speaks ${langByCode(svc.language).name}. Hold on...'));
      });
      _searchTimer?.cancel();
      if (svc.language != kAnyLang) {
        _searchTimer = Timer(const Duration(seconds: 20), () {
          if (mounted && phase == _Phase.searching) {
            setState(() => showAnyLang = true);
          }
        });
      }
    };
    svc.onMatch = (name, country, common) {
      if (!mounted) return;
      _searchTimer?.cancel();
      setState(() {
        phase = _Phase.chatting;
        confirmStop = false;
        showAnyLang = false;
        partnerLang = svc.partnerLanguage;
        lines
          ..clear()
          ..add(_Line(_Kind.system,
              'You\'re now chatting with ${name == 'Anonymous' ? 'a random stranger' : name} from $country. Say hi!'));
        if (partnerLang != kAnyLang) {
          lines.add(_Line(_Kind.system,
              'Language: ${langByCode(partnerLang).native}'));
        }
        if (common.isNotEmpty) {
          lines.add(_Line(_Kind.system, 'You both like: ${common.join(', ')}.'));
        }
        lines.add(_Line(_Kind.system,
            'Never share personal info. Anyone can screenshot or record. Use Report if someone makes you uncomfortable.'));
      });
      _scrollDown();
      inputFocus.requestFocus();
    };
    svc.onPartnerLeft = () {
      if (!mounted) return;
      setState(() {
        phase = _Phase.ended;
        typing = false;
        confirmStop = false;
        lines
          ..add(_Line(_Kind.system, 'Stranger has disconnected.'))
          ..add(_Line(_Kind.system, 'Click New to chat with someone else.'));
      });
      _scrollDown();
    };
    svc.onStatus = (s) {
      if (!mounted) return;
      setState(() {
        if (phase == _Phase.chatting) phase = _Phase.ended;
        lines.add(_Line(_Kind.system, s));
      });
      _scrollDown();
    };
    svc.onMessage = (t, mine) {
      if (!mounted) return;
      setState(() => lines.add(mine
          ? _Line(_Kind.you, t)
          : _Line(_Kind.stranger, t, label: strangerLabel)));
      _scrollDown();
    };
    svc.onPartner = (n, c) {
      if (mounted) setState(() { partnerName = n; partnerCountry = c; });
    };
    svc.onOnline = (n) {
      if (mounted) setState(() => online = n);
    };
    svc.onTyping = (v) {
      if (mounted) setState(() => typing = v);
    };
    svc.onNotice = (t) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
    };
    svc.onBanned = () {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text('You have been banned', style: display(size: 20)),
          content: const Text(
              'Other users reported you for breaking the rules. The ban is temporary.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
          ],
        ),
      ).then((_) {
        if (mounted) Navigator.of(context).pop();
      });
    };

    svc.init().then((_) {
      if (mounted) setState(() {});
    });
  }

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) {
          scroll.animateTo(scroll.position.maxScrollExtent + 80,
              duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
        }
      });

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() => hidden = state != AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _confirmTimer?.cancel();
    _typingTimer?.cancel();
    _searchTimer?.cancel();
    svc.dispose();
    input.dispose();
    inputFocus.dispose();
    scroll.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ actions
  /// Omegle flow: Stop -> "Really?" -> (disconnected) New -> searching ...
  void _stopNew() {
    if (phase == _Phase.ended) {
      svc.findNew();
      return;
    }
    if (!confirmStop) {
      setState(() => confirmStop = true);
      _confirmTimer?.cancel();
      _confirmTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => confirmStop = false);
      });
      return;
    }
    _confirmTimer?.cancel();
    svc.stop();
    setState(() {
      confirmStop = false;
      phase = _Phase.ended;
      typing = false;
      lines
        ..add(_Line(_Kind.system, 'You have disconnected.'))
        ..add(_Line(_Kind.system, 'Click New to chat with someone else.'));
    });
    _scrollDown();
  }

  void _send() {
    final t = input.text.trim();
    if (t.isEmpty || phase != _Phase.chatting) return;
    svc.send(t);
    svc.typing(false);
    input.clear();
    inputFocus.requestFocus();
  }

  void _onChanged(String v) {
    if (phase != _Phase.chatting) return;
    svc.typing(v.isNotEmpty);
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () => svc.typing(false));
  }

  Future<void> _report() async {
    const reasons = <String, String>{
      'nudity': 'Nudity or sexual content',
      'minor': 'Seems to be under 18',
      'harassment': 'Harassment or hate',
      'spam': 'Spam or scam',
      'other': 'Something else',
    };
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Report this user', style: display(size: 20)),
        children: [
          for (final e in reasons.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, e.key),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(e.value, style: const TextStyle(fontSize: 15)),
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.muted)),
          ),
        ],
      ),
    );
    if (reason == null || !mounted || phase != _Phase.chatting) return;
    svc.report(reason);
    svc.stop();
    setState(() {
      phase = _Phase.ended;
      typing = false;
      lines
        ..add(_Line(_Kind.system, 'You reported this user and disconnected. Thank you for keeping Orbyt safe.'))
        ..add(_Line(_Kind.system, 'Click New to chat with someone else.'));
    });
    _scrollDown();
  }

  void _openEmojis() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final e in _emojis)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _insertEmoji(e),
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(
                            child: Text(e, style: const TextStyle(fontSize: 26))),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _insertEmoji(String e) {
    final t = input.text;
    final sel = input.selection;
    final start = sel.isValid ? sel.start : t.length;
    final end = sel.isValid ? sel.end : t.length;
    input.value = TextEditingValue(
      text: t.replaceRange(start, end, e),
      selection: TextSelection.collapsed(offset: start + e.length),
    );
  }

  // ------------------------------------------------------------ video tiles
  Widget _tile({required Widget child}) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        child: child,
      );

  /// Top-left box in Omegle: the stranger.
  Widget _strangerTile() {
    final connected = phase == _Phase.chatting;
    return _tile(
      child: Stack(fit: StackFit.expand, children: [
        RTCVideoView(svc.remoteRenderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
        if (!connected || hidden)
          Container(
            color: AppColors.bg,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(12),
            child: hidden && connected
                ? const Icon(Icons.lock_rounded, size: 40, color: AppColors.muted)
                : phase == _Phase.searching
                    ? Column(mainAxisSize: MainAxisSize.min, children: const [
                        AnimatedOrbit(size: 64),
                        SizedBox(height: 12),
                        Text('Looking for someone...',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: AppColors.muted)),
                      ])
                    : Column(mainAxisSize: MainAxisSize.min, children: const [
                        Icon(Icons.person_off_rounded,
                            size: 40, color: AppColors.muted),
                        SizedBox(height: 10),
                        Text('Click New to meet someone else',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: AppColors.muted)),
                      ]),
          ),
        if (connected && partnerName.isNotEmpty)
          Positioned(
            left: 10,
            bottom: 10,
            child: Pill(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.public_rounded, size: 14, color: AppColors.mint),
                const SizedBox(width: 6),
                Text(
                    partnerLang == kAnyLang
                        ? '$strangerLabel · $partnerCountry'
                        : '$strangerLabel · $partnerCountry · ${langByCode(partnerLang).badge}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
      ]),
    );
  }

  /// Bottom-left box in Omegle: you.
  Widget _youTile() {
    return _tile(
      child: Stack(fit: StackFit.expand, children: [
        RTCVideoView(svc.localRenderer,
            mirror: true,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
        Positioned(
          right: 8,
          bottom: 8,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            RoundIconButton(
              icon: micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
              tooltip: micOn ? 'Mute microphone' : 'Unmute microphone',
              size: 34,
              active: micOn,
              onPressed: () {
                svc.toggleMic();
                setState(() => micOn = !micOn);
              },
            ),
            const SizedBox(width: 6),
            RoundIconButton(
              icon: camOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
              tooltip: camOn ? 'Turn camera off' : 'Turn camera on',
              size: 34,
              active: camOn,
              onPressed: () {
                svc.toggleCam();
                setState(() => camOn = !camOn);
              },
            ),
          ]),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------ chat log
  Widget _lineView(_Line l) {
    if (l.kind == _Kind.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text(l.text,
            style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: Color(0xFFC9CBE0))),
      );
    }
    final you = l.kind == _Kind.you;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(
            text: '${you ? 'You' : l.label}: ',
            style: TextStyle(
                fontWeight: FontWeight.w800,
                color: you ? _youColor : _strangerColor),
          ),
          TextSpan(text: l.text),
        ]),
        style: const TextStyle(fontSize: 15, height: 1.4),
      ),
    );
  }

  Widget _chatLog() {
    final extra = (typing && phase == _Phase.chatting) ? 1 : 0;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: ListView.builder(
        controller: scroll,
        itemCount: lines.length + extra,
        itemBuilder: (_, i) {
          if (i >= lines.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('$strangerLabel is typing...',
                  style: const TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: AppColors.muted)),
            );
          }
          return _lineView(lines[i]);
        },
      ),
    );
  }

  // ------------------------------------------------------------ bottom bar
  Widget _stopNewButton() {
    final ended = phase == _Phase.ended;
    if (ended) {
      return GradientButton(label: 'New', icon: Icons.refresh_rounded, height: 48, onPressed: _stopNew);
    }
    return SizedBox(
      height: 48,
      child: OutlinedButton(
        onPressed: _stopNew,
        style: OutlinedButton.styleFrom(
          foregroundColor: confirmStop ? Colors.white : AppColors.text,
          backgroundColor: confirmStop ? const Color(0xFFEF4444) : Colors.transparent,
          side: BorderSide(
              color: confirmStop ? const Color(0xFFEF4444) : Colors.white24),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 22),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(confirmStop ? 'Really?' : 'Stop',
              style: display(size: 16, weight: FontWeight.w700, color: confirmStop ? Colors.white : AppColors.text)),
          if (!confirmStop) ...[
            const SizedBox(width: 8),
            const Text('Esc', style: TextStyle(fontSize: 11, color: AppColors.muted)),
          ],
        ]),
      ),
    );
  }

  Widget _bottomBar(bool wide) {
    final canType = phase == _Phase.chatting;
    return Row(children: [
      _stopNewButton(),
      const SizedBox(width: 8),
      RoundIconButton(
        icon: Icons.flag_rounded,
        tooltip: 'Report this user',
        size: 48,
        onPressed: canType ? _report : null,
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: Row(children: [
            IconButton(
              tooltip: 'Emoji',
              onPressed: canType ? _openEmojis : null,
              icon: const Icon(Icons.emoji_emotions_outlined, size: 22),
              color: AppColors.muted,
            ),
            Expanded(
              child: TextField(
                controller: input,
                focusNode: inputFocus,
                enabled: canType,
                maxLength: 500,
                onChanged: _onChanged,
                onSubmitted: (_) => _send(),
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(
                  counterText: '',
                  border: InputBorder.none,
                  hintText: canType
                      ? 'Type a message...'
                      : (phase == _Phase.searching
                          ? 'Looking for someone...'
                          : 'Click New to chat with someone else'),
                  hintStyle: const TextStyle(color: AppColors.muted),
                ),
              ),
            ),
          ]),
        ),
      ),
      const SizedBox(width: 8),
      RoundIconButton(
        icon: Icons.send_rounded,
        tooltip: 'Send',
        size: 48,
        onPressed: canType ? _send : null,
      ),
    ]);
  }

  Widget _anyLanguageButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: () {
          _searchTimer?.cancel();
          setState(() {
            showAnyLang = false;
            lines
              ..clear()
              ..add(_Line(_Kind.system,
                  'Looking for someone you can chat with. Hold on...'));
          });
          svc.matchAnyLanguage();
        },
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: AppColors.lime.withOpacity(0.6)),
            boxShadow: [
              BoxShadow(
                  color: AppColors.lime.withOpacity(0.15), blurRadius: 24),
            ],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.translate_rounded, size: 18, color: AppColors.lime),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                  'Not many ${langByCode(widget.language).name} speakers online. Match with anyone',
                  style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.lime)),
            ),
          ]),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ page
  Widget _topBar() {
    return Row(children: [
      const OrbytLogo(size: 32),
      const SizedBox(width: 10),
      Text(appName,
          style: display(size: 22, weight: FontWeight.w700, letterSpacing: -0.6)),
      const SizedBox(width: 12),
      Pill(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.circle, size: 8, color: AppColors.green),
          const SizedBox(width: 6),
          Text('$online online',
              style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
        ]),
      ),
      const Spacer(),
      RoundIconButton(
        icon: Icons.close_rounded,
        tooltip: 'Back to home',
        danger: true,
        size: 40,
        onPressed: () => Navigator.of(context).pop(),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final wide = size.width > 860;

    Widget content;
    if (!widget.video) {
      content = Center(
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900), child: _chatLog()),
      );
    } else if (wide) {
      // Omegle layout: stranger on top, you below, chat on the right.
      content = Row(children: [
        SizedBox(
          width: (size.width * 0.36).clamp(320.0, 480.0),
          child: Column(children: [
            Expanded(child: _strangerTile()),
            const SizedBox(height: 10),
            Expanded(child: _youTile()),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(child: _chatLog()),
      ]);
    } else {
      content = Column(children: [
        SizedBox(
          height: (size.height * 0.27).clamp(130.0, 220.0),
          child: Row(children: [
            Expanded(child: _strangerTile()),
            const SizedBox(width: 8),
            Expanded(child: _youTile()),
          ]),
        ),
        const SizedBox(height: 8),
        Expanded(child: _chatLog()),
      ]);
    }

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _stopNew},
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: AppColors.bg,
          body: SafeArea(
            child: Padding(
              padding: EdgeInsets.all(wide ? 16 : 10),
              child: Column(children: [
                _topBar(),
                const SizedBox(height: 10),
                Expanded(
                  child: Stack(children: [
                    Positioned.fill(child: content),
                    if (showAnyLang && phase == _Phase.searching)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 12,
                        child: Center(child: _anyLanguageButton()),
                      )

                  ]),
                ),
                const SizedBox(height: 10),
                _bottomBar(wide),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
