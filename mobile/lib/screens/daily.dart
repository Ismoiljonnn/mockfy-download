import 'dart:math';

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

/// The Daily English map: each zone a stretch of a winding path, every stage a round stop on it (done
/// with its stars, the one you are on, locked ahead). It opens at your stage; scroll far from it and a
/// button in the corner brings you back. Every row has a fixed height, so where your stage is on the
/// page is simply counted, never guessed.
const double _kTop = 96, _kZone = 76, _kStop = 104;
const _zoneColours = [Color(0xFF4CB782), Color(0xFF5B8DEF), Color(0xFFD97757), Color(0xFF9B7BEA), Color(0xFFE8A52A), Color(0xFF2BB3B1)];

class _Map extends StatefulWidget {
  const _Map({required this.map, required this.reload});
  final Map<String, dynamic> map;
  final Future<void> Function() reload;
  @override
  State<_Map> createState() => _MapState();
}

class _MapState extends State<_Map> {
  final _scroll = ScrollController();
  int _away = 0;                  // 0: your stage is on screen, -1: above, 1: below
  late List<Object> _rows;        // a zone (Map with 'place') or a stage (Map with 'id')
  int _hereRow = -1;
  final List<(int, int)> _meta = [];   // for each row: its zone's number on the page, its place in the zone

  @override
  void initState() {
    super.initState();
    _layout();
    _scroll.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _goHere(animate: false));
  }

  @override
  void didUpdateWidget(_Map old) {
    super.didUpdateWidget(old);
    _layout();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _layout() {
    _rows = [];
    _meta.clear();
    _hereRow = -1;
    var zi = 0;
    for (final z in (widget.map['zones'] as List).cast<Map>()) {
      _rows.add(z);
      _meta.add((zi, 0));
      var k = 0;
      for (final st in (z['stages'] as List).cast<Map>()) {
        if (_hereRow < 0 && st['status'] == 'open') _hereRow = _rows.length;
        _rows.add(st);
        _meta.add((zi, k++));
      }
      zi++;
    }
  }

  double _offsetOf(int row) {
    var y = _kTop;
    for (var i = 0; i < row; i++) { y += (_rows[i] as Map).containsKey('stages') ? _kZone : _kStop; }
    return y;
  }

  void _goHere({bool animate = true}) {
    if (_hereRow < 0 || !_scroll.hasClients) return;
    final view = _scroll.position.viewportDimension;
    final target = (_offsetOf(_hereRow) - view * .4).clamp(0.0, _scroll.position.maxScrollExtent);
    if (animate) {
      _scroll.animateTo(target, duration: const Duration(milliseconds: 450), curve: Curves.easeInOutCubic);
    } else {
      _scroll.jumpTo(target);
    }
    _check();
  }

  void _check() {
    if (_hereRow < 0 || !_scroll.hasClients) return;
    final top = _offsetOf(_hereRow), bottom = top + _kStop;
    final from = _scroll.offset, to = from + _scroll.position.viewportDimension;
    final away = bottom < from ? -1 : top > to ? 1 : 0;
    if (away != _away && mounted) setState(() => _away = away);
  }

  @override
  Widget build(BuildContext context) {
    final map = widget.map;
    return Stack(children: [
      ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.only(bottom: 90),
        itemCount: _rows.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) return SizedBox(height: _kTop, child: _Summary(map: map));
          final row = _rows[i - 1] as Map;
          final (zi, k) = _meta[i - 1];
          final c = _zoneColours[zi % _zoneColours.length];
          if (row.containsKey('stages')) {
            return SizedBox(height: _kZone, child: _ZoneBanner(zone: row.cast<String, dynamic>(), colour: c));
          }
          return SizedBox(
            height: _kStop,
            child: _Stop(stage: row.cast<String, dynamic>(), colour: c, index: k, onDone: widget.reload),
          );
        },
      ),
      if (_hereRow >= 0)
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

class _Summary extends StatelessWidget {
  const _Summary({required this.map});
  final Map<String, dynamic> map;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              const Icon(Icons.flag_rounded, color: C.green, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${map['done']} of ${map['total']} stages', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: (map['total'] ?? 0) == 0 ? 0 : (map['done'] as num) / (map['total'] as num),
                    color: C.green, minHeight: 6, borderRadius: BorderRadius.circular(4),
                  ),
                ]),
              ),
              const SizedBox(width: 12),
              Row(children: [const Icon(Icons.star_rounded, color: C.gold), Text(' ${map['stars']}', style: const TextStyle(fontWeight: FontWeight.w800))]),
            ]),
          ),
        ),
      );
}

class _ZoneBanner extends StatelessWidget {
  const _ZoneBanner({required this.zone, required this.colour});
  final Map<String, dynamic> zone;
  final Color colour;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: colour, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            Text('${zone['number']}', style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
            const SizedBox(width: 14),
            Expanded(child: Text('${zone['place'] ?? zone['id']}', overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800))),
            const Icon(Icons.map_rounded, color: Colors.white70),
          ]),
        ),
      );
}

/// One stop on the path: the path swings left and right, like a trail across a map.
class _Stop extends StatelessWidget {
  const _Stop({required this.stage, required this.colour, required this.index, required this.onDone});
  final Map<String, dynamic> stage;
  final Color colour;
  final int index;
  final Future<void> Function() onDone;

  @override
  Widget build(BuildContext context) {
    final status = stage['status'];
    final locked = status == 'locked', done = status == 'done', here = status == 'open';
    final stars = (stage['stars'] as num?)?.toInt() ?? 0;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final swing = sin(index * pi / 3);                      // -1..1 across the page
    final fill = locked ? (dark ? const Color(0xFF3A3A3A) : const Color(0xFFDEDBD2)) : done ? C.gold : colour;
    final size = here ? 74.0 : 62.0;
    return LayoutBuilder(builder: (context, box) {
      final x = box.maxWidth / 2 + swing * box.maxWidth * .26 - size / 2;
      return Stack(clipBehavior: Clip.none, children: [
        Positioned(
          left: x, top: (_kStop - size) / 2 - 8,
          child: GestureDetector(
            onTap: locked ? null : () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => StageScreen(stageId: '${stage['id']}', title: '${stage['title']}')));
              onDone();
            },
            child: Column(children: [
              Container(
                width: size, height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fill,
                  boxShadow: [BoxShadow(color: (locked ? Colors.black : fill).withValues(alpha: locked ? .12 : .45), offset: const Offset(0, 5))],
                  border: here ? Border.all(color: Colors.white, width: 4) : null,
                ),
                child: Icon(locked ? Icons.lock_rounded : done ? Icons.check_rounded : Icons.play_arrow_rounded,
                    color: locked ? (dark ? Colors.white38 : Colors.black38) : Colors.white, size: here ? 38 : 30),
              ),
              if (done)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  for (var i = 0; i < 3; i++) Icon(i < stars ? Icons.star_rounded : Icons.star_border_rounded, color: C.gold, size: 15),
                ]),
            ]),
          ),
        ),
        if (here)
          Positioned(
            left: swing > 0 ? 16 : null, right: swing > 0 ? null : 16, top: _kStop / 2 - 26,
            child: Container(
              constraints: BoxConstraints(maxWidth: box.maxWidth * .38),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))]),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                const Text('Start here', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.green)),
                Text('${stage['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
      ]);
    });
  }
}

