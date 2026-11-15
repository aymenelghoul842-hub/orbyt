import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'config.dart';
import 'theme.dart';

/// Warm "coffee" accent used by the support button.
const Color kCoffee = Color(0xFFFFC857);

/// "Buy me a coffee": the visitor writes an amount, picks a payment method,
/// and pays either on the payment provider's own secure page (card / e-DINAR)
/// or by transfer to the owner's postal / bank account.
///
/// IMPORTANT: card numbers are never typed into this app and never reach our
/// server. The card page belongs to the payment provider (see server/index.js).
Future<void> showSupportSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _SupportSheet(),
  );
}

class _DonateConfig {
  const _DonateConfig({
    required this.currency,
    required this.min,
    required this.max,
    required this.presets,
    required this.card,
    required this.test,
    required this.transfer,
  });
  final String currency;
  final double min, max;
  final List<double> presets;
  final bool card, test;
  final Map<String, String> transfer;

  bool get anyMethod => card || transfer.isNotEmpty;

  factory _DonateConfig.fromJson(Map<String, dynamic> j) {
    final transfer = <String, String>{};
    final t = j['transfer'];
    if (t is Map) {
      t.forEach((k, v) {
        final s = v?.toString() ?? '';
        if (s.isNotEmpty) transfer[k.toString()] = s;
      });
    }
    return _DonateConfig(
      currency: j['currency']?.toString() ?? 'TND',
      min: (j['min'] as num?)?.toDouble() ?? 1,
      max: (j['max'] as num?)?.toDouble() ?? 500,
      presets: ((j['presets'] as List?) ?? const [2, 5, 10, 20])
          .map((e) => (e as num).toDouble())
          .toList(),
      card: j['card'] == true,
      test: j['test'] == true,
      transfer: transfer,
    );
  }
}

enum _Step { amount, method, transfer }

class _SupportSheet extends StatefulWidget {
  const _SupportSheet();
  @override
  State<_SupportSheet> createState() => _SupportSheetState();
}

