import 'dart:math';

import 'package:flutter/material.dart';

import '../i18n.dart';

import '../desktop_shell.dart';
import '../api.dart';
import '../prefs.dart';
import '../theme.dart';
import '../widgets.dart';
import 'placement.dart';
import 'stage.dart';

/// The Daily English map: zones, each with its stages (open, done with stars, locked); the chests on
/// the path and the level check are in the bar.
class DailyScreen extends StatefulWidget {
  const DailyScreen({super.key, required this.onSignedOut});
  final VoidCallback onSignedOut;
  @override
  State<DailyScreen> createState() => _DailyScreenState();
}

class _DailyScreenState extends State<DailyScreen> {
  Key _k = UniqueKey();
  List<Map> _chests = const [];
  bool _placed = true;

  Future<Map<String, dynamic>> _load() async {
    final r = await Api.I.get('/api/daily');
    final map = (r['map'] as Map).cast<String, dynamic>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() { _chests = ((map['chests'] as List?) ?? []).cast<Map>(); _placed = r['placed'] != false; });
    });
    return map;
  }

  void _again() => setState(() => _k = UniqueKey());

  Future<void> _levelCheck() async {
    final done = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const PlacementScreen()));
    if (done == true) _again();
  }

  Future<void> _openChest(int n) async {
    try {
      final r = await Api.I.post('/api/daily/chest/$n');
      final c = (r['chest'] as Map?) ?? {};
      Sfx.play('win');
      if (!mounted) return;
      final item = c['item'] as Map?;
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          icon: const Text('🎁', style: TextStyle(fontSize: 48)),
          title: Text(tr('Chest opened!')),
          content: Text(item != null ? tr('You got {x}.', {'x': item['name']}) : tr('+{n} points', {'n': c['points'] ?? 0}), textAlign: TextAlign.center),
          actions: [TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Great')))],
        ),
      );
      _again();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  void _showChests() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
          Text(tr('Chests on the path'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(tr('One after every few stages. Finish the stage before it to open it.'), style: TextStyle(color: Theme.of(context).hintColor)),
          const SizedBox(height: 8),
          for (final c in _chests)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Text(c['status'] == 'opened' ? '📭' : c['status'] == 'ready' ? '🎁' : '🔒', style: const TextStyle(fontSize: 28)),
              title: Text(tr('After stage {n}', {'n': c['n']})),
              subtitle: Text(c['status'] == 'opened'
                  ? (c['item'] != null ? 'Opened' : 'Opened')
                  : c['status'] == 'ready' ? 'Ready to open' : 'Locked'),
              trailing: c['status'] == 'ready'
                  ? FilledButton(onPressed: () { Navigator.pop(sheet); _openChest((c['n'] as num).toInt()); }, child: Text(tr('Open')))
                  : null,
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = _chests.where((c) => c['status'] == 'ready').length;
    return Scaffold(
      appBar: rootBar(context, AppBar(leading: menuButton(context), title: Text(tr('Daily English')), actions: [
        if (_chests.isNotEmpty)
          IconButton(
            tooltip: tr('Chests'),
            onPressed: _showChests,
            icon: Badge(isLabelVisible: ready > 0, label: Text('$ready'), child: const Icon(Icons.card_giftcard_rounded)),
          ),
        IconButton(tooltip: tr('Level check'), onPressed: _levelCheck, icon: const Icon(Icons.speed_rounded)),
      ])),
      body: Column(children: [
        if (!_placed)
          MaterialBanner(
            leading: const Icon(Icons.speed_rounded, color: C.accent),
            content: Text(tr('Take the 3-minute level check so the stages fit your level.')),
            actions: [TextButton(onPressed: _levelCheck, child: Text(tr('Start')))],
          ),
        Expanded(
          child: Loader<Map<String, dynamic>>(
            key: _k,
            load: _load,
            onSignedOut: widget.onSignedOut,
            build: (context, map, reload) => _Map(map: map, reload: reload),
          ),
        ),
      ]),
    );
  }
}

/// The Daily English map: each zone a stretch of a winding path, every stage a round stop on it (done
/// with its stars, the one you are on, locked ahead). It opens at your stage; scroll far from it and a
/// button in the corner brings you back. Every row has a fixed height, so where your stage is on the
/// page is simply counted, never guessed.
const double _kTop = 96, _kZone = 76, _kStop = 104;
const _zoneColours = [Color(0xFF4CB782), Color(0xFFE8A52A), Color(0xFF9B7BEA), Color(0xFF2BB3B1), Color(0xFF5B8DEF), Color(0xFFD97757)];

/// A zone's look: sky colours (day / night), hill colour and what stands along the road.
class _Scene {
  const _Scene(this.sky, this.skyDark, this.hill, this.things);
  final List<Color> sky, skyDark;
  final Color hill;
  final List<String> things;
}

const _scenes = {
  'park': _Scene([Color(0xFFDFF5E3), Color(0xFFF4FBF2)], [Color(0xFF16261B), Color(0xFF1B2A1F)], Color(0xFF8FD19E), ['🌳', '🌼', '🦆', '🌷', '🦋', '🌲', '⛲']),
  'market': _Scene([Color(0xFFFFEBD2), Color(0xFFFFF7EC)], [Color(0xFF2B2216), Color(0xFF261F17)], Color(0xFFF2BE7A), ['🍎', '🧺', '🥖', '🍉', '⛺', '🧀', '🍋']),
  'library': _Scene([Color(0xFFEDE6FB), Color(0xFFF8F5FE)], [Color(0xFF221D2E), Color(0xFF1F1B27)], Color(0xFFC3B2EE), ['📚', '🕯️', '📜', '🖋️', '🪑', '📖', '🦉']),
  'seaside': _Scene([Color(0xFFD5F4F6), Color(0xFFF1FBFC)], [Color(0xFF13262A), Color(0xFF162427)], Color(0xFF8CD9DC), ['🌴', '🐚', '⛱️', '🦀', '🌊', '⛵', '🐬']),
  'airport': _Scene([Color(0xFFDDE8FD), Color(0xFFF3F7FF)], [Color(0xFF161E2D), Color(0xFF1A2130)], Color(0xFFA9C2F4), ['✈️', '🧳', '🛫', '☁️', '🗺️', '🛬', '🎫']),
  'london': _Scene([Color(0xFFFBE2DA), Color(0xFFFFF4F0)], [Color(0xFF2B1C18), Color(0xFF261B18)], Color(0xFFEFB3A1), ['🚌', '☂️', '🏰', '💂', '🫖', '🌉', '🕰️']),
  'university': _Scene([Color(0xFFE2ECFA), Color(0xFFF5F8FD)], [Color(0xFF18202B), Color(0xFF1B222C)], Color(0xFFB1C8EA), ['🎓', '🏛️', '🔬', '📐', '🧪', '🎒', '🌐']),
  'centre': _Scene([Color(0xFFFFF0CF), Color(0xFFFFF9EA)], [Color(0xFF2A2412), Color(0xFF262113)], Color(0xFFF1CF7C), ['🏆', '⭐', '🎯', '📝', '🥇', '🎉', '✨']),
};
const _defaultScene = _Scene([Color(0xFFE8F0EA), Color(0xFFF7FAF7)], [Color(0xFF1C221D), Color(0xFF1E231F)], Color(0xFFB9D7BF), ['🌳', '⭐', '🌼']);
_Scene _sceneOf(Map zone) => _scenes['${zone['scene']}'] ?? _defaultScene;

/// x position (0..1 of the width) of the k-th stop of a zone: the road swings left and right.
double _swing(int k) => .5 + sin(k * pi / 3) * .26;

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
  int _topZone = 0;                // the zone whose stops fill the top of the screen
  final List<(int, int)> _meta = [];   // for each row: its zone's number on the page, its place in the zone
  final List<Map> _zoneOfRow = [];

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
    _zoneOfRow.clear();
    _hereRow = -1;
    var zi = 0;
    for (final z in (widget.map['zones'] as List).cast<Map>()) {
      _rows.add(z);
      _meta.add((zi, 0));
      _zoneOfRow.add(z);
      var k = 0;
      for (final st in (z['stages'] as List).cast<Map>()) {
        if (_hereRow < 0 && st['status'] == 'open') _hereRow = _rows.length;
        _rows.add(st);
        _meta.add((zi, k++));
        _zoneOfRow.add(z);
      }
      zi++;
    }
  }

  double _offsetOf(int row) {
    var y = 0.0;
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
    if (!_scroll.hasClients) return;
    final from = _scroll.offset, to = from + _scroll.position.viewportDimension;
    var away = 0;
    if (_hereRow >= 0) {
      final top = _offsetOf(_hereRow), bottom = top + _kStop;      // measured from the foot of the map
      away = bottom < from ? 1 : top > to ? -1 : 0;                // above the screen = scroll up
    }
    // the zone of the row at the top edge of the screen
    var zone = 0, y = 0.0;
    for (var i = 0; i < _rows.length; i++) {
      final h = (_rows[i] as Map).containsKey('stages') ? _kZone : _kStop;
      if (y + h > to - 1) { zone = _meta[i].$1; break; }
      y += h;
      zone = _meta[i].$1;
    }
    if ((away != _away || zone != _topZone) && mounted) setState(() { _away = away; _topZone = zone; });
  }

  @override
  Widget build(BuildContext context) {
    final map = widget.map;
    final zones = (map['zones'] as List).cast<Map>();
    final zone = zones.isEmpty ? null : zones[_topZone.clamp(0, zones.length - 1)].cast<String, dynamic>();
    return Column(children: [
      SizedBox(height: _kTop, child: _Summary(map: map)),
      if (zone != null)
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: SizedBox(key: ValueKey(_topZone), height: _kZone,
              child: _ZoneBanner(zone: zone, colour: _zoneColours[_topZone % _zoneColours.length])),
        ),
      Expanded(
        child: Stack(children: [
          ListView.builder(
            controller: _scroll,
            reverse: true,                         // the road starts at the foot and climbs
            padding: const EdgeInsets.only(top: 24, bottom: 8),
            itemCount: _rows.length,
            itemBuilder: (context, i) {
              final row = _rows[i] as Map;
              final (zi, k) = _meta[i];
              final c = _zoneColours[zi % _zoneColours.length];
              final zone = _zoneOfRow[i];
              if (row.containsKey('stages')) {
                return SizedBox(height: _kZone, child: _ZoneBanner(zone: row.cast<String, dynamic>(), colour: c));
              }
              final last = k == (zone['stages'] as List).length - 1;
              return SizedBox(
                height: _kStop,
                child: _Stop(stage: row.cast<String, dynamic>(), colour: c, index: k, last: last, scene: _sceneOf(zone), onDone: widget.reload),
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
                  tooltip: tr('Back to my stage'),
                  onPressed: _goHere,
                  child: Icon(_away < 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded),
                ),
              ),
            ),
        ]),
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
  Widget build(BuildContext context) {
    final scene = _sceneOf(zone);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: dark ? scene.skyDark : scene.sky)),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [colour, Color.lerp(colour, Colors.black, .18)!]),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: colour.withValues(alpha: .45), offset: const Offset(0, 5))],
        ),
        child: Row(children: [
          Container(
            width: 38, height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .25), shape: BoxShape.circle),
            child: Text('${zone['number']}', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text('${zone['place'] ?? zone['id']}', overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: -.2))),
          Text(scene.things.first, style: const TextStyle(fontSize: 26)),
        ]),
      ),
    );
  }
}

