// The word games, in the app: Word match, Word Rush, Duel (vs a Mockfy bot), Scramble, Collocation Match,
// Synonym Ladder and Listening Spell, plus the My words review. Hudi reacts to every answer.
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../desktop_shell.dart';
import '../api.dart';
import '../prefs.dart';
import '../theme.dart';
import '../widgets.dart';

const _games = [
  ('match', 'Word match', 'Pick the word for its meaning.', Icons.extension_rounded, C.accent),
  ('rush', 'Word Rush', 'As many as you can in 60 seconds.', Icons.bolt_rounded, C.gold),
  ('duel', 'Duel', 'Race a Mockfy bot to ten words.', Icons.sports_mma_rounded, C.red),
  ('scramble', 'Scramble', 'Put the letters back in order.', Icons.shuffle_rounded, C.blue),
  ('collocations', 'Collocation Match', 'Join the words that go together.', Icons.link_rounded, C.green),
  ('ladder', 'Synonym Ladder', 'Climb from a plain word to a strong one.', Icons.stairs_rounded, Color(0xFF9B7BEA)),
  ('spell', 'Listening Spell', 'Hear the word, then spell it.', Icons.hearing_rounded, C.blue),
];

/// The games: today's quest (three different games with 10 or more, then crystals to claim), My words,
/// and every game with your best score. Comes back up to date after each game.
class GamesScreen extends StatefulWidget {
  const GamesScreen({super.key});
  @override
  State<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends State<GamesScreen> {
  Key _k = UniqueKey();

  Future<void> _claim() async {
    try {
      final r = await Api.I.post('/api/games/quest/claim');
      Sfx.play('win');
      if (mounted) toast(context, '+${r['reward']} crystals for today\'s quest!');
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
    setState(() => _k = UniqueKey());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: rootBar(context, AppBar(title: const Text('Games'))),
      body: Loader<Map<String, dynamic>>(
        key: _k,
        load: () => Api.I.get('/api/app/games'),
        build: (context, d, reload) {
          final quest = ((d['quest'] as Map?) ?? {}).cast<String, dynamic>();
          final best = ((d['games'] as Map?) ?? {}).cast<String, dynamic>();
          final done = (quest['done'] as num?)?.toInt() ?? 0, of = (quest['of'] as num?)?.toInt() ?? 3;
          final ready = done >= of && quest['claimed'] != true;
          return ListView(padding: const EdgeInsets.all(16), children: [
            // today's quest
            Card(
              color: C.gold.withValues(alpha: .12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.flag_circle_rounded, color: C.gold, size: 30),
                    const SizedBox(width: 10),
                    const Expanded(child: Text("Today's quest", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                    Text('+${quest['reward'] ?? 30} 💎', style: const TextStyle(fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 6),
                  Text('Play $of different games with ${quest['score'] ?? 10} or more points.', style: TextStyle(color: Theme.of(context).hintColor)),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(value: of == 0 ? 0 : done / of, color: C.gold, minHeight: 8, borderRadius: BorderRadius.circular(5)),
                  const SizedBox(height: 10),
                  if (quest['claimed'] == true)
                    const Text('Done for today. Come back tomorrow!', style: TextStyle(fontWeight: FontWeight.w700))
                  else if (ready)
                    FilledButton(onPressed: _claim, child: const Text('Claim the reward'))
                  else
                    Text('$done of $of games', style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              color: C.green.withValues(alpha: .12),
              child: ListTile(
                leading: const Icon(Icons.style_rounded, color: C.green),
                title: const Text('My words', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Review the words you saved, a few each day'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WordsReviewScreen())),
              ),
            ),
            const SizedBox(height: 12),
            for (final g in _games)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    leading: Container(
                      width: 46, height: 46,
                      decoration: BoxDecoration(color: g.$5.withValues(alpha: .15), borderRadius: BorderRadius.circular(12)),
                      child: Icon(g.$4, color: g.$5),
                    ),
                    title: Row(children: [
                      Flexible(child: Text(g.$2, style: const TextStyle(fontWeight: FontWeight.w700))),
                      if (d['today'] == g.$1) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: C.accent, borderRadius: BorderRadius.circular(6)),
                          child: const Text('TODAY', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ]),
                    subtitle: Text(best[g.$1] is Map && ((best[g.$1] as Map)['best'] ?? 0) > 0
                        ? 'Best ${(best[g.$1] as Map)['best']}${(best[g.$1] as Map)['rank'] != null ? ' · #${(best[g.$1] as Map)['rank']} this week' : ''}'
                        : g.$3),
                    trailing: const Icon(Icons.play_circle_fill_rounded, color: C.accent, size: 30),
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => _gameFor(g.$1, g.$2)));
                      setState(() => _k = UniqueKey());                 // the quest and bests, after the game
                    },
                  ),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

Widget _gameFor(String id, String title) => switch (id) {
      'rush' => WordGame(game: 'rush', title: title, seconds: 60),
      'duel' => WordGame(game: 'duel', title: title, duel: true),
      'scramble' => ScrambleGame(title: title),
      'collocations' => CollocationGame(title: title),
      'ladder' => LadderGame(title: title),
      'spell' => SpellGame(title: title),
      _ => WordGame(game: 'match', title: title),
    };

// ---------------------------------------------------------------- Hudi, reacting
class Hudi extends StatefulWidget {
  const Hudi({super.key, required this.mood, this.size = 64});
  final int mood;          // bumps on every answer: >0 right, <0 wrong
  final double size;
  @override
  State<Hudi> createState() => _HudiState();
}

class _HudiState extends State<Hudi> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));

  @override
  void didUpdateWidget(Hudi old) {
    super.didUpdateWidget(old);
    if (old.mood != widget.mood) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final t = _c.value;
          final happy = widget.mood >= 0;
          final dy = happy ? -18 * sin(pi * t) : 0.0;                      // a hop when right
          final dx = happy ? 0.0 : 8 * sin(pi * 6 * t) * (1 - t);         // a shake when wrong
          return Transform.translate(offset: Offset(dx, dy), child: child);
        },
        child: ClipRRect(borderRadius: BorderRadius.circular(widget.size * .25),
            child: Image.asset('assets/icon.png', width: widget.size, height: widget.size)),
      );
}

Future<Map<String, dynamic>?> _saveScore(String game, int score) async {
  try {
    return await Api.I.post('/api/games/score', {'game': game, 'score': score});
  } on ApiError {
    return null;
  }
}

class _GameOver extends StatelessWidget {
  const _GameOver({required this.score, required this.again, this.best, this.line});
  final int score;
  final int? best;
  final String? line;
  final VoidCallback again;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Hudi(mood: 1, size: 96),
            const SizedBox(height: 16),
            Text('$score', style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w900, color: C.accent)),
            Text(line ?? 'points', style: TextStyle(color: Theme.of(context).hintColor, fontSize: 16)),
            if (best != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Your best: $best')),
            const SizedBox(height: 24),
            FilledButton(onPressed: again, child: const Text('Play again')),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Back to games')),
          ]),
        ),
      );
}

Widget _choice(BuildContext context, String label, {bool? right, VoidCallback? onTap}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final fill = right == null
      ? (dark ? Colors.white.withValues(alpha: .07) : const Color(0xFF141413).withValues(alpha: .05))
      : (right ? C.green : C.red).withValues(alpha: dark ? .32 : .18);
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: fill,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 54),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------- Word match / Rush / Duel
class WordGame extends StatefulWidget {
  const WordGame({super.key, required this.game, required this.title, this.seconds, this.duel = false});
  final String game;
  final String title;
  final int? seconds;
  final bool duel;
  @override
  State<WordGame> createState() => _WordGameState();
}

class _WordGameState extends State<WordGame> {
  List<Map> _items = [];
  int _i = 0, _score = 0, _mood = 0, _left = 0, _bot = 0;
  String? _picked;
  bool _loading = true, _over = false;
  int? _best;
  Timer? _t;
  Map? _opponent;
  final _rnd = Random();