class _SupportSheetState extends State<_SupportSheet> {
  _DonateConfig? _cfg;
  bool _loadFailed = false;
  _Step _step = _Step.amount;
  final _amountCtrl = TextEditingController(text: '5');
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await http
          .get(Uri.parse('$kServerUrl/api/donate'))
          .timeout(const Duration(seconds: 6));
      if (r.statusCode == 200) {
        final cfg = _DonateConfig.fromJson(
          jsonDecode(r.body) as Map<String, dynamic>,
        );
        if (mounted) setState(() => _cfg = cfg);
        return;
      }
    } catch (_) {
      // fall through
    }
    if (mounted) setState(() => _loadFailed = true);
  }

  double? get _amount =>
      double.tryParse(_amountCtrl.text.trim().replaceAll(',', '.'));

  String? get _amountError {
    final cfg = _cfg;
    final a = _amount;
    if (cfg == null) return null;
    if (a == null) return 'Write an amount';
    if (a < cfg.min) return 'Minimum is ${_fmt(cfg.min)} ${cfg.currency}';
    if (a > cfg.max) return 'Maximum is ${_fmt(cfg.max)} ${cfg.currency}';
    return null;
  }

  String _fmt(double a) {
    if (a == a.roundToDouble()) return a.toInt().toString();
    return a.toStringAsFixed(2);
  }

  Future<void> _payByCard() async {
    final a = _amount;
    if (a == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await http
          .post(
            Uri.parse('$kServerUrl/api/donate/checkout'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'amount': a}),
          )
          .timeout(const Duration(seconds: 15));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final url = j['payUrl'];
      if (r.statusCode == 200 && url is String) {
        // Same tab on the web (a new tab opened after a network call is blocked by many browsers).
        await launchUrl(Uri.parse(url), webOnlyWindowName: '_self');
        return;
      }
      if (mounted) {
        setState(
          () => _error = 'The payment page could not be opened. Please try again in a moment.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not reach the payment page. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$label copied')));
  }

  // ------------------------------------------------------------------ UI
  Widget _title(String text, {bool back = false}) {
    return Row(
      children: [
        if (back)
          IconButton(
            onPressed: () => setState(() {
              _error = null;
              _step = _step == _Step.transfer ? _Step.method : _Step.amount;
            }),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        Expanded(child: Text(text, style: display(size: 22))),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }

  Widget _amountStep(_DonateConfig cfg) {
    final err = _amountError;
    final a = _amount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Buy me a coffee \u2615'),
        const SizedBox(height: 4),
        const Text(
          'Orbyt is free. If you enjoy it, you can send me a small gift. '
          'It is completely optional.',
          style: TextStyle(fontSize: 14, height: 1.45, color: AppColors.muted),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            for (final p in cfg.presets)
              ChoiceChip(
                label: Text('${_fmt(p)} ${cfg.currency}'),
                selected: a == p,
                showCheckmark: false,
                onSelected: (_) => setState(() => _amountCtrl.text = _fmt(p)),
                selectedColor: kCoffee.withOpacity(0.18),
                backgroundColor: Colors.white.withOpacity(0.06),
                side: BorderSide(
                  color: a == p ? kCoffee.withOpacity(0.6) : Colors.white12,
                ),
                shape: const StadiumBorder(),
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: a == p ? kCoffee : AppColors.text,
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            LengthLimitingTextInputFormatter(6),
          ],
          onChanged: (_) => setState(() {}),
          style: display(size: 22),
          decoration: InputDecoration(
            labelText: 'Amount you want to send',
            suffixText: cfg.currency,
            errorText: err,
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton(
            onPressed: (err == null && a != null)
                ? () => setState(() => _step = _Step.method)
                : null,
            style: FilledButton.styleFrom(
              backgroundColor: kCoffee,
              foregroundColor: AppColors.onCta,
              shape: const StadiumBorder(),
            ),
            child: const Text(
              'Continue',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _methodTile({
    required IconData icon,
    required String title,
    required String text,
    required VoidCallback? onTap,
    bool loading = false,
  }) {
    return Material(
      color: Colors.white.withOpacity(0.05),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: kCoffee.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: kCoffee),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      text,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.muted,
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _methodStep(_DonateConfig cfg) {
    final a = _amount ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('How do you want to pay?', back: true),
        const SizedBox(height: 2),
        Text(
          'Gift: ${_fmt(a)} ${cfg.currency}',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: kCoffee,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 14),
        if (cfg.card) ...[
          _methodTile(
            icon: Icons.credit_card_rounded,
            title: 'Bank card or e-DINAR',
            text:
                'You will be taken to the payment provider\'s secure page to '
                'enter your card details there. Your card details are never '
                'typed in, or stored by, Orbyt.',
            loading: _busy,
            onTap: _busy ? null : _payByCard,
          ),
          const SizedBox(height: 10),
        ],
        if (cfg.transfer.isNotEmpty) ...[
          _methodTile(
            icon: Icons.account_balance_rounded,
            title: 'La Poste Tunisienne / bank transfer',
            text:
                'Send it from your own postal (CCP), bank or mobile-wallet '
                'account. I will show you where to send it.',
            onTap: () => setState(() => _step = _Step.transfer),
          ),
          const SizedBox(height: 10),
        ],
        if (cfg.test && cfg.card)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Test mode: no real money is charged yet.',
              style: TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _error!,
              style: const TextStyle(color: Color(0xFFFF7A7A), fontSize: 13.5),
            ),
          ),
      ],
    );
  }

  Widget _transferStep(_DonateConfig cfg) {
    final a = _amount ?? 0;
    const labels = <String, String>{
      'name': 'Account holder',
      'ccp': 'CCP',
      'rib': 'RIB',
      'phone': 'Mobile number',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Send your gift', back: true),
        const SizedBox(height: 4),
        Text(
          'Send ${_fmt(a)} ${cfg.currency} from your La Poste Tunisienne, bank '
          'or mobile-wallet account to:',
          style: const TextStyle(
            fontSize: 14,
            height: 1.45,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(height: 14),
        for (final key in labels.keys)
          if (cfg.transfer.containsKey(key))
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          labels[key]!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        SelectableText(
                          cfg.transfer[key]!,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy',
                    onPressed: () => _copy(labels[key]!, cfg.transfer[key]!),
                    icon: const Icon(Icons.copy_rounded, size: 20),
                  ),
                ],
              ),
            ),
        const SizedBox(height: 6),
        const Text(
          'Gifts are voluntary and not refundable. Thank you, it really helps! \u2615',
          style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.muted),
        ),
      ],
    );
  }

  Widget _message(String text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Buy me a coffee \u2615'),
        const SizedBox(height: 8),
        Text(
          text,
          style: const TextStyle(
            fontSize: 14.5,
            height: 1.5,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _cfg;
    Widget body;
    if (_loadFailed) {
      body = _message(
        'Could not load the gift options right now. Please try again later.',
      );
    } else if (cfg == null) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (!cfg.anyMethod) {
      body = _message('Gifts are not set up yet. Please come back soon!');
    } else {
      switch (_step) {
        case _Step.amount:
          body = _amountStep(cfg);
          break;
        case _Step.method:
          body = _methodStep(cfg);
          break;
        case _Step.transfer:
          body = _transferStep(cfg);
          break;
      }
    }
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}
