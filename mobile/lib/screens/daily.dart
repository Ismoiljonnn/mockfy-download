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
        build: (context, map, reload) => _Map(map: map, reload: reload),
      ),
    );
  }
}

/// The map opens at the stage you are on; scroll away and a button in the corner brings you back.
class _Map extends StatefulWidget {
  const _Map({required this.map, required this.reload});
  final Map<String, dynamic> map;
  final Future<void> Function() reload;
  @override
  State<_Map> createState() => _MapState();
}

class _MapState extends State<_Map> {
  final _scroll = ScrollController();
  final _here = GlobalKey();
  int _away = 0;          // 0: on screen, -1: above, 1: below

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _goHere(animate: false));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String? get _currentId {
    for (final z in (widget.map['zones'] as List)) {
      for (final st in ((z as Map)['stages'] as List)) {
        if ((st as Map)['status'] == 'open') return '${st['id']}';
      }
    }
    return null;
  }

  void _goHere({bool animate = true}) {
    final ctx = _here.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx, alignment: .4, duration: animate ? const Duration(milliseconds: 450) : Duration.zero, curve: Curves.easeInOutCubic)
        .then((_) => _check());
  }

  void _check() {
    final ctx = _here.currentContext;
    final view = context.findRenderObject() as RenderBox?;
    var away = 0;
    if (ctx == null) {
      away = 1;                                   // not built yet: far below
    } else if (view != null) {
      final box = ctx.findRenderObject() as RenderBox?;
      if (box != null && box.attached) {
        final top = box.localToGlobal(Offset.zero, ancestor: view).dy;
        away = top + box.size.height < 0 ? -1 : top > view.size.height ? 1 : 0;
      }
    }
    if (away != _away && mounted) setState(() => _away = away);
  }

  @override
  Widget build(BuildContext context) {
    final map = widget.map;
    final zones = (map['zones'] as List).cast<Map>();
    final current = _currentId;
    return Stack(children: [
      ListView(controller: _scroll, cacheExtent: 100000, padding: const EdgeInsets.fromLTRB(16, 4, 16, 90), children: [
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
            child: Text('${z['number']}. ${z['place'] ?? z['id']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          for (final st in (z['stages'] as List).cast<Map>())
            KeyedSubtree(
              key: '${st['id']}' == current ? _here : null,
              child: _StageTile(stage: st.cast<String, dynamic>(), onDone: widget.reload),
            ),
        ],
      ]),
      if (current != null)
        Positioned(
          right: 16, bottom: 16,
          child: AnimatedScale(
            scale: _away == 0 ? 0 : 1,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutBack,
            child: FloatingActionButton(
              heroTag: 'daily-here',
              backgroundColor: C.green,
              foregroundColor: Colors.white,
              tooltip: 'Back to my stage',
              onPressed: _goHere,
              child: Icon(_away < 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded),
            ),
          ),
        ),
    ]);
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