  int get _goal => widget.duel ? 10 : (widget.seconds != null ? 1 << 20 : 10);

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    _t?.cancel();
    setState(() { _loading = true; _over = false; _i = 0; _score = 0; _bot = 0; _picked = null; _best = null; });
    try {
      final r = await Api.I.get('/api/games/words', {'n': widget.seconds != null ? 40 : 12});
      _items = (r['items'] as List).cast<Map>().where((m) => m['options'] is List).toList();
      if (widget.duel) _opponent = (await Api.I.get('/api/games/duel'))['opponent'] as Map?;
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
    if (!mounted) return;
    setState(() => _loading = false);
    if (widget.seconds != null) {
      _left = widget.seconds!;
      _t = Timer.periodic(const Duration(seconds: 1), (t) {
        setState(() => _left--);
        if (_left <= 0) _finish();
      });
    }
    if (widget.duel) {
      // the bot answers at its own pace and gets some wrong
      final speed = ((_opponent?['speed'] as num?) ?? 4).toDouble();
      final acc = ((_opponent?['accuracy'] as num?) ?? .7).toDouble();
      _t = Timer.periodic(Duration(milliseconds: (speed * 1000).round()), (t) {
        if (_over) return;
        if (_rnd.nextDouble() < acc) setState(() => _bot++);
        if (_bot >= _goal) _finish();
      });
    }
  }