/// The scenery behind one stop: the zone's sky, a soft hill and two things beside the road, then the
/// road itself (a wide band with a dashed centre line) running from the stop above to the one below.
class _ScenePainter extends CustomPainter {
  _ScenePainter({required this.index, required this.last, required this.scene, required this.dark, required this.road});
  final int index;
  final bool last;
  final _Scene scene;
  final bool dark;
  final Color road;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // sky
    canvas.drawRect(Offset.zero & size, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: dark ? scene.skyDark : scene.sky).createShader(Offset.zero & size));
    // a hill on the side away from the road
    final side = _swing(index) > .5 ? -1.0 : 1.0;
    final hx = side < 0 ? w * .12 : w * .88;
    canvas.drawOval(Rect.fromCenter(center: Offset(hx, h * .95), width: w * .55, height: h * .7),
        Paint()..color = scene.hill.withValues(alpha: dark ? .16 : .45));
    // the road: from the middle of the row's top edge (between the stop above and this one) through this stop
    final x = _swing(index) * w, cy = h / 2 - 8;
    // the road climbs: from the stop below (the one before) up to the one above (the next)
    final xBottom = index == 0 ? x : (_swing(index - 1) * w + x) / 2;
    final xTop = (x + _swing(index + 1) * w) / 2;
    final path = Path()..moveTo(xBottom, index == 0 ? cy : h)..quadraticBezierTo(x, cy + (h - cy) * .5, x, cy);
    if (!last) path.quadraticBezierTo(x, cy * .5, xTop, 0);
    canvas.drawPath(path, Paint()..color = road..strokeWidth = 30..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);
    // dashed centre line
    final dash = Paint()..color = Colors.white.withValues(alpha: dark ? .25 : .8)..strokeWidth = 3..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    for (final m in path.computeMetrics()) {
      for (double d = 4; d < m.length; d += 16) {
        canvas.drawPath(m.extractPath(d, min(d + 7, m.length)), dash);
      }
    }
  }

  @override
  bool shouldRepaint(_ScenePainter old) => old.index != index || old.dark != dark || old.scene != scene || old.last != last;
}

