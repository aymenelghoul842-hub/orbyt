import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';
import 'widgets.dart';

/// Auto-playing, looping "trailer" shown on the home page.
///
/// It is drawn in code (no video file needed): you press Start, meet a stranger,
/// chat, press Stop -> Really? -> New and meet someone else who speaks another
/// language, then an outro card. Tap the player to pause / resume.
///
/// To use a real recorded video instead, see README ("Trailer").
class TrailerPreview extends StatefulWidget {
  const TrailerPreview({super.key});
  @override
  State<TrailerPreview> createState() => _TrailerPreviewState();
}

class _Person {
  const _Person({
    required this.name,
    required this.country,
    required this.badge,
    required this.langName,
    required this.hello,
    required this.reply,
    required this.second,
    required this.bg1,
    required this.bg2,
    required this.skin,
    required this.hair,
    required this.shirt,
    required this.style,
  });
  final String name, country, badge, langName, hello, reply, second;
  final Color bg1, bg2, skin, hair, shirt;
  final int style; // 0 short, 1 long, 2 bun, 3 cap
}

const _you = _Person(
  name: 'You',
  country: '',
  badge: '',
  langName: '',
  hello: '',
  reply: '',
  second: '',
  bg1: Color(0xFF123B3A),
  bg2: Color(0xFF0B1F2E),
  skin: Color(0xFFF1C7A0),
  hair: Color(0xFF2B1B12),
  shirt: Color(0xFF2F6BFF),
  style: 3,
);

const _people = <_Person>[
  _Person(
    name: 'Maria',
    country: 'Brazil',
    badge: 'PT',
    langName: 'Português',
    hello: 'Oi! Tudo bem? 👋',
    reply: 'Tudo ótimo! Where are you from?',
    second: 'Brasil! Vamos conversar 😄',
    bg1: Color(0xFF4A1D5C),
    bg2: Color(0xFF1E1033),
    skin: Color(0xFFB57A52),
    hair: Color(0xFF1A0F0A),
    shirt: Color(0xFFFF5FA8),
    style: 1,
  ),
  _Person(
    name: 'Yuki',
    country: 'Japan',
    badge: 'JA',
    langName: '日本語',
    hello: 'こんにちは! 🎌',
    reply: 'Hi Yuki! 👋',
    second: 'はじめまして! 😊',
    bg1: Color(0xFF0F3B5C),
    bg2: Color(0xFF0A1830),
    skin: Color(0xFFF3D2B3),
    hair: Color(0xFF111111),
    shirt: Color(0xFFEDEDED),
    style: 2,
  ),
  _Person(
    name: 'Karim',
    country: 'Tunisia',
    badge: 'AR',
    langName: 'العربية',
    hello: 'مرحبا! كيف حالك؟',
    reply: 'مرحبا كريم! 🙌',
    second: 'أهلا وسهلا 🇹🇳',
    bg1: Color(0xFF5C3A12),
    bg2: Color(0xFF2B1708),
    skin: Color(0xFFC98D5E),
    hair: Color(0xFF1B1109),
    shirt: Color(0xFF34D399),
    style: 0,
  ),
  _Person(
    name: 'Léa',
    country: 'France',
    badge: 'FR',
    langName: 'Français',
    hello: 'Salut ! Tu parles français ?',
    reply: 'Oui ! Salut Léa 😄',
    second: 'Super, on discute ? 🎉',
    bg1: Color(0xFF1F2D5C),
    bg2: Color(0xFF0E1230),
    skin: Color(0xFFF6D9C2),
    hair: Color(0xFFB5651D),
    shirt: Color(0xFF8B6CFF),
    style: 1,
  ),
];

class _TLine {
  const _TLine(this.kind, this.text);
  final int kind; // 0 system, 1 you, 2 stranger
  final String text;
}