  Future<void> _finish() async {
    if (_over) return;
    _t?.cancel();
    setState(() => _over = true);
    if (widget.game == 'match') { Sfx.play('win'); return; }
    final won = !widget.duel || _score >= _goal;
    if (won) Sfx.play('win');
    if (widget.duel && won) { try { await Api.I.post('/api/games/duel/win'); } on ApiError catch (_) {} }
    final r = await _saveScore(widget.game, widget.duel ? _score * 10 : _score);
    if (mounted && r != null) setState(() => _best = (r['best'] as num?)?.toInt());
  }

  void _pick(String opt) {
    if (_picked != null || _over) return;
    final it = _items[_i];
    final right = opt.toLowerCase() == '${it['word']}'.toLowerCase();
    setState(() { _picked = opt; _mood = right ? _mood.abs() + 1 : -(_mood.abs() + 1); if (right) _score += widget.seconds != null ? 10 : 1; });
    Sfx.play(right ? 'right' : 'error');
    Api.I.post('/api/games/words/answer', {'game': widget.game, 'word': it['word'], 'picked': opt, if (it['id'] != null) 'id': it['id']})
        .catchError((_) => <String, dynamic>{});
    Future.delayed(Duration(milliseconds: right ? 450 : 900), () {
      if (!mounted || _over) return;
      if ((!widget.duel && widget.seconds == null && _i + 1 >= min(_goal, _items.length)) || (widget.duel && _score >= _goal) || _i + 1 >= _items.length) {
        _finish();
        return;
      }
      setState(() { _i++; _picked = null; });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), actions: [
        if (widget.seconds != null && !_over && !_loading)
          Center(child: Padding(padding: const EdgeInsets.only(right: 16),
              child: Text('$_left s', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: _left <= 10 ? C.red : null)))),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _over || _items.isEmpty
              ? _GameOver(score: widget.duel ? _score * 10 : _score, best: _best, again: _start,
                  line: widget.duel ? (_score >= _goal ? 'You beat ${_opponent?['name'] ?? 'the bot'}!' : '${_opponent?['name'] ?? 'The bot'} won this time') : null)
              : _question(context),
    );
  }

  Widget _question(BuildContext context) {
    final it = _items[_i];
    final opts = (it['options'] as List).cast<String>();
    return ListView(padding: const EdgeInsets.all(20), children: [
      Row(children: [
        Hudi(mood: _mood, size: 56),
        const SizedBox(width: 12),
        Expanded(child: Text(widget.duel ? 'You $_score · ${_opponent?['name'] ?? 'Bot'} $_bot' : 'Score $_score',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
        if (widget.seconds == null) Text('${_i + 1}/${min(_goal, _items.length)}', style: TextStyle(color: Theme.of(context).hintColor)),
      ]),
      if (widget.duel) ...[
        const SizedBox(height: 10),
        LinearProgressIndicator(value: _score / _goal, color: C.accent, minHeight: 6, borderRadius: BorderRadius.circular(4)),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: _bot / _goal, color: C.red, minHeight: 6, borderRadius: BorderRadius.circular(4)),
      ],
      const SizedBox(height: 22),
      Text('${it['definition']}', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, height: 1.35)),
      if ('${it['pos'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${it['pos']}', style: TextStyle(color: Theme.of(context).hintColor))),
      const SizedBox(height: 20),
      for (final o in opts)
        _choice(context, o,
            right: _picked == null ? null : (o.toLowerCase() == '${it['word']}'.toLowerCase() ? true : (o == _picked ? false : null)),
            onTap: () => _pick(o)),
    ]);
  }
}

