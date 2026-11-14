import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'stage.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.me, required this.onSignedOut, required this.goTab});
  final Map<String, dynamic> me;
  final VoidCallback onSignedOut;
  final void Function(int) goTab;

  Future<Map<String, dynamic>> _load() async {
    final r = await Future.wait([
      Api.I.get('/api/app/me'),
      Api.I.get('/api/streak'),
      Api.I.get('/api/daily'),
    ]);
    return {'me': r[0]['me'], 'streak': r[1]['streak'], 'daily': r[2]['map']};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Loader<Map<String, dynamic>>(
          load: _load,
          onSignedOut: onSignedOut,
          build: (context, d, reload) {
            final m = d['me'] as Map<String, dynamic>;
            final streak = d['streak'] as Map<String, dynamic>;
            final daily = d['daily'] as Map<String, dynamic>;
            final next = _nextStage(daily);
            return ListView(padding: const EdgeInsets.all(16), children: [
              Row(children: [
                Avatar(url: m['avatar'] as String?, initial: (m['name'] as String? ?? '?').substring(0, 1).toUpperCase(), size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Hello,', style: TextStyle(color: Theme.of(context).hintColor)),
                    Row(children: [
                      Flexible(child: Text('${m['name']}', overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
                      if (m['isPro'] == true) ...[const SizedBox(width: 6), const ProTick()],
                    ]),
                  ]),
                ),
              ]),
              const SizedBox(height: 16),
              _StreakCard(streak: streak),
              const SizedBox(height: 12),
              Row(children: [
                StatTile(icon: Icons.star_rounded, color: C.gold, value: '${m['points'] ?? 0}', label: 'Points'),
                const SizedBox(width: 12),
                StatTile(icon: Icons.diamond_rounded, color: const Color(0xFF9B7BEA), value: '${m['crystals'] ?? 0}', label: 'Crystals'),
              ]),
              const SizedBox(height: 12),
              Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: next == null ? () => goTab(1) : () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => StageScreen(stageId: next['id'] as String, title: next['title'] as String)));
                    reload();
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      Container(
                        width: 52, height: 52,
                        decoration: BoxDecoration(color: C.green.withValues(alpha: .15), borderRadius: BorderRadius.circular(14)),
                        child: const Icon(Icons.play_arrow_rounded, color: C.green, size: 32),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Daily English', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                          const SizedBox(height: 2),
                          Text(daily['todayDone'] == true ? 'Today\'s stage is done. Keep going!' : next != null ? 'Next: ${next['title']}' : 'Open the map',
                              style: TextStyle(color: Theme.of(context).hintColor)),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: (daily['total'] ?? 0) == 0 ? 0 : (daily['done'] as num) / (daily['total'] as num),
                            borderRadius: BorderRadius.circular(4), color: C.green, minHeight: 6,
                          ),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  onTap: () => openWeb('/practice'),
                  leading: const Icon(Icons.headphones_rounded, color: C.blue),
                  title: const Text('Mock tests and section practice'),
                  subtitle: const Text('Listening, Reading, Writing and Speaking'),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 20),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }

  Map<String, dynamic>? _nextStage(Map<String, dynamic> daily) {
    for (final z in (daily['zones'] as List? ?? [])) {
      for (final s in ((z as Map)['stages'] as List)) {
        if ((s as Map)['status'] == 'open') return s.cast<String, dynamic>();
      }
    }
    return null;
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.streak});
  final Map<String, dynamic> streak;
  @override
  Widget build(BuildContext context) {
    final days = (streak['days'] as List? ?? []).cast<Map>();
    final count = streak['count'] ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.local_fire_department_rounded, color: C.accent, size: 30),
            const SizedBox(width: 8),
            Text('$count', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(width: 6),
            Text(count == 1 ? 'day streak' : 'day streak', style: TextStyle(color: Theme.of(context).hintColor)),
            const Spacer(),
            Text('Best ${streak['best'] ?? 0}', style: TextStyle(color: Theme.of(context).hintColor)),
          ]),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            for (final d in days)
              Column(children: [
                Text('${d['day']}', style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor,
                    fontWeight: d['isToday'] == true ? FontWeight.w800 : FontWeight.w500)),
                const SizedBox(height: 6),
                Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: d['active'] == true ? C.accent : Colors.transparent,
                    border: Border.all(color: d['active'] == true ? C.accent : Theme.of(context).dividerColor, width: d['isToday'] == true ? 2 : 1),
                  ),
                  child: d['active'] == true ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null,
                ),
              ]),
          ]),
        ]),
      ),
    );
  }
}