/// One stop on the road: a raised round button (done: gold with stars; yours: big, with a "Start here"
/// card; ahead: locked), with the zone's things standing beside the road.
class _Stop extends StatelessWidget {
  const _Stop({required this.stage, required this.colour, required this.index, required this.last, required this.scene, required this.onDone});
  final Map<String, dynamic> stage;
  final Color colour;
  final int index;
  final bool last;
  final _Scene scene;
  final Future<void> Function() onDone;

  @override
  Widget build(BuildContext context) {
    final status = stage['status'];
    final locked = status == 'locked', done = status == 'done', here = status == 'open';
    final stars = (stage['stars'] as num?)?.toInt() ?? 0;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final top = locked ? (dark ? const Color(0xFF4A4A4A) : const Color(0xFFD9D5CB)) : done ? C.gold : colour;
    final under = Color.lerp(top, Colors.black, .28)!;
    final size = here ? 76.0 : 64.0;
    final road = dark ? const Color(0xFF3A3530) : const Color(0xFFE9DFC9);
    final thingLeft = scene.things[(index * 2 + 1) % scene.things.length];
    final thingRight = scene.things[(index * 2 + 2) % scene.things.length];
    return RepaintBoundary(
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth;
        final x = _swing(index) * w - size / 2;
        final roadOnRight = _swing(index) > .5;
        return CustomPaint(
          painter: _ScenePainter(index: index, last: last, scene: scene, dark: dark, road: road),
          child: Stack(clipBehavior: Clip.none, children: [
            // things beside the road (on the side the road is not)
            Positioned(left: roadOnRight ? w * .1 : null, right: roadOnRight ? null : w * .1, top: 14,
                child: Text(index.isEven ? thingLeft : thingRight, style: TextStyle(fontSize: 30, color: dark ? Colors.white.withValues(alpha: .85) : null))),
            if (index % 3 == 1)
              Positioned(left: roadOnRight ? w * .3 : null, right: roadOnRight ? null : w * .3, bottom: 6,
                  child: Text(thingRight, style: const TextStyle(fontSize: 18))),
            Positioned(
              left: x, top: (_kStop - size) / 2 - 12,
              child: GestureDetector(
                onTap: locked ? null : () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => StageScreen(stageId: '${stage['id']}', title: '${stage['title']}')));
                  onDone();
                },
                child: Column(children: [
                  // a raised button: the darker rim underneath shows as its side
                  Container(
                    width: size, height: size + 7,
                    alignment: Alignment.topCenter,
                    decoration: BoxDecoration(color: under, borderRadius: BorderRadius.circular(size)),
                    child: Container(
                      width: size, height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(center: const Alignment(-.3, -.4), radius: .9,
                            colors: [Color.lerp(top, Colors.white, .22)!, top]),
                        border: here ? Border.all(color: Colors.white, width: 4) : null,
                      ),
                      child: Icon(locked ? Icons.lock_rounded : done ? Icons.check_rounded : Icons.play_arrow_rounded,
                          color: locked ? (dark ? Colors.white38 : Colors.black38) : Colors.white, size: here ? 40 : 32),
                    ),
                  ),
                  if (done)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      for (var i = 0; i < 3; i++) Icon(i < stars ? Icons.star_rounded : Icons.star_border_rounded, color: C.gold, size: 16),
                    ]),
                ]),
              ),
            ),
            if (here)
              Positioned(
                left: roadOnRight ? 14 : null, right: roadOnRight ? null : 14, top: _kStop / 2 - 34,
                child: Container(
                  constraints: BoxConstraints(maxWidth: w * .38),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(14),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))]),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(tr('START HERE'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: .6, color: colour)),
                    Text('${stage['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
          ]),
        );
      }),
    );
  }
}