// ---------------------------------------------------------------- Scramble
class ScrambleGame extends StatefulWidget {
  const ScrambleGame({super.key, required this.title});
  final String title;
  @override
  State<ScrambleGame> createState() => _ScrambleGameState();
}

class _ScrambleGameState extends State<ScrambleGame> {
  List<Map> _words = [];
  int _i = 0, _score = 0, _mood = 0;
  List<int> _order = [];
  final List<int> _built = [];
  bool _loading = true, _over = false, _wrong = false;
  int? _best;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() { _loading = true; _over = false; _i = 0; _score = 0; _best = null; });
    try {
      final r = await Api.I.get('/api/games/words', {'n': 20});
      _words = (r['items'] as List).cast<Map>().where((m) => RegExp(r'^[a-zA-Z]{3,10}$').hasMatch('${m['word']}')).take(10).toList();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
    _next(first: true);
    if (mounted) setState(() => _loading = false);
  }

  void _next({bool first = false}) {
    if (!first) _i++;
    if (_i >= _words.length) { _finish(); return; }
    final w = '${_words[_i]['word']}';
    _order = List.generate(w.length, (k) => k)..shuffle();
    if (_order.join() == List.generate(w.length, (k) => k).join() && w.length > 1) _order = _order.reversed.toList();
    _built.clear();
    _wrong = false;
    setState(() {});
  }

  Future<void> _finish() async {
    setState(() => _over = true);
    Sfx.play('win');
    final r = await _saveScore('scramble', _score);
    if (mounted && r != null) setState(() => _best = (r['best'] as num?)?.toInt());
  }

  void _tap(int letterIndex) {
    final w = '${_words[_i]['word']}';
    setState(() { _built.add(letterIndex); _wrong = false; });
    if (_built.length == w.length) {
      final guess = _built.map((k) => w[k]).join();
      final right = guess.toLowerCase() == w.toLowerCase();
      Sfx.play(right ? 'right' : 'error');
      setState(() { _mood = right ? _mood.abs() + 1 : -(_mood.abs() + 1); _wrong = !right; if (right) _score += 10; });
      if (right) { Future.delayed(const Duration(milliseconds: 500), () { if (mounted) _next(); }); }
      else { Future.delayed(const Duration(milliseconds: 700), () { if (mounted) setState(() { _built.clear(); _wrong = false; }); }); }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _over || _words.isEmpty
              ? _GameOver(score: _score, best: _best, again: _start)
              : ListView(padding: const EdgeInsets.all(20), children: [
                  Row(children: [Hudi(mood: _mood, size: 56), const SizedBox(width: 12),
                    Text('Score $_score', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), const Spacer(),
                    Text('${_i + 1}/${_words.length}', style: TextStyle(color: Theme.of(context).hintColor))]),
                  const SizedBox(height: 22),
                  Text('${_words[_i]['definition']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.35)),
                  const SizedBox(height: 22),
                  Container(
                    height: 60,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: (_wrong ? C.red : C.accent).withValues(alpha: .12),
                    ),
                    child: Text(_built.map((k) => '${_words[_i]['word']}'[k]).join().toUpperCase(),
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 4)),
                  ),
                  const SizedBox(height: 22),
                  Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: [
                    for (final k in _order)
                      AnimatedOpacity(
                        opacity: _built.contains(k) ? .2 : 1,
                        duration: const Duration(milliseconds: 150),
                        child: Material(
                          color: C.accent,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: _built.contains(k) ? null : () => _tap(k),
                            child: SizedBox(width: 48, height: 52, child: Center(child: Text('${_words[_i]['word']}'[k].toUpperCase(),
                                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)))),
                          ),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 18),
                  TextButton(onPressed: () => setState(() => _built.clear()), child: const Text('Clear')),
                  TextButton(onPressed: () => _next(), child: const Text('Skip')),
                ]),
    );
  }
}

// ---------------------------------------------------------------- Collocation Match
class CollocationGame extends StatefulWidget {
  const CollocationGame({super.key, required this.title});
  final String title;
  @override
  State<CollocationGame> createState() => _CollocationGameState();
}

