// The dashboard's middle, as on the website: the goal band, today's plan, tests to go on with and
// what to work on next.
import 'package:flutter/material.dart';

import '../i18n.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'exam.dart';
import 'games.dart';
import 'more.dart';

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

class HomePlan extends StatefulWidget {
  const HomePlan({super.key, required this.goTab});
  final void Function(int) goTab;
  @override
  State<HomePlan> createState() => _HomePlanState();
}

class _HomePlanState extends State<HomePlan> {
  Map<String, dynamic>? _d;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.I.get('/api/app/home');
      if (mounted) setState(() => _d = r);
    } on ApiError {
      /* the rest of the home page still shows */
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    _load();
  }

  Future<void> _startTest(Map t) async {
    final scopes = ((t['scopes'] as List?) ?? []).cast<String>();
    try {
      final r = await Api.I.post('/api/attempts', {'test': t['slug'], 'scope': scopes.isNotEmpty ? scopes.first : 'full'});
      if (!mounted) return;
      _open(ExamScreen(attemptId: (r['attemptId'] as num).toInt()));
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  Future<void> _editGoal() async {
    final g = (_d?['goal'] as Map?) ?? {};
    var band = ((g['goal'] as num?) ?? 6.5).toDouble();
    String? exam = _d?['examMonth'] as String?;
    final now = DateTime.now();
    final months = [for (var i = 0; i < 18; i++) DateTime(now.year, now.month + i)];
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    String key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr('Your goal'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Text('Band ${band.toStringAsFixed(1)}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: C.accent)),
              Slider(value: band, min: 4, max: 9, divisions: 10, label: band.toStringAsFixed(1), onChanged: (v) => set(() => band = v)),
              const SizedBox(height: 8),
              Text(tr('Exam month'), style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                ChoiceChip(label: Text(tr('Not booked')), selected: exam == null, onSelected: (_) => set(() => exam = null)),
                for (final m in months)
                  ChoiceChip(label: Text('${names[m.month - 1]} ${m.year % 100}'), selected: exam == key(m), onSelected: (_) => set(() => exam = key(m))),
              ]),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Save'))),
            ]),
          ),
        ),
      ),
    );
    if (ok != true) return;
    try {
      await Api.I.post('/api/start/goal', {'goal': band, 'exam': exam});
      _load();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  void _step(Map s) {
    switch (s['key']) {
      case 'daily': widget.goTab(2);
      case 'test': widget.goTab(1);
      case 'games': _open(const GamesScreen());
      case 'words': _open(const WordsReviewScreen());
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) return const SizedBox.shrink();
    final hint = Theme.of(context).hintColor;
    final goal = d['goal'] as Map?;
    final plan = (d['plan'] as Map?) ?? {};
    final steps = ((plan['steps'] as List?) ?? []).cast<Map>();
    final going = ((d['inProgress'] as List?) ?? []).cast<Map>();
    final next = d['nextTest'] as Map?;
    String label(Map s) => switch (s['key']) {
          'daily' => 'Daily English stage',
          'test' => '${_cap('${s['section']}')} practice test${(s['of'] as num) > 1 ? 's' : ''}',
          'games' => 'Two game rounds',
          'words' => 'Review ${s['of']} words',
          _ => '${s['key']}',
        };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 12),
      Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _editGoal,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: goal == null
                ? Row(children: [
                    const Icon(Icons.flag_rounded, color: C.accent),
                    const SizedBox(width: 12),
                    Expanded(child: Text(tr('Set the band you aim for'), style: TextStyle(fontWeight: FontWeight.w700))),
                    Icon(Icons.chevron_right_rounded, color: hint),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.flag_rounded, color: C.accent),
                      const SizedBox(width: 8),
                      Text('Goal: band ${goal['goal']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      const Spacer(),
                      if (goal['month'] != null) Text('${goal['month']}', style: TextStyle(color: hint)),
                    ]),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(value: ((goal['pct'] as num?) ?? 0) / 100, minHeight: 8, borderRadius: BorderRadius.circular(6), color: C.accent),
                    const SizedBox(height: 8),
                    Text(
                      goal['now'] == null
                          ? 'Take a test to see where you are.'
                          : (goal['left'] as num? ?? 0) <= 0
                              ? 'You are at band ${goal['now']}: goal reached!'
                              : 'Now ${goal['now']} · ${goal['left']} to go${goal['weeks'] != null ? ' · ${goal['weeks']} weeks left' : ''}',
                      style: TextStyle(color: hint),
                    ),
                  ]),
          ),
        ),
      ),
      if (steps.isNotEmpty) ...[
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(tr("Today's plan"), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                Text('${plan['done']} / ${plan['total']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: ((plan['pct'] as num?) ?? 0) / 100, minHeight: 6, borderRadius: BorderRadius.circular(4), color: C.green),
              for (final s in steps)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  onTap: s['done'] == true ? null : () => _step(s),
                  leading: Icon(s['done'] == true ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      color: s['done'] == true ? C.green : hint),
                  title: Text(label(s), style: TextStyle(
                      fontWeight: FontWeight.w600, decoration: s['done'] == true ? TextDecoration.lineThrough : null)),
                  trailing: s['key'] == 'words' ? null : Text('${s['n']}/${s['of']}', style: TextStyle(color: hint)),
                ),
            ]),
          ),
        ),
      ],
      if (going.isNotEmpty) ...[
        const SizedBox(height: 12),
        Card(
          child: Column(children: [
            ListTile(title: Text(tr('Go on with'), style: TextStyle(fontWeight: FontWeight.w800))),
            for (final a in going)
              ListTile(
                leading: const Icon(Icons.play_circle_rounded, color: C.accent),
                title: Text('${a['testTitle']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(a['scope'] == 'full' ? tr('Full mock') : _cap('${a['scope']}')),
                onTap: () => _open(ExamScreen(attemptId: (a['id'] as num).toInt())),
              ),
          ]),
        ),
      ],
      if (next != null) ...[
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.auto_awesome_rounded, color: C.gold),
            title: Text('${next['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${next['reason'] ?? next['description'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.play_arrow_rounded),
            onTap: () => _startTest(next),
          ),
        ),
      ],
      const SizedBox(height: 12),
      Card(
        child: ListTile(
          leading: const Icon(Icons.lightbulb_rounded, color: C.gold),
          title: Text(tr('Recommendations')),
          subtitle: Text(tr('What to practise, from the questions you miss')),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _open(const RecommendationsScreen()),
        ),
      ),
    ]);
  }
}
