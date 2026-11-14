import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'exam.dart';

const sectionIcons = {
  'listening': Icons.headphones_rounded,
  'reading': Icons.menu_book_rounded,
  'writing': Icons.edit_note_rounded,
  'speaking': Icons.mic_rounded,
};
const sectionColors = {'listening': C.blue, 'reading': C.green, 'writing': C.accent, 'speaking': Color(0xFF9B7BEA)};

/// Full mock tests and single-section practice, started and taken in the app.
class TestsScreen extends StatelessWidget {
  const TestsScreen({super.key, required this.onSignedOut});
  final VoidCallback onSignedOut;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Tests'),
          bottom: const TabBar(tabs: [Tab(text: 'Full mock'), Tab(text: 'Section practice')]),
        ),
        body: Loader<Map<String, dynamic>>(
          load: () => Api.I.get('/api/app/tests'),
          onSignedOut: onSignedOut,
          build: (context, d, reload) => TabBarView(children: [
            _List(tests: (d['full'] as List).cast<Map>(), full: true, reload: reload),
            _List(tests: (d['practice'] as List).cast<Map>(), full: false, reload: reload),
          ]),
        ),
      ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.tests, required this.full, required this.reload});
  final List<Map> tests;
  final bool full;
  final Future<void> Function() reload;

  @override
  Widget build(BuildContext context) {
    if (tests.isEmpty) return const Center(child: Text('No tests here yet.'));
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (full)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text('All four sections in one sitting, with real timing, like the exam day.',
              style: TextStyle(color: Theme.of(context).hintColor)),
        ),
      for (final t in tests) _TestCard(test: t.cast<String, dynamic>(), full: full, reload: reload),
    ]);
  }
}

class _TestCard extends StatelessWidget {
  const _TestCard({required this.test, required this.full, required this.reload});
  final Map<String, dynamic> test;
  final bool full;
  final Future<void> Function() reload;

  Future<void> _start(BuildContext context, String scope) async {
    try {
      final r = await Api.I.post('/api/attempts', {'test': test['slug'], 'scope': scope});
      if (!context.mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ExamScreen(attemptId: (r['attemptId'] as num).toInt())));
      reload();
    } on ApiError catch (e) {
      if (context.mounted) toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sections = (test['sections'] as List? ?? []).cast<Map>();
    final scopes = (test['scopes'] as List? ?? []).cast<String>();
    final resume = (test['resume'] as Map?) ?? {};
    final minutes = sections.fold<num>(0, (a, s) => a + ((s['duration_min'] as num?) ?? 0));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${test['title']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(spacing: 10, runSpacing: 6, children: [
              for (final s in sections)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(sectionIcons[s['key']] ?? Icons.quiz_rounded, size: 16, color: sectionColors[s['key']]),
                  const SizedBox(width: 4),
                  Text('${s['title']}', style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13)),
                ]),
              Text('· $minutes min', style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13)),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final sc in scopes)
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: () => _start(context, sc),
                  child: Text(resume.containsKey(sc) ? 'Continue' : sc == 'full' ? 'Start full mock' : 'Start ${sc[0].toUpperCase()}${sc.substring(1)}'),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}