class _CollocationGameState extends State<CollocationGame> {
  List<Map> _rounds = [];
  int _r = 0, _score = 0, _mood = 0;
  List<String> _left = [], _right = [];
  final Set<String> _done = {};
  String? _a;
  bool _loading = true, _over = false;
  int? _best;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() { _loading = true; _over = false; _r = 0; _score = 0; _best = null; });
    try {
      _rounds = ((await Api.I.get('/api/games/collocations'))['rounds'] as List).cast<Map>();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
    _round();
    if (mounted) setState(() => _loading = false);
  }

  void _round() {
    if (_r >= _rounds.length) { _finish(); return; }
    final pairs = (_rounds[_r]['pairs'] as List).cast<Map>();
    _left = pairs.map((p) => '${p['a']}').toList()..shuffle();
    _right = pairs.map((p) => '${p['b']}').toList()..shuffle();
    _done.clear();
    _a = null;
    setState(() {});
  }

  Future<void> _finish() async {
    setState(() => _over = true);
    Sfx.play('win');
    final r = await _saveScore('collocations', _score);
    if (mounted && r != null) setState(() => _best = (r['best'] as num?)?.toInt());
  }

  void _pickB(String b) {
    if (_a == null) return;
    final ok = ((_rounds[_r]['ok'] as List?) ?? []).contains('$_a|$b');
    Sfx.play(ok ? 'right' : 'error');
    setState(() {
      _mood = ok ? _mood.abs() + 1 : -(_mood.abs() + 1);
      if (ok) { _done..add('a:$_a')..add('b:$b'); _score += 10; }
      _a = null;
    });
    if (_done.length == _left.length * 2) {
      Future.delayed(const Duration(milliseconds: 500), () { if (mounted) { _r++; _round(); } });
    }
  }

  Widget _cell(String text, {required bool done, required bool selected, VoidCallback? onTap}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: AnimatedOpacity(
          opacity: done ? .25 : 1,
          duration: const Duration(milliseconds: 200),
          child: Material(
            color: selected ? C.accent.withValues(alpha: .3) : (done ? C.green.withValues(alpha: .2) : Theme.of(context).colorScheme.surface),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: done ? null : onTap,
              child: Container(height: 54, alignment: Alignment.center, padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _over || _rounds.isEmpty
              ? _GameOver(score: _score, best: _best, again: _start)
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Row(children: [Hudi(mood: _mood, size: 52), const SizedBox(width: 12),
                    Text('Score $_score', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), const Spacer(),
                    Text('Round ${_r + 1}/${_rounds.length}', style: TextStyle(color: Theme.of(context).hintColor))]),
                  const SizedBox(height: 16),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Column(children: [
                      for (final a in _left) _cell(a, done: _done.contains('a:$a'), selected: _a == a, onTap: () => setState(() => _a = a)),
                    ])),
                    const SizedBox(width: 12),
                    Expanded(child: Column(children: [
                      for (final b in _right) _cell(b, done: _done.contains('b:$b'), selected: false, onTap: () => _pickB(b)),
                    ])),
                  ]),
                ]),
    );
  }
}

// ---------------------------------------------------------------- Synonym Ladder
class LadderGame extends StatefulWidget {
  const LadderGame({super.key, required this.title});
  final String title;
  @override
  State<LadderGame> createState() => _LadderGameState();
}