class _TrailerPreviewState extends State<TrailerPreview>
    with SingleTickerProviderStateMixin {
  static const double _seg = 4.5; // seconds per stranger
  static const double _outro = 3.0;
  static const double _total = _seg * 4 + _outro; // 21 s

  late final AnimationController _ctrl;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (_total * 1000).round()),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _paused = !_paused);
    if (_paused) {
      _ctrl.stop();
    } else {
      _ctrl.repeat(); // continues from the current position
    }
  }

  String _clock(double s) {
    final v = s.floor().clamp(0, 99);
    return '0:${v.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: _toggle,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.14)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.lime.withOpacity(0.10),
                    blurRadius: 60,
                    spreadRadius: 2,
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: 640,
                    height: 360,
                    child: AnimatedBuilder(
                      animation: _ctrl,
                      builder: (_, __) => _scene(_ctrl.value * _total),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => Row(
            children: [
              Icon(
                _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                size: 18,
                color: AppColors.muted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _ctrl.value,
                    minHeight: 4,
                    backgroundColor: Colors.white.withOpacity(0.10),
                    valueColor: const AlwaysStoppedAnimation(AppColors.lime),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${_clock(_ctrl.value * _total)} / ${_clock(_total)}',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- scene
  Widget _scene(double t) {
    final inOutro = t >= _seg * 4;
    final segIndex = math.min(3, (t / _seg).floor());
    final local = inOutro ? _seg : t - segIndex * _seg;
    final p = _people[segIndex];
    final searching = !inOutro && local < 1.0;
    final connected = !inOutro && !searching;
    final reallyPhase = !inOutro && local >= 3.9;

    // ---- chat lines
    final lines = <_TLine>[];
    if (searching) {
      lines.add(
        const _TLine(0, 'Looking for someone you can chat with. Hold on...'),
      );
    } else {
      lines.add(
        _TLine(
          0,
          'You\'re now chatting with a random stranger from ${p.country}. Say hi!',
        ),
      );
      lines.add(_TLine(0, 'Language: ${p.langName}'));
      if (local >= 1.8) lines.add(_TLine(2, p.hello));
      if (local >= 2.9) lines.add(_TLine(1, p.reply));
      if (local >= 3.7) lines.add(_TLine(2, p.second));
    }
    final typing =
        connected &&
        ((local >= 1.0 && local < 1.8) || (local >= 3.0 && local < 3.7));
    final strangerTalking =
        connected &&
        ((local >= 1.8 && local < 2.7) || (local >= 3.7 && local < 4.5));
    final youTalking = connected && local >= 2.9 && local < 3.6;

    final flash = (!inOutro && local < 0.28 && segIndex > 0)
        ? (1 - local / 0.28) * 0.45
        : 0.0;

    double outroOpacity = 0;
    if (inOutro) {
      final o = t - _seg * 4;
      outroOpacity = math.min(1.0, o / 0.5);
      if (o > _outro - 0.5) outroOpacity = math.max(0.0, (_outro - o) / 0.5);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: AppColors.bg),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              _topBar(),
              const SizedBox(height: 6),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: 220,
                      child: Column(
                        children: [
                          Expanded(
                            child: _strangerTile(
                              p,
                              t,
                              searching,
                              connected,
                              strangerTalking,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(child: _youTile(t, youTalking)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: _chatLog(lines, typing, p)),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              _bottomBar(reallyPhase, connected),
            ],
          ),
        ),
        if (flash > 0)
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(color: Colors.white.withOpacity(flash)),
            ),
          ),
        // "TRAILER" badge
        Positioned(
          left: 14,
          top: 44,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.circle,
                    size: 8,
                    color: (t * 2).floor().isEven
                        ? const Color(0xFFFF5A5F)
                        : const Color(0xFF8A2A2D),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'TRAILER',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (outroOpacity > 0)
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(opacity: outroOpacity, child: _outroCard()),
            ),
          ),
        if (_paused)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: Colors.black.withOpacity(0.35),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.play_circle_fill_rounded,
                  size: 76,
                  color: Colors.white70,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _topBar() => SizedBox(
    height: 26,
    child: Row(
      children: [
        const OrbytLogo(size: 22),
        const SizedBox(width: 8),
        Text(
          appName,
          style: display(
            size: 15,
            weight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(width: 10),
        Pill(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.circle, size: 6, color: AppColors.green),
              SizedBox(width: 5),
              Text(
                'Live demo',
                style: TextStyle(fontSize: 10, color: AppColors.muted),
              ),
            ],
          ),
        ),
        const Spacer(),
        const Icon(Icons.close_rounded, size: 16, color: Color(0xFFEF4444)),
      ],
    ),
  );

  Widget _tile({required Widget child}) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.black,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withOpacity(0.12)),
    ),
    child: child,
  );

  Widget _strangerTile(
    _Person p,
    double t,
    bool searching,
    bool connected,
    bool talking,
  ) {
    return _tile(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (connected)
            CustomPaint(painter: _PersonPainter(p, t, talking))
          else
            Container(
              color: AppColors.bg,
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  AnimatedOrbit(size: 44),
                  SizedBox(height: 8),
                  Text(
                    'Looking for someone...',
                    style: TextStyle(fontSize: 10, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          if (connected)
            Positioned(
              left: 6,
              bottom: 6,
              child: Pill(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.public_rounded,
                      size: 10,
                      color: AppColors.mint,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Stranger · ${p.country} · ${p.badge}',
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _youTile(double t, bool talking) {
    return _tile(
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _PersonPainter(_you, t + 3.1, talking)),
          Positioned(
            right: 6,
            bottom: 6,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _miniBtn(Icons.mic_rounded),
                const SizedBox(width: 4),
                _miniBtn(Icons.videocam_rounded),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniBtn(IconData i) => Container(
    width: 22,
    height: 22,
    decoration: BoxDecoration(
      color: Colors.black.withOpacity(0.5),
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white24),
    ),
    child: Icon(i, size: 12, color: Colors.white),
  );

  Widget _chatLog(List<_TLine> lines, bool typing, _Person p) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final l in lines) _lineView(l),
            if (typing)
              const Padding(
                padding: EdgeInsets.only(top: 3),
                child: Text(
                  'Stranger is typing...',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontStyle: FontStyle.italic,
                    color: AppColors.muted,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _lineView(_TLine l) {
    if (l.kind == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          l.text,
          style: const TextStyle(
            fontSize: 11,
            height: 1.35,
            fontWeight: FontWeight.w600,
            color: Color(0xFFC9CBE0),
          ),
        ),
      );
    }
    final you = l.kind == 1;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: you ? 'You: ' : 'Stranger: ',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: you ? const Color(0xFF4DA3FF) : const Color(0xFFFF5A5F),
              ),
            ),
            TextSpan(text: l.text),
          ],
        ),
        style: const TextStyle(fontSize: 12, height: 1.35),
      ),
    );
  }

  Widget _bottomBar(bool really, bool connected) {
    return SizedBox(
      height: 30,
      child: Row(
        children: [
          Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: really ? const Color(0xFFEF4444) : Colors.transparent,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: really ? const Color(0xFFEF4444) : Colors.white24,
              ),
            ),
            child: Text(
              really ? 'Really?' : 'Stop',
              style: display(
                size: 12,
                weight: FontWeight.w700,
                color: really ? Colors.white : AppColors.text,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.07),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.flag_rounded,
              size: 14,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
              ),
              child: Text(
                connected ? 'Type a message...' : 'Looking for someone...',
                style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _outroCard() {
    const badges = ['EN', 'FR', 'AR', 'ES', 'PT', 'DE', 'JA', 'ZH'];
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.2),
          radius: 1.1,
          colors: [Color(0xFF1B1840), AppColors.bg],
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const OrbytLogo(size: 54),
          const SizedBox(height: 14),
          Text(
            'Meet someone',
            style: display(size: 34, height: 1.0, letterSpacing: -1.2),
          ),
          ShaderMask(
            shaderCallback: (r) => AppColors.cta.createShader(r),
            child: Text(
              'new. Instantly.',
              style: display(
                size: 34,
                height: 1.05,
                letterSpacing: -1.2,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Video & text chat · Pick your language · No sign-up',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              for (final b in badges)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.14)),
                  ),
                  child: Text(
                    b,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Flat-style webcam "person": gradient room, shoulders, head, hair, blinking
/// eyes and a mouth that moves while they talk.
class _PersonPainter extends CustomPainter {
  _PersonPainter(this.p, this.t, this.talking);
  final _Person p;
  final double t;
  final bool talking;

  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    final rect = Offset.zero & s;

    // room
    c.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [p.bg1, p.bg2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(rect),
    );
    c.drawCircle(
      Offset(w * 0.82, h * 0.18),
      h * 0.32,
      Paint()..color = Colors.white.withOpacity(0.06),
    );
    c.drawCircle(
      Offset(w * 0.12, h * 0.9),
      h * 0.28,
      Paint()..color = Colors.white.withOpacity(0.04),
    );

    final bob = math.sin(t * 2.2) * h * 0.006;
    final cx = w / 2 + math.sin(t * 0.9) * w * 0.012;
    final headR = h * 0.19;
    final headCy = h * 0.43 + bob;

    // shoulders
    final body = Path()
      ..moveTo(cx - w * 0.36, h + 2)
      ..quadraticBezierTo(
        cx - w * 0.36,
        h * 0.74 + bob,
        cx - w * 0.13,
        h * 0.70 + bob,
      )
      ..lineTo(cx + w * 0.13, h * 0.70 + bob)
      ..quadraticBezierTo(cx + w * 0.36, h * 0.74 + bob, cx + w * 0.36, h + 2)
      ..close();
    c.drawPath(body, Paint()..color = p.shirt);

    // neck
    final neckColor = Color.lerp(p.skin, Colors.black, 0.14)!;
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx, headCy + headR * 1.0),
          width: headR * 0.72,
          height: headR * 1.0,
        ),
        Radius.circular(headR * 0.2),
      ),
      Paint()..color = neckColor,
    );

    final hairPaint = Paint()..color = p.hair;

    // hair behind the head
    if (p.style == 1) {
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(cx, headCy + headR * 0.55),
            width: headR * 2.35,
            height: headR * 2.7,
          ),
          Radius.circular(headR * 1.1),
        ),
        hairPaint,
      );
    }
    if (p.style == 2) {
      c.drawCircle(Offset(cx, headCy - headR * 1.12), headR * 0.4, hairPaint);
    }

    // head
    c.drawCircle(Offset(cx, headCy), headR, Paint()..color = p.skin);

    // hair on top
    final topRect = Rect.fromCircle(
      center: Offset(cx, headCy),
      radius: headR * 1.05,
    );
    if (p.style == 3) {
      c.drawArc(
        topRect,
        math.pi,
        math.pi,
        true,
        Paint()..color = AppColors.lime,
      );
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            cx - headR * 0.2,
            headCy - headR * 0.18,
            headR * 1.3,
            headR * 0.16,
          ),
          Radius.circular(headR * 0.08),
        ),
        Paint()..color = const Color(0xFF9BD12F),
      );
    } else {
      c.drawArc(topRect, math.pi, math.pi, true, hairPaint);
      // fringe (clipped to the head so no corners stick out)
      final fringe = Path()
        ..moveTo(cx - headR * 1.05, headCy - headR * 0.05)
        ..quadraticBezierTo(
          cx - headR * 0.2,
          headCy - headR * 0.75,
          cx + headR * 1.05,
          headCy - headR * 0.25,
        )
        ..lineTo(cx + headR * 1.05, headCy - headR * 1.2)
        ..lineTo(cx - headR * 1.05, headCy - headR * 1.2)
        ..close();
      c.save();
      c.clipPath(Path()..addOval(topRect));
      c.drawPath(fringe, hairPaint);
      c.restore();
    }

    // cheeks
    final blush = Paint()..color = const Color(0xFFFF7A9A).withOpacity(0.22);
    c.drawCircle(
      Offset(cx - headR * 0.58, headCy + headR * 0.32),
      headR * 0.16,
      blush,
    );
    c.drawCircle(
      Offset(cx + headR * 0.58, headCy + headR * 0.32),
      headR * 0.16,
      blush,
    );

    // eyes (blink every few seconds)
    final blinkPhase = (t * 0.8) % 3.7;
    final open = blinkPhase < 0.12 ? 0.15 : 1.0;
    final eye = Paint()..color = const Color(0xFF1A1414);
    for (final dx in [-0.38, 0.38]) {
      c.drawOval(
        Rect.fromCenter(
          center: Offset(cx + headR * dx, headCy + headR * 0.02),
          width: headR * 0.17,
          height: headR * 0.2 * open,
        ),
        eye,
      );
    }

    // mouth
    final mouthC = Offset(cx, headCy + headR * 0.52);
    if (talking) {
      final m = (math.sin(t * 14) + 1) / 2; // 0..1
      c.drawOval(
        Rect.fromCenter(
          center: mouthC,
          width: headR * 0.46,
          height: headR * (0.10 + 0.26 * m),
        ),
        Paint()..color = const Color(0xFF7A2630),
      );
    } else {
      final smile = Path()
        ..moveTo(mouthC.dx - headR * 0.24, mouthC.dy - headR * 0.04)
        ..quadraticBezierTo(
          mouthC.dx,
          mouthC.dy + headR * 0.2,
          mouthC.dx + headR * 0.24,
          mouthC.dy - headR * 0.04,
        );
      c.drawPath(
        smile,
        Paint()
          ..color = const Color(0xFF7A2630)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.6, headR * 0.05)
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PersonPainter old) =>
      old.t != t || old.talking != talking || old.p != p;
}
