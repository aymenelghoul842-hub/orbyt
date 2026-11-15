import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config.dart';
import '../languages.dart';
import '../profile.dart';
import '../support.dart';
import '../theme.dart';
import '../trailer.dart';
import 'live_screen.dart';
import '../visitors_line.dart';
import '../widgets.dart';
import 'chat_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool agreed = true; // pressing Start = accepting (notice shown under the cards)
  final _interestsCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _useName = false; // false = Anonymous
  final _tags = <String>[];
  String _lang = deviceLanguageCode(); // language you want to speak; 'any' = everyone

  late final TapGestureRecognizer _termsTap = TapGestureRecognizer()
    ..onTap = () => _open('terms');
  late final TapGestureRecognizer _privacyTap = TapGestureRecognizer()
    ..onTap = () => _open('privacy');
  late final TapGestureRecognizer _safetyTap = TapGestureRecognizer()
    ..onTap = () => _open('safety');

  @override
  void initState() {
    super.initState();
    // the username from the welcome screen is already filled in
    if (Profile.username.length >= 2) {
      _nameCtrl.text = Profile.username;
      _useName = true;
    }
  }

  @override
  void dispose() {
    _interestsCtrl.dispose();
    _nameCtrl.dispose();
    _termsTap.dispose();
    _privacyTap.dispose();
    _safetyTap.dispose();
    super.dispose();
  }

  Widget _identityCard() {
    Widget chip(String label, IconData icon, bool selected, VoidCallback onTap) =>
        ChoiceChip(
          avatar: Icon(icon,
              size: 18, color: selected ? AppColors.lime : AppColors.muted),
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
          showCheckmark: false,
          selectedColor: AppColors.lime.withOpacity(0.14),
          backgroundColor: Colors.white.withOpacity(0.06),
          side: BorderSide(
              color: selected
                  ? AppColors.lime.withOpacity(0.5)
                  : Colors.white.withOpacity(0.12)),
          shape: const StadiumBorder(),
          labelStyle: TextStyle(
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.lime : AppColors.text),
        );

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      radius: 22,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: const [
            Icon(Icons.badge_rounded, color: AppColors.mint, size: 20),
            SizedBox(width: 10),
            Text('How do you want to appear?',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 4, children: [
            chip('Anonymous', Icons.visibility_off_rounded, !_useName,
                () => setState(() => _useName = false)),
            chip('Use a username', Icons.person_rounded, _useName,
                () => setState(() => _useName = true)),
          ]),
          if (_useName)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: TextField(
                controller: _nameCtrl,
                maxLength: 20,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'[\p{L}\p{N} _.\-]', unicode: true)),
                ],
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'Username (2-20 letters, numbers, _ . -)',
                  hintStyle: const TextStyle(color: AppColors.muted),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 10),
          const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.public_rounded, size: 15, color: AppColors.muted),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Your country is shown to the person you meet. Never your IP.',
                style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.muted),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _openSupport() => showSupportSheet(context);

  /// Name shown on Live (null = Anonymous), same choice as in random chat.
  String? get _liveName {
    final n = _nameCtrl.text.trim();
    return _useName && n.length >= 2 ? n : null;
  }

  Future<void> _pickLanguage() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _LanguageSheet(selected: _lang),
    );
    if (picked != null && mounted) setState(() => _lang = picked);
  }

  Widget _languageCard() {
    final l = langByCode(_lang);
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      radius: 22,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.translate_rounded, color: AppColors.mint, size: 20),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Language you speak',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _pickLanguage,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.lime,
                side: BorderSide(color: AppColors.lime.withOpacity(0.5)),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(l.badge,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                Text(l.native,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const Icon(Icons.arrow_drop_down_rounded, size: 22),
              ]),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            _lang == kAnyLang
                ? 'You will meet people who speak any language.'
                : 'You will only meet people who also speak ${l.name}.',
            style: const TextStyle(
                fontSize: 12.5, height: 1.4, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Future<void> _share() async {
    await Clipboard.setData(ClipboardData(text: '$kShareText\n$kServerUrl'));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Link + description copied. Paste it anywhere to share!'),
    ));
  }

  Future<void> _open(String page) async {
    await launchUrl(Uri.parse('$kServerUrl/$page'),
        mode: LaunchMode.externalApplication);
  }

  void _addTags(String raw) {
    for (final part in raw.split(',')) {
      var t = part.trim().toLowerCase();
      if (t.isEmpty || _tags.length >= 5 || _tags.contains(t)) continue;
      if (t.length > 24) t = t.substring(0, 24);
      _tags.add(t);
    }
  }

  void _start(bool video) {
    if (!agreed) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please confirm you are 18+ and accept the rules first.'),
      ));
      return;
    }
    final name = _nameCtrl.text.trim();
    if (_useName && name.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Pick a username with at least 2 characters, or choose Anonymous.'),
      ));
      return;
    }
    if (_interestsCtrl.text.trim().isNotEmpty) {
      setState(() {
        _addTags(_interestsCtrl.text);
        _interestsCtrl.clear();
      });
    }
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, __, ___) =>
            ChatScreen(
                video: video,
                interests: List<String>.of(_tags),
                language: _lang,
                username: _useName ? name : null),
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width > 860;
    final headline = wide ? 52.0 : 30.0;

    final cards = [
      _ModeCard(
        icon: Icons.videocam_rounded,
        title: 'Video chat',
        text: wide ? 'Face to face with someone new.' : null,
        button: 'Start video',
        glow: AppColors.lime,
        onTap: () => _start(true),
      ),
      _ModeCard(
        icon: Icons.chat_bubble_rounded,
        title: 'Text chat',
        text: wide ? 'No camera needed.' : null,
        button: 'Start texting',
        glow: AppColors.violet,
        onTap: () => _start(false),
      ),
    ];

    Widget nav() => Row(children: [
          OrbytLogo(size: wide ? 36 : 30),
          const SizedBox(width: 10),
          Text(appName,
              style: display(
                  size: wide ? 24 : 21,
                  weight: FontWeight.w700,
                  letterSpacing: -0.8)),
          const Spacer(),
          // Live button hidden for now (the live code is still in the project).
          IconButton(
            tooltip: 'Buy me a coffee',
            onPressed: _openSupport,
            icon: const Icon(Icons.coffee_rounded, size: 20, color: kCoffee),
          ),
          IconButton(
            tooltip: 'Share Orbyt',
            onPressed: _share,
            icon: const Icon(Icons.share_rounded,
                size: 20, color: AppColors.mint),
          ),
          const Pill(
            child: Text('18+ only',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ]);

    Widget title() => Column(children: [
          Text('Meet someone',
              textAlign: TextAlign.center,
              style: display(
                  size: headline,
                  weight: FontWeight.w700,
                  height: 1.02,
                  letterSpacing: -headline * 0.035)),
          ShaderMask(
            shaderCallback: (r) => AppColors.cta.createShader(r),
            child: Text('new. Instantly.',
                textAlign: TextAlign.center,
                style: display(
                    size: headline,
                    weight: FontWeight.w700,
                    height: 1.02,
                    letterSpacing: -headline * 0.035,
                    color: Colors.white)),
          ),
        ]);

    const subtitle = Text(
      'Orbyt connects you with people from around the world. '
      'No sign-up. No profile. Just a conversation.',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 15, height: 1.4, color: AppColors.muted),
    );

    Widget interests() => GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          radius: 22,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.favorite_rounded,
                    color: AppColors.pink, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _interestsCtrl,
                    enabled: _tags.length < 5,
                    onChanged: (v) {
                      if (v.contains(',')) {
                        setState(() {
                          _addTags(v);
                          _interestsCtrl.clear();
                        });
                      }
                    },
                    onSubmitted: (v) => setState(() {
                      _addTags(v);
                      _interestsCtrl.clear();
                    }),
                    decoration: InputDecoration(
                      hintText: _tags.length >= 5
                          ? 'Max 5 interests'
                          : 'Interests (optional): type one, press Enter',
                      border: InputBorder.none,
                      hintStyle: const TextStyle(color: AppColors.muted),
                    ),
                  ),
                ),
              ]),
              if (_tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(spacing: 8, runSpacing: 6, children: [
                    for (final t in _tags)
                      InputChip(
                        label: Text(t),
                        onDeleted: () => setState(() => _tags.remove(t)),
                        backgroundColor: Colors.white.withOpacity(0.07),
                        side: const BorderSide(color: Colors.white12),
                        shape: const StadiumBorder(),
                      ),
                  ]),
                ),
            ],
          ),
        );

    Widget consent() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text.rich(
            TextSpan(
              style: const TextStyle(
                  fontSize: 12, height: 1.4, color: AppColors.muted),
              children: [
                const TextSpan(
                    text:
                        'By pressing Start you confirm you are 18+, your country is shown to people you chat with, and you accept the '),
                _link('Terms', _termsTap),
                const TextSpan(text: ', '),
                _link('Privacy', _privacyTap),
                const TextSpan(text: ' and rules. '),
                _link('Safety tips', _safetyTap),
                const TextSpan(text: '.'),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        );

    final footer = Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('© Orbyt · Be kind. Be safe.  ',
            style: TextStyle(color: AppColors.muted, fontSize: 12)),
        _FooterLink('Terms', () => _open('terms')),
        _FooterLink('Privacy', () => _open('privacy')),
        _FooterLink('Safety', () => _open('safety')),
      ],
    );

    // Everything on ONE screen: the left column is the pitch, the right
    // column is the controls. On phones it is a single compact column.
    final Widget body = wide
        ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const VisitorsLine(),
                  const SizedBox(height: 18),
                  title(),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: subtitle),
                  const SizedBox(height: 20),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: const TrailerPreview(),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 32),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: 14),
                      Expanded(child: cards[1]),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _languageCard(),
                  const SizedBox(height: 12),
                  _identityCard(),
                  const SizedBox(height: 12),
                  interests(),
                  const SizedBox(height: 12),
                  consent(),
                ],
              ),
            ),
          ])
        : Column(mainAxisSize: MainAxisSize.min, children: [
            const VisitorsLine(),
            const SizedBox(height: 10),
            title(),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: cards[0]),
                const SizedBox(width: 10),
                Expanded(child: cards[1]),
              ],
            ),
            const SizedBox(height: 10),
            _languageCard(),
            const SizedBox(height: 10),
            _identityCard(),
            const SizedBox(height: 10),
            interests(),
            const SizedBox(height: 10),
            consent(),
          ]);

    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth < 1180 ? c.maxWidth : 1180.0;
            final pad = wide ? 28.0 : 14.0;
            return Center(
              // FittedBox shrinks everything to fit the window: no scrollbar,
              // whatever the screen size.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: w,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(pad, 8, pad, 8),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      nav(),
                      SizedBox(height: wide ? 14 : 8),
                      body,
                      SizedBox(height: wide ? 10 : 6),
                      footer,
                    ]),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  TextSpan _link(String text, TapGestureRecognizer rec) => TextSpan(
        text: text,
        recognizer: rec,
        style: const TextStyle(
            color: AppColors.mint, decoration: TextDecoration.underline),
      );
}