class _LadderGameState extends State<LadderGame> {
  List<Map> _ladders = [];
  int _l = 0, _step = 0, _score = 0, _mood = 0;
  String? _picked;
  bool _loading = true, _over = false;
  int? _best;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() { _loading = true; _over = false; _l = 0; _step = 0; _score = 0; _best = null; _picked = null; });
    try {
      _ladders = ((await Api.I.get('/api/games/ladders'))['ladders'] as List).cast<Map>().take(6).toList();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _finish() async {
    setState(() => _over = true);
    Sfx.play('win');
    final r = await _saveScore('ladder', _score);
    if (mounted && r != null) setState(() => _best = (r['best'] as num?)?.toInt());
  }

  void _pick(String o) {
    if (_picked != null) return;
    final steps = (_ladders[_l]['steps'] as List).cast<Map>();
    final right = o == '${steps[_step]['answer']}';
    Sfx.play(right ? 'right' : 'error');
    setState(() { _picked = o; _mood = right ? _mood.abs() + 1 : -(_mood.abs() + 1); if (right) _score += 10; });
    Future.delayed(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      setState(() {
        _picked = null;
        if (_step + 1 < steps.length) { _step++; } else { _step = 0; _l++; }
      });
      if (_l >= _ladders.length) _finish();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(appBar: AppBar(title: Text(widget.title)), body: const Center(child: CircularProgressIndicator()));
    if (_over || _ladders.isEmpty || _l >= _ladders.length) {
      return Scaffold(appBar: AppBar(title: Text(widget.title)), body: _GameOver(score: _score, best: _best, again: _start));
    }
    final lad = _ladders[_l];
    final words = (lad['words'] as List).cast<String>();
    final steps = (lad['steps'] as List).cast<Map>();
    final st = steps[_step];
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Row(children: [
          Text('Score $_score', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), const Spacer(),
          Text('Ladder ${_l + 1}/${_ladders.length}', style: TextStyle(color: Theme.of(context).hintColor)),
        ]),
        const SizedBox(height: 16),
        // the ladder: Hudi stands on the rung being climbed
        for (var k = words.length - 1; k >= 0; k--)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              SizedBox(width: 60, child: k == _step ? Hudi(mood: _mood, size: 44) : null),
              Expanded(
                child: Container(
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: k <= _step ? C.green.withValues(alpha: .2) : Theme.of(context).colorScheme.surface,
                  ),
                  child: Text(k <= _step ? words[k] : '?', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ),
        const SizedBox(height: 16),
        Text('A stronger word for "${words[_step]}":', style: TextStyle(color: Theme.of(context).hintColor)),
        const SizedBox(height: 10),
        for (final o in (st['options'] as List).cast<String>())
          _choice(context, o, right: _picked == null ? null : (o == '${st['answer']}' ? true : (o == _picked ? false : null)), onTap: () => _pick(o)),
      ]),
    );
  }
}

// ---------------------------------------------------------------- Listening Spell
class SpellGame extends StatefulWidget {
  const SpellGame({super.key, required this.title});
  final String title;
  @override
  State<SpellGame> createState() => _SpellGameState();
}

class _SpellGameState extends State<SpellGame> {
  final _player = AudioPlayer();
  final _in = TextEditingController();
  List<Map> _words = [];
  int _i = 0, _score = 0, _mood = 0;
  bool _loading = true, _over = false;
  bool? _right;
  int? _best;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _player.dispose();
    _in.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() { _loading = true; _over = false; _i = 0; _score = 0; _best = null; _right = null; });
    try {
      final r = await Api.I.get('/api/games/words', {'n': 20});
      _words = (r['items'] as List).cast<Map>().where((m) => RegExp(r'^[a-zA-Z]{3,12}$').hasMatch('${m['word']}')).take(10).toList();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
    if (mounted) setState(() => _loading = false);
    _say();
  }

  Future<void> _say({bool sentence = false}) async {
    if (_i >= _words.length) return;
    try {
      await _player.setUrl('$kBaseUrl/static/audio/words/${Uri.encodeComponent('${_words[_i]['word']}')}${sentence ? '.s' : ''}.mp3');
      await _player.play();
    } catch (_) {
      if (mounted) toast(context, 'Could not play the word. Check your connection.');
    }
  }

  Future<void> _check() async {
    if (_right != null || _in.text.trim().isEmpty) return;
    final right = _in.text.trim().toLowerCase() == '${_words[_i]['word']}'.toLowerCase();
    Sfx.play(right ? 'right' : 'error');
    setState(() { _right = right; _mood = right ? _mood.abs() + 1 : -(_mood.abs() + 1); if (right) _score += 10; });
    await Future.delayed(Duration(milliseconds: right ? 600 : 1400));
    if (!mounted) return;
    if (_i + 1 >= _words.length) {
      setState(() => _over = true);
      Sfx.play('win');
      final r = await _saveScore('spell', _score);
      if (mounted && r != null) setState(() => _best = (r['best'] as num?)?.toInt());
      return;
    }
    setState(() { _i++; _right = null; _in.clear(); });
    _say();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _over || _words.isEmpty
              ? _GameOver(score: _score, best: _best, again: _start)
              : ListView(padding: const EdgeInsets.all(20), children: [
                  Row(children: [Hudi(mood: _mood, size: 56), const SizedBox(width: 12),
                    Text('Score $_score', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), const Spacer(),
                    Text('${_i + 1}/${_words.length}', style: TextStyle(color: Theme.of(context).hintColor))]),
                  const SizedBox(height: 28),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    IconButton.filled(iconSize: 40, onPressed: _say, icon: const Icon(Icons.volume_up_rounded)),
                    const SizedBox(width: 16),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                      onPressed: () => _say(sentence: true),
                      icon: const Icon(Icons.short_text_rounded),
                      label: const Text('In a sentence'),
                    ),
                  ]),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _in,
                    autocorrect: false,
                    enableSuggestions: false,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                    onSubmitted: (_) => _check(),
                    decoration: InputDecoration(
                      hintText: 'Type the word',
                      filled: true,
                      fillColor: _right == null ? null : (_right! ? C.green : C.red).withValues(alpha: .18),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                  if (_right == false)
                    Padding(padding: const EdgeInsets.only(top: 10), child: Text('It is "${_words[_i]['word']}"',
                        textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
                  const SizedBox(height: 18),
                  FilledButton(onPressed: _check, child: const Text('Check')),
                ]),
    );
  }
}

