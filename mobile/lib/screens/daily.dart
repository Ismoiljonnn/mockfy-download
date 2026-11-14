import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'stage.dart';

/// The Daily English map: zones, each with its stages (open, done with stars, locked).
class DailyScreen extends StatelessWidget {
  const DailyScreen({super.key, required this.onSignedOut});
  final VoidCallback onSignedOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Daily English')),
      body: Loader<Map<String, dynamic>>(
        load: () async => (await Api.I.get('/api/daily'))['map'] as Map<String, dynamic>,
        onSignedOut: onSignedOut,
        build: (context, map, reload) {
          final zones = (map['zones'] as List).cast<Map>();
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  const Icon(Icons.flag_rounded, color: C.green, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${map['done']} of ${map['total']} stages', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      Text('${map['stars']} stars', style: TextStyle(color: Theme.of(context).hintColor)),
                    ]),
                  ),
                  if (map['todayDone'] == true)
                    const Chip(avatar: Icon(Icons.check_circle_rounded, color: C.green, size: 18), label: Text('Today done')),
                ]),
              ),
            ),
            for (final z in zones) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
                child: Text('${z['number']}. ${z['place'] ?? z['id']}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              for (final s in (z['stages'] as List).cast<Map>()) _StageTile(stage: s.cast<String, dynamic>(), onDone: reload),
            ],
          ]);
        },
      ),
    );
  }
}

class _StageTile extends StatelessWidget {
  const _StageTile({required this.stage, required this.onDone});
  final Map<String, dynamic> stage;
  final Future<void> Function() onDone;

  @override
  Widget build(BuildContext context) {
    final status = stage['status'];
    final locked = status == 'locked';
    final done = status == 'done';
    final stars = (stage['stars'] as num?)?.toInt() ?? 0;
    final color = locked ? Theme.of(context).disabledColor : done ? C.gold : C.green;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          enabled: !locked,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: .15),
            child: locked ? Icon(Icons.lock_rounded, color: color, size: 20)
                : Text('${stage['index']}', style: TextStyle(color: color, fontWeight: FontWeight.w800)),
          ),
          title: Text('${stage['title']}', style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${stage['questions']} questions'),
          trailing: done
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  for (var i = 0; i < 3; i++) Icon(i < stars ? Icons.star_rounded : Icons.star_border_rounded, color: C.gold, size: 20),
                ])
              : locked ? null : const Icon(Icons.play_circle_fill_rounded, color: C.green, size: 30),
          onTap: locked ? null : () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => StageScreen(stageId: '${stage['id']}', title: '${stage['title']}')));
            onDone();
          },
        ),
      ),
    );
  }
}