class _FooterLink extends StatelessWidget {
  const _FooterLink(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
            minimumSize: const Size(0, 28),
            padding: const EdgeInsets.symmetric(horizontal: 8)),
        child: Text(label,
            style: const TextStyle(color: AppColors.mint, fontSize: 12)),
      );
}

class _ModeCard extends StatefulWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.text,
    required this.button,
    required this.onTap,
    required this.glow,
  });
  final IconData icon;
  final String title, button;
  final String? text;
  final VoidCallback onTap;
  final Color glow;
  @override
  State<_ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends State<_ModeCard> {
  bool hover = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: AnimatedScale(
        scale: hover ? 1.02 : 1,
        duration: const Duration(milliseconds: 200),
        child: GlassCard(
          padding: const EdgeInsets.all(16),
          glow: hover ? widget.glow : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: widget.glow == AppColors.lime
                      ? AppColors.cta
                      : AppColors.gradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(widget.icon,
                    color: widget.glow == AppColors.lime
                        ? AppColors.onCta
                        : Colors.white,
                    size: 24),
              ),
              const SizedBox(height: 10),
              Text(widget.title,
                  style: display(size: 21, weight: FontWeight.w700)),
              if (widget.text != null) ...[
                const SizedBox(height: 4),
                Text(widget.text!,
                    style: const TextStyle(
                        fontSize: 13.5, height: 1.4, color: AppColors.muted)),
              ],
              const SizedBox(height: 12),
              GradientButton(
                  height: 44,
                  label: widget.button,
                  icon: Icons.arrow_forward_rounded,
                  onPressed: widget.onTap),
            ],
          ),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature(this.icon, this.title, this.sub);
  final IconData icon;
  final String title, sub;
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: AppColors.mint, size: 22),
      ),
      const SizedBox(width: 12),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        Text(sub, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
      ]),
    ]);
  }
}


