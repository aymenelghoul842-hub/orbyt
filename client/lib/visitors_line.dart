import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'theme.dart';
import 'widgets.dart';

/// One small pill with just two numbers: visitors (today) and online now.
class VisitorsLine extends StatefulWidget {
  const VisitorsLine({super.key});
  @override
  State<VisitorsLine> createState() => _VisitorsLineState();
}

class _VisitorsLineState extends State<VisitorsLine> {
  int _today = -1, _online = 0;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _load();
    _t = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await http
          .get(Uri.parse('$kServerUrl/api/visits'))
          .timeout(const Duration(seconds: 5));
      if (r.statusCode != 200) return;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _today = ((j['today'] as Map)['visitors'] as num).toInt();
        _online = (j['online'] as num).toInt();
      });
    } catch (_) {
      // keep the last numbers
    }
  }

  static String _n(int v) {
    final s = v.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (_today < 0) return const SizedBox.shrink();
    const label = TextStyle(color: AppColors.muted, fontSize: 13);
    const bold = TextStyle(fontWeight: FontWeight.w800, fontSize: 14);
    return Pill(
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.circle, size: 9, color: AppColors.green),
        const SizedBox(width: 8),
        Text(_n(_online), style: bold),
        const SizedBox(width: 4),
        const Text('online', style: label),
        const SizedBox(width: 14),
        const Icon(Icons.groups_rounded, size: 16, color: AppColors.mint),
        const SizedBox(width: 6),
        Text(_n(_today), style: bold),
        const SizedBox(width: 4),
        const Text('visitors', style: label),
      ]),
    );
  }
}
