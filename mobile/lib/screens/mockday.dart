// Mock Day in the app: the next event (join, then take the test at the set time), and the results.
import 'package:flutter/material.dart';

import '../i18n.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'exam.dart';

class MockDayScreen extends StatelessWidget {
  const MockDayScreen({super.key});

  String _when(dynamic local) {
    final d = DateTime.tryParse('${local ?? ''}');
    if (d == null) return '';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]}, ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Mock Day'))),
      body: Loader<Map<String, dynamic>>(
        load: () => Api.I.get('/api/app/mockday'),
        build: (context, d, reload) {
          final e = (d['event'] as Map?)?.cast<String, dynamic>();
          if (e == null) {
            return ListView(children: [Padding(padding: EdgeInsets.all(40),
                child: Center(child: Text(tr('No Mock Day is planned yet. Watch your notifications for the next one.'), textAlign: TextAlign.center)))]);
          }
          final state = '${e['state']}';
          final mine = e['me'] as Map?;
          final top = (d['top'] as List? ?? []).cast<Map>();
          final prizes = (d['prizes'] as List? ?? []);
          Future<void> act(String what) async {
            try {
              if (what == 'start') {
                final r = await Api.I.post('/api/app/mockday/${e['id']}/start');
                if (context.mounted) {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => ExamScreen(attemptId: (r['attemptId'] as num).toInt())));
                }
              } else {
                await Api.I.post('/api/mockday/${e['id']}/$what');
              }
              await reload();
            } on ApiError catch (err) {
              if (context.mounted) toast(context, err.message);
            }
          }

          return ListView(padding: const EdgeInsets.all(16), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.event_rounded, color: C.gold, size: 30),
                    const SizedBox(width: 10),
                    Expanded(child: Text('${e['title'] ?? 'Mock Day'}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                  ]),
                  const SizedBox(height: 10),
                  Text('${e['test_title'] ?? ''}${e['minutes'] != null ? ' · ${e['minutes']} min' : ''}', style: TextStyle(color: Theme.of(context).hintColor)),
                  const SizedBox(height: 6),
                  Text(switch (state) {
                    'upcoming' => 'Starts ${_when(e['starts_local'])}',
                    'open' => 'Open now, until ${_when(e['ends_local'])}',
                    'waiting' => 'Results on ${_when(e['results_local'])}',
                    _ => 'Results are out',
                  }, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('${e['joined'] ?? 0} learners joined', style: TextStyle(color: Theme.of(context).hintColor)),
                  if (prizes.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('${tr('Prizes')}: ${prizes.asMap().entries.map((p) => '#${p.key + 1} ${p.value} 💎').join(' · ')}'),
                  ],
                  const SizedBox(height: 16),
                  if (state == 'upcoming' || state == 'open') ...[
                    if (mine == null)
                      FilledButton(onPressed: () => act('join'), child: Text(tr('Join')))
                    else if (state == 'open' && mine['band'] == null)
                      FilledButton(onPressed: () => act('start'), child: Text(tr('Start the test')))
                    else if (state == 'upcoming')
                      Row(children: [
                        const Icon(Icons.check_circle_rounded, color: C.green),
                        const SizedBox(width: 8),
                        Expanded(child: Text(tr('You are in. We will remind you when it starts.'))),
                        TextButton(onPressed: () => act('leave'), child: Text(tr('Leave'))),
                      ]),
                  ],
                  if (mine != null && mine['band'] != null)
                    Text(tr('Your band: {n}', {'n': mine['band']}), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: C.accent)),
                ]),
              ),
            ),
            if (top.isNotEmpty) ...[
              Padding(padding: EdgeInsets.fromLTRB(4, 20, 4, 8), child: Text(tr('Results'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              for (var i = 0; i < top.length; i++)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Text('${i + 1}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    title: Text('${top[i]['name']}'),
                    trailing: Text('${top[i]['band']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                ),
            ],
          ]);
        },
      ),
    );
  }
}