/// Bottom sheet with a searchable list of languages.
class _LanguageSheet extends StatefulWidget {
  const _LanguageSheet({required this.selected});
  final String selected;
  @override
  State<_LanguageSheet> createState() => _LanguageSheetState();
}

class _LanguageSheetState extends State<_LanguageSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final query = _q.trim().toLowerCase();
    final items = kLanguages
        .where((l) =>
            query.isEmpty ||
            l.name.toLowerCase().contains(query) ||
            l.native.toLowerCase().contains(query) ||
            l.code == query)
        .toList();
    final h = MediaQuery.of(context).size.height;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 560, maxHeight: h * 0.78),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                child: Row(children: [
                  Text('Choose your language', style: display(size: 20)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  onChanged: (v) => setState(() => _q = v),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: 'Search a language',
                    hintStyle: const TextStyle(color: AppColors.muted),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final l = items[i];
                    final sel = l.code == widget.selected;
                    return ListTile(
                      leading: Container(
                        width: 44,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: sel
                              ? AppColors.lime.withOpacity(0.14)
                              : Colors.white.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(l.badge,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: sel ? AppColors.lime : AppColors.text)),
                      ),
                      title: Text(l.native,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(l.name,
                          style: const TextStyle(color: AppColors.muted)),
                      trailing: sel
                          ? const Icon(Icons.check_circle_rounded,
                              color: AppColors.lime)
                          : null,
                      onTap: () => Navigator.pop(context, l.code),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ]),
          ),
        ),
      ),
    );
  }
}
