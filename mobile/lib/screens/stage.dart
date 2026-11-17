import 'package:flutter/material.dart';

import '../i18n.dart';

import '../api.dart';
import '../theme.dart';
import '../prefs.dart';
import '../widgets.dart';

/// One Daily English stage: choice, type-the-word and spot-the-mistake questions, one at a time,
/// with the right answer and why, and the result (stars, points, streak) at the end.
class StageScreen extends StatefulWidget {
  const StageScreen({super.key, required this.stageId, required this.title});
  final String stageId;
  final String title;
  @override
  State<StageScreen> createState() => _StageScreenState();
}

class _StageScreenState extends State<StageScreen> {
  List<Map<String, dynamic>> _qs = [];
  int _i = 0;
  bool _loading = true;
  String? _error;
  bool _sending = false;
  Map<String, dynamic>? _feedback;     // the answer to the current question
  Map<String, dynamic>? _result;       // the stage is finished
  Object? _picked;
  final _typed = TextEditingController();
  int _score = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await Api.I.post('/api/daily/${widget.stageId}/start');
      final answered = (r['answered'] as Map?) ?? {};
      final qs = (r['questions'] as List).cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
      setState(() {
        _qs = qs;
        _i = qs.indexWhere((q) => !answered.containsKey(q['id']));
        if (_i < 0) _i = 0;
        _loading = false;
      });
    } on ApiError catch (e) {
      setState(() { _error = e.message; _loading = false; });
    }
  }

  Map<String, dynamic> get _q => _qs[_i];

  bool get _canCheck {
    if (_feedback != null || _sending) return false;
    if (_q['type'] == 'type') return _typed.text.trim().isNotEmpty;
    return _picked != null;
  }

  Future<void> _check() async {
    final answer = _q['type'] == 'type' ? _typed.text.trim() : _picked;
    setState(() => _sending = true);
    try {
      final r = await Api.I.post('/api/daily/${widget.stageId}/answer', {'question': _q['id'], 'answer': answer});
      if (r['secondChance'] == true) {
        if (mounted) toast(context, tr('Second chance used. Try once more ({n} left).', {'n': r['left']}));
        setState(() { _picked = null; _typed.clear(); });
        return;
      }
      if (r['correct'] == true) _score++;
      Sfx.play(r['correct'] == true ? 'right' : 'error');
      if (r['result'] is Map) Future.delayed(const Duration(milliseconds: 500), () => Sfx.play('win'));
      setState(() {
        _feedback = r;
        if (r['result'] is Map) _result = (r['result'] as Map).cast<String, dynamic>();
      });
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _next() {
    if (_result != null || _i >= _qs.length - 1) {
      setState(() { _feedback = null; _i = _qs.length; });
      return;
    }
    setState(() { _i++; _feedback = null; _picked = null; _typed.clear(); });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null) {
      return Scaffold(appBar: AppBar(), body: ErrorView(message: _error!, onRetry: _start));
    }
    if (_i >= _qs.length) return _ResultView(title: widget.title, result: _result, score: _score, total: _qs.length);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
        title: LinearProgressIndicator(
          value: (_i + (_feedback != null ? 1 : 0)) / _qs.length,
          minHeight: 10, borderRadius: BorderRadius.circular(6), color: C.green,
        ),
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.all(20), children: [
              Text(_q['type'] == 'spot' ? tr('Tap the part with the mistake') : _q['type'] == 'type' ? 'Type the answer' : 'Choose the answer',
                  style: TextStyle(color: Theme.of(context).hintColor, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Text('${_q['prompt']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, height: 1.35)),
              const SizedBox(height: 22),
              ..._answerArea(),
            ]),
          ),
          _bottomBar(),
        ]),
      ),
    );
  }

  List<Widget> _answerArea() {
    final fb = _feedback;
    switch (_q['type']) {
      case 'type':
        return [
          TextField(
            controller: _typed,
            enabled: fb == null,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) { if (_canCheck) _check(); },
            decoration: InputDecoration(
              hintText: tr('Your answer'),
              filled: true,
              fillColor: Theme.of(context).brightness == Brightness.dark ? Colors.white.withValues(alpha: .07) : const Color(0xFF141413).withValues(alpha: .05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
        ];
      case 'spot':
        final parts = (_q['parts'] as List).cast<String>();
        return [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var k = 0; k < parts.length; k++) _option(parts[k], k),
          ]),
        ];
      default:
        final opts = (_q['options'] as List).cast<String>();
        return [for (final o in opts) Padding(padding: const EdgeInsets.only(bottom: 10), child: _option(o, o, wide: true))];
    }
  }

  // filled tiles, no borders: the fill says what it is (picked, right, wrong); the text keeps
  // full contrast in both day and night
  Widget _option(String label, Object value, {bool wide = false}) {
    final fb = _feedback;
    final selected = _picked == value;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = Theme.of(context).colorScheme.onSurface;
    Color fill = dark ? Colors.white.withValues(alpha: .07) : const Color(0xFF141413).withValues(alpha: .05);
    Color text = ink;
    if (fb != null && selected) {
      final ok = fb['correct'] == true;
      fill = (ok ? C.green : C.red).withValues(alpha: dark ? .32 : .18);
      text = dark ? Colors.white : (ok ? const Color(0xFF1E6B47) : const Color(0xFF9B2C26));
    } else if (selected) {
      fill = C.accent.withValues(alpha: dark ? .34 : .2);
      text = dark ? Colors.white : const Color(0xFF8A3B1E);
    }
    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: fb != null ? null : () { Sfx.play('tap'); setState(() => _picked = value); },
        child: Container(
          constraints: BoxConstraints(minHeight: wide ? 54 : 48),
          width: wide ? double.infinity : null,
          alignment: wide ? Alignment.centerLeft : Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(label, style: TextStyle(fontSize: 16, color: text, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    final fb = _feedback;
    if (fb == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(onPressed: _canCheck ? _check : null, child: _sending
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            : Text(tr('Check'))),
      );
    }
    final ok = fb['correct'] == true;
    final color = ok ? C.green : C.red;
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: .12),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.cancel_rounded, color: color),
          const SizedBox(width: 8),
          Text(ok ? tr('Correct!') : tr('Not quite'), style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 18)),
          const Spacer(),
          if ((fb['points'] ?? 0) != 0) Text('+${fb['points']}', style: const TextStyle(color: C.gold, fontWeight: FontWeight.w700)),
        ]),
        if (!ok) ...[
          const SizedBox(height: 6),
          Text('${tr('Answer')}: ${fb['answer']}', style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
        if ((fb['explain'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('${fb['explain']}'),
        ],
        const SizedBox(height: 12),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: color),
          onPressed: _next,
          child: Text(_i >= _qs.length - 1 ? tr('See results') : 'Continue'),
        ),
      ]),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({required this.title, required this.result, required this.score, required this.total});
  final String title;
  final Map<String, dynamic>? result;
  final int score;
  final int total;

  @override
  Widget build(BuildContext context) {
    final r = result ?? {};
    final stars = (r['stars'] as num?)?.toInt() ?? 0;
    final streak = (r['streak'] as Map?)?['count'];
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const Spacer(),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: EdgeInsets.only(bottom: i == 1 ? 18 : 0),
                  child: Icon(i < stars ? Icons.star_rounded : Icons.star_border_rounded, color: C.gold, size: i == 1 ? 76 : 60),
                ),
            ]),
            const SizedBox(height: 12),
            Text(stars >= 2 ? tr('Great work!') : stars == 1 ? 'Stage done!' : 'Keep practising!',
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(title, style: TextStyle(color: Theme.of(context).hintColor)),
            const SizedBox(height: 24),
            Row(children: [
              StatTile(icon: Icons.check_circle_rounded, color: C.green, value: '${r['score'] ?? score}/${r['total'] ?? total}', label: tr('Correct')),
              const SizedBox(width: 12),
              StatTile(icon: Icons.star_rounded, color: C.gold, value: '+${r['points'] ?? 0}', label: tr('Points')),
              if (streak != null) ...[
                const SizedBox(width: 12),
                StatTile(icon: Icons.local_fire_department_rounded, color: C.accent, value: '$streak', label: tr('Streak')),
              ],
            ]),
            const Spacer(),
            FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('Done'))),
          ]),
        ),
      ),
    );
  }
}