// ---------------------------------------------------------------- My words (saved words, spaced review)
class WordsReviewScreen extends StatefulWidget {
  const WordsReviewScreen({super.key});
  @override
  State<WordsReviewScreen> createState() => _WordsReviewScreenState();
}

class _WordsReviewScreenState extends State<WordsReviewScreen> {
  List<Map> _items = [];
  Map<String, dynamic>? _data;
  int _i = 0, _mood = 0;
  String? _picked;
  bool _loading = true, _shown = false;
  final _in = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _data = await Api.I.get('/api/vocab/review');
      _items = ((_data!['items'] as List?) ?? []).cast<Map>();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
    if (mounted) setState(() { _loading = false; _i = 0; });
  }

  Future<void> _answer(bool knew) async {
    final it = _items[_i];
    Sfx.play(knew ? 'right' : 'error');
    setState(() { _shown = true; _mood = knew ? _mood.abs() + 1 : -(_mood.abs() + 1); });
    try { await Api.I.post('/api/vocab/review/${it['id']}', {'knew': knew}); } on ApiError catch (_) {}
  }

  void _next() {
    setState(() { _i++; _picked = null; _shown = false; _in.clear(); });
    if (_i >= _items.length) Sfx.play('win');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: rootBar(context, AppBar(title: const Text('My words'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty || _i >= _items.length
              ? Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Hudi(mood: 1, size: 88),
                  const SizedBox(height: 16),
                  Text(_items.isEmpty ? 'No words to review today.' : 'All done for today!', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text('You have ${_data?['total'] ?? 0} saved words. Tap a word in Reading to save it.',
                      textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).hintColor)),
                ])))
              : _card(context),
    );
  }

  Widget _card(BuildContext context) {
    final it = _items[_i];
    final card = (it['card'] as Map?) ?? {};
    final choose = it['type'] == 'choose';
    return ListView(padding: const EdgeInsets.all(20), children: [
      Row(children: [Hudi(mood: _mood, size: 52), const Spacer(), Text('${_i + 1}/${_items.length}', style: TextStyle(color: Theme.of(context).hintColor))]),
      const SizedBox(height: 20),
      Text('${it['prompt']}', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, height: 1.35)),
      if (!choose && '${it['hint'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${it['hint']}', style: TextStyle(color: Theme.of(context).hintColor))),
      const SizedBox(height: 20),
      if (choose)
        for (final o in (it['options'] as List).cast<String>())
          _choice(context, o,
              right: _picked == null ? null : (o == '${it['answer']}' ? true : (o == _picked ? false : null)),
              onTap: _picked != null ? null : () { setState(() => _picked = o); _answer(o == '${it['answer']}'); })
      else ...[
        TextField(controller: _in, autocorrect: false, enableSuggestions: false, enabled: !_shown,
            decoration: InputDecoration(hintText: 'The missing word', filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)),
            onSubmitted: (v) => _answer(v.trim().toLowerCase() == '${it['answer']}')),
        const SizedBox(height: 12),
        if (!_shown) FilledButton(onPressed: () => _answer(_in.text.trim().toLowerCase() == '${it['answer']}'), child: const Text('Check')),
      ],
      if (_shown) ...[
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${card['word'] ?? it['word']}  ${card['ipa'] ?? ''}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              if ('${card['definition'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${card['definition']}')),
              if ('${card['example'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6),
                  child: Text('${card['example']}', style: const TextStyle(fontStyle: FontStyle.italic))),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: _next, child: const Text('Next')),
      ],
    ]);
  }
}
