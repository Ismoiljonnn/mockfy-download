// The level check, as on the website's /start: say roughly where you are (or let the questions decide),
// then about a dozen questions that get harder or easier as you answer. Daily English follows the result.
import 'package:flutter/material.dart';

import '../i18n.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

class PlacementScreen extends StatefulWidget {
  const PlacementScreen({super.key, this.api = '/api/start/placement'});
  final String api;
  @override
  State<PlacementScreen> createState() => _PlacementScreenState();
}

class _PlacementScreenState extends State<PlacementScreen> {
  Map<String, dynamic>? _st;
  bool _chooseSelf = true;
  bool _busy = false;
  String? _error;
  Object? _picked;
  final _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  Future<void> _get({String? self, bool restart = false}) async {
    setState(() { _busy = true; _error = null; });
    try {
      final r = await Api.I.get(widget.api, {if (restart) 'restart': '1', if (self != null) 'self': self});
      setState(() { _st = r; _chooseSelf = false; _picked = null; _typed.clear(); });
    } on ApiError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _answer() async {
    final q = (_st!['question'] as Map);
    final given = q['type'] == 'type' ? _typed.text.trim() : _picked;
    setState(() => _busy = true);
    try {
      final r = await Api.I.post(widget.api, {'answer': given});
      if (r['done'] == true) {
        setState(() => _st = r);
      } else {
        await _get();
      }
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    Widget body;
    if (_error != null) {
      body = ErrorView(message: _error!, onRetry: () => _get());
    } else if (_chooseSelf) {
      body = ListView(padding: const EdgeInsets.all(20), children: [
        Text(tr('Where are you now?'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(tr('Pick the IELTS band you think you have. The questions start there and adjust as you answer.'), style: TextStyle(color: hint)),
        const SizedBox(height: 18),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final b in ['4.0', '4.5', '5.0', '5.5', '6.0', '6.5', '7.0', '7.5', '8.0'])
            ActionChip(label: Text(b, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)), onPressed: _busy ? null : () => _get(self: b, restart: true)),
        ]),
        const SizedBox(height: 14),
        OutlinedButton(onPressed: _busy ? null : () => _get(self: '', restart: true), child: Text(tr("I'm not sure: let the questions decide"))),
      ]);
    } else if (_st == null || _busy && _st!['question'] == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_st!['done'] == true) {
      final s = _st!;
      body = ListView(padding: const EdgeInsets.all(24), children: [
        const SizedBox(height: 20),
        Image.asset('assets/hudi/cheer.png', height: 120, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
        const SizedBox(height: 12),
        Text(tr('Your level'), textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
        Text('${s['cefr'] ?? ''}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: C.accent)),
        if (s['band'] != null) Text('About IELTS band ${s['band']}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('${s['right']} of ${s['total']} right. Daily English now starts at this level.', textAlign: TextAlign.center, style: TextStyle(color: hint)),
        const SizedBox(height: 24),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Done'))),
        TextButton(onPressed: () => setState(() { _chooseSelf = true; _st = null; }), child: Text(tr('Take it again'))),
      ]);
    } else {
      final q = (_st!['question'] as Map).cast<String, dynamic>();
      final n = (_st!['n'] as num?) ?? 1, total = (_st!['total'] as num?) ?? 1;
      final type = '${q['type']}';
      final canGo = !_busy && (type == 'type' ? _typed.text.trim().isNotEmpty : _picked != null);
      Widget opt(String label, Object value, {bool wide = true}) {
        final sel = _picked == value;
        return Material(
          color: sel ? C.accent.withValues(alpha: .2) : Theme.of(context).colorScheme.onSurface.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _picked = value),
            child: Container(
              width: wide ? double.infinity : null,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Text(label, style: TextStyle(fontSize: 16, fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
            ),
          ),
        );
      }
      body = Column(children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.all(20), children: [
            LinearProgressIndicator(value: (n - 1) / total, minHeight: 8, borderRadius: BorderRadius.circular(6), color: C.green),
            const SizedBox(height: 8),
            Text('Question $n of $total', style: TextStyle(color: hint)),
            const SizedBox(height: 14),
            Text('${q['prompt']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, height: 1.35)),
            const SizedBox(height: 20),
            if (type == 'type')
              TextField(controller: _typed, autofocus: true, autocorrect: false, onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(hintText: tr('Your answer')))
            else if (type == 'spot')
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (var k = 0; k < (q['parts'] as List).length; k++) opt('${(q['parts'] as List)[k]}', k, wide: false),
              ])
            else
              for (final o in (q['options'] as List? ?? [])) Padding(padding: const EdgeInsets.only(bottom: 10), child: opt('$o', '$o')),
          ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(width: double.infinity, child: FilledButton(onPressed: canGo ? _answer : null, child: Text(tr('Next')))),
          ),
        ),
      ]);
    }
    return Scaffold(appBar: AppBar(title: Text(tr('Level check'))), body: body);
  }
}
