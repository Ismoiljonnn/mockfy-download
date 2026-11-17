// The word games, in the app: Word match, Word Rush, Duel (vs a Mockfy bot), Scramble, Collocation Match,
// Synonym Ladder and Listening Spell, plus the My words review. Hudi reacts to every answer.
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../i18n.dart';
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
      appBar: rootBar(context, AppBar(title: Text(tr('Games')))),
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
                    Expanded(child: Text(tr("Today's quest"), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                    Text('+${quest['reward'] ?? 30} 💎', style: const TextStyle(fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 6),
                  Text('Play $of different games with ${quest['score'] ?? 10} or more points.', style: TextStyle(color: Theme.of(context).hintColor)),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(value: of == 0 ? 0 : done / of, color: C.gold, minHeight: 8, borderRadius: BorderRadius.circular(5)),
                  const SizedBox(height: 10),
                  if (quest['claimed'] == true)
                    Text(tr('Done for today. Come back tomorrow!'), style: TextStyle(fontWeight: FontWeight.w700))
                  else if (ready)
                    FilledButton(onPressed: _claim, child: Text(tr('Claim the reward')))
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
                title: Text(tr('My words'), style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(tr('Review the words you saved, a few each day')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WordsBoardScreen())),
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
                          child: Text(tr('TODAY'), style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
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

const _rules = {
  'rush': 'Pick the word for each meaning. As many as you can in 60 seconds.',
  'duel': 'Race a Mockfy bot to ten right answers.',
  'scramble': 'The letters are mixed up. Read the meaning and put the word together. Spelling counts in IELTS Listening and Writing.',
  'collocations': 'Join the words that go together, round after round.',
  'ladder': 'Climb from a plain word to a strong one, one synonym at a time.',
  'spell': 'Hear the word, then spell it. Spelling counts in IELTS Listening.',
};

Widget _gameFor(String id, String title) {
  if (id == 'match') _walletAtStart = _wallet();
  return id == 'match' ? _game(id, title) : GameLobby(game: id, title: title);
}

/// Before a game: the rules on top, this week's leaderboard in the middle (your own row marked), Start.
class GameLobby extends StatelessWidget {
  const GameLobby({super.key, required this.game, required this.title});
  final String game;
  final String title;
  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.all(20), children: [
            const Center(child: Hudi(mood: 0, size: 84)),
            const SizedBox(height: 12),
            Text(tr(_rules[game] ?? ''), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, height: 1.4)),
            const SizedBox(height: 20),
            Text(tr('Leaderboard · this week'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            FutureBuilder<Map<String, dynamic>>(
              future: Api.I.get('/api/games/top', {'game': game}),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return snap.hasError ? const SizedBox.shrink() : const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
                }
                final rows = ((snap.data!['top'] as List?) ?? []).cast<Map>();
                if (rows.isEmpty) return Text(tr('Nobody has played this week yet. Be the first!'), style: TextStyle(color: hint));
                return Card(
                  child: Column(children: [
                    for (var i = 0; i < rows.length; i++)
                      Container(
                        color: rows[i]['me'] == true ? C.accent.withValues(alpha: .12) : null,
                        child: ListTile(
                          dense: true,
                          leading: SizedBox(width: 28, child: Text('${i + 1}', textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.w800, color: i < 3 ? C.gold : hint))),
                          title: Text('${rows[i]['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: rows[i]['username'] != null ? Text('@${rows[i]['username']}') : null,
                          trailing: Text('${rows[i]['score']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    if (snap.data!['best'] != null)
                      Padding(padding: const EdgeInsets.all(12), child: Text(tr('Your best: {n}', {'n': snap.data!['best']}), style: TextStyle(color: hint))),
                  ]),
                );
              },
            ),
          ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  _walletAtStart = _wallet();
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => _game(game, title)));
                },
                child: Text(tr('Start')),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// The endless games end when you press Finish or leave: the score is saved either way, as on the website.
Widget _finishButton(bool show, VoidCallback onFinish) =>
    show ? TextButton(onPressed: onFinish, child: Text(tr('Finish'))) : const SizedBox.shrink();

Widget _game(String id, String title) => switch (id) {
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
  const Hudi({super.key, required this.mood, this.size = 64, this.face});
  final int mood;          // bumps on every answer: >0 right, <0 wrong, 0 waiting
  final double size;
  final String? face;      // a fixed mood: idle, happy, cheer, thinking, sad, sleep
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

  String get _face => widget.face ?? (widget.mood > 0 ? 'happy' : widget.mood < 0 ? 'sad' : 'idle');

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final t = _c.value;
          final happy = widget.mood >= 0;
          final dy = happy ? -16 * sin(pi * t) : 0.0;                      // a hop when right
          final dx = happy ? 0.0 : 7 * sin(pi * 6 * t) * (1 - t);         // a shake when wrong
          return Transform.translate(offset: Offset(dx, dy), child: child);
        },
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Image.asset('assets/hudi/$_face.png', key: ValueKey(_face), width: widget.size, height: widget.size,
              fit: BoxFit.contain, filterQuality: FilterQuality.high),
        ),
      );
}

// What the game earned: points and crystals before it started, compared with after it (combo rewards,
// a won duel, the quest), shown on the game-over screen.
Future<Map<String, num>> _wallet() async {
  try {
    final m = (await Api.I.get('/api/app/me'))['me'] as Map;
    return {'points': (m['points'] as num?) ?? 0, 'crystals': (m['crystals'] as num?) ?? 0};
  } on ApiError {
    return const {};
  }
}

Future<Map<String, num>> _walletAtStart = Future.value(const {});

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
            const Hudi(mood: 1, size: 110, face: 'cheer'),
            const SizedBox(height: 16),
            Text('$score', style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w900, color: C.accent)),
            Text(line ?? 'points', style: TextStyle(color: Theme.of(context).hintColor, fontSize: 16)),
            if (best != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(tr('Your best: {n}', {'n': best}))),
            const SizedBox(height: 16),
            _Earned(key: ValueKey(score)),
            const SizedBox(height: 24),
            FilledButton(onPressed: () { _walletAtStart = _wallet(); again(); }, child: Text(tr('Play again'))),
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Back to games'))),
          ]),
        ),
      );
}

/// "+12 points  +20 crystals": what this game gave (read a moment after it ends, once the server has paid it).
class _Earned extends StatelessWidget {
  const _Earned({super.key});
  Future<Map<String, num>> _diff() async {
    final before = await _walletAtStart;
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final after = await _wallet();
    if (before.isEmpty || after.isEmpty) return const {};
    return {'points': after['points']! - before['points']!, 'crystals': after['crystals']! - before['crystals']!};
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, num>>(
        future: _diff(),
        builder: (context, snap) {
          final d = snap.data;
          if (d == null || d.isEmpty) return const SizedBox(height: 40);
          Widget pill(IconData icon, Color c, String text) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 5),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: c.withValues(alpha: .14), borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, color: c, size: 20),
                  const SizedBox(width: 6),
                  Text(text, style: TextStyle(fontWeight: FontWeight.w800, color: c, fontSize: 16)),
                ]),
              );
          return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            pill(Icons.star_rounded, C.gold, tr('+{n} points', {'n': d['points']!.round()})),
            pill(Icons.diamond_rounded, const Color(0xFF9B7BEA), tr('+{n} crystals', {'n': d['crystals']!.round()})),
          ]);
        },
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

  bool _more = false;
  static bool _ok(Map m) => RegExp(r'^[a-zA-Z]{4,11}$').hasMatch('${m['word']}');

  @override
  void dispose() {
    if (!_over && _score > 0) _saveScore('scramble', _score);   // leaving keeps the score
    super.dispose();
  }

  Future<void> _start() async {
    setState(() { _loading = true; _over = false; _i = 0; _score = 0; _best = null; });
    try {
      final r = await Api.I.get('/api/games/words', {'n': 40});
      _words = (r['items'] as List).cast<Map>().where(_ok).toList();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
    _next(first: true);
    if (mounted) setState(() => _loading = false);
  }

  // endless: more words come before the list runs out
  Future<void> _loadMore() async {
    if (_more || _words.length - _i > 4) return;
    _more = true;
    try {
      final r = await Api.I.get('/api/games/words', {'n': 40});
      final have = _words.map((w) => '${w['word']}').toSet();
      _words.addAll((r['items'] as List).cast<Map>().where((m) => _ok(m) && !have.contains('${m['word']}')));
    } on ApiError { /* try again on the next word */ }
    _more = false;
    if (mounted) setState(() {});
  }

  void _next({bool first = false}) {
    if (!first) _i++;
    _loadMore();
    if (_i >= _words.length) {
      if (_words.isEmpty) { _finish(); return; }
      Future.delayed(const Duration(milliseconds: 400), () { if (mounted && !_over) { _i--; _next(); } });
      return;
    }
    final w = '${_words[_i]['word']}';
    _order = List.generate(w.length, (k) => k)..shuffle();
    if (_order.join() == List.generate(w.length, (k) => k).join() && w.length > 1) _order = _order.reversed.toList();
    _built.clear();
    _wrong = false;
    setState(() {});
  }

  Future<void> _finish() async {
    if (_over) return;
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
      appBar: AppBar(title: Text(widget.title), actions: [_finishButton(!_loading && !_over, _finish)]),
      body: _loading || (!_over && _i >= _words.length && _words.isNotEmpty)
          ? const Center(child: CircularProgressIndicator())
          : _over || _words.isEmpty
              ? _GameOver(score: _score, best: _best, again: _start)
              : ListView(padding: const EdgeInsets.all(20), children: [
                  Row(children: [Hudi(mood: _mood, size: 56), const SizedBox(width: 12),
                    Text(tr('Score {n}', {'n': _score}), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), const Spacer(),
                    Text(tr('{n} words', {'n': _i}), style: TextStyle(color: Theme.of(context).hintColor))]),
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
                      // a used letter fades to an empty outline, so what is left to place is plain to see
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 48, height: 52,
                        decoration: BoxDecoration(
                          color: _built.contains(k) ? Colors.transparent : C.accent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _built.contains(k) ? Theme.of(context).dividerColor : C.accent, width: 1.5),
                        ),
                        child: Material(
                          type: MaterialType.transparency,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: _built.contains(k) ? null : () => _tap(k),
                            child: Center(child: Text('${_words[_i]['word']}'[k].toUpperCase(),
                                style: TextStyle(color: _built.contains(k) ? Theme.of(context).hintColor.withValues(alpha: .35) : Colors.white,
                                    fontSize: 22, fontWeight: FontWeight.w800))),
                          ),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 18),
                  TextButton(onPressed: _built.isEmpty ? null : () => setState(() => _built.removeLast()), child: Text(tr('Undo'))),
                  TextButton(onPressed: () => setState(() => _built.clear()), child: Text(tr('Clear'))),
                  TextButton(onPressed: () => _next(), child: Text(tr('Skip'))),
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

  bool _more = false;

  @override
  void dispose() {
    if (!_over && _score > 0) _saveScore('collocations', _score);
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_more || _rounds.length - _r > 2) return;
    _more = true;
    try {
      _rounds.addAll(((await Api.I.get('/api/games/collocations'))['rounds'] as List).cast<Map>());
    } on ApiError { /* again next round */ }
    _more = false;
  }

  void _round() {
    _loadMore();
    if (_r >= _rounds.length) {
      if (_rounds.isEmpty) { _finish(); return; }
      Future.delayed(const Duration(milliseconds: 400), () { if (mounted && !_over) _round(); });
      return;
    }
    final pairs = (_rounds[_r]['pairs'] as List).cast<Map>();
    _left = pairs.map((p) => '${p['a']}').toList()..shuffle();
    _right = pairs.map((p) => '${p['b']}').toList()..shuffle();
    _done.clear();
    _a = null;
    setState(() {});
  }

  Future<void> _finish() async {
    if (_over) return;
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
      appBar: AppBar(title: Text(widget.title), actions: [_finishButton(!_loading && !_over, _finish)]),
      body: _loading || (!_over && _r >= _rounds.length && _rounds.isNotEmpty)
          ? const Center(child: CircularProgressIndicator())
          : _over || _rounds.isEmpty
              ? _GameOver(score: _score, best: _best, again: _start)
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Row(children: [Hudi(mood: _mood, size: 52), const SizedBox(width: 12),
                    Text(tr('Score {n}', {'n': _score}), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), const Spacer(),
                    Text(tr('Round {n}', {'n': _r + 1}), style: TextStyle(color: Theme.of(context).hintColor))]),
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
      _ladders = ((await Api.I.get('/api/games/ladders'))['ladders'] as List).cast<Map>().toList();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  bool _more = false;

  @override
  void dispose() {
    if (!_over && _score > 0) _saveScore('ladder', _score);
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_more || _ladders.length - _l > 2) return;
    _more = true;
    try {
      _ladders.addAll(((await Api.I.get('/api/games/ladders'))['ladders'] as List).cast<Map>());
    } on ApiError { /* again on the next ladder */ }
    _more = false;
    if (mounted) setState(() {});
  }

  Future<void> _finish() async {
    if (_over) return;
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
      _loadMore();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || (!_over && _l >= _ladders.length && _ladders.isNotEmpty)) {
      return Scaffold(appBar: AppBar(title: Text(widget.title)), body: const Center(child: CircularProgressIndicator()));
    }
    if (_over || _ladders.isEmpty) {
      return Scaffold(appBar: AppBar(title: Text(widget.title)), body: _GameOver(score: _score, best: _best, again: _start));
    }
    final lad = _ladders[_l];
    final words = (lad['words'] as List).cast<String>();
    final steps = (lad['steps'] as List).cast<Map>();
    final st = steps[_step];
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), actions: [_finishButton(true, _finish)]),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Row(children: [
          Text(tr('Score {n}', {'n': _score}), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), const Spacer(),
          Text(tr('{n} ladders', {'n': _l}), style: TextStyle(color: Theme.of(context).hintColor)),
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

  bool _more = false;
  static bool _ok(Map m) => RegExp(r'^[a-zA-Z]{3,12}$').hasMatch('${m['word']}');

  @override
  void dispose() {
    if (!_over && _score > 0) _saveScore('spell', _score);
    _player.dispose();
    _in.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_more || _words.length - _i > 4) return;
    _more = true;
    try {
      final r = await Api.I.get('/api/games/words', {'n': 20});
      final have = _words.map((w) => '${w['word']}').toSet();
      _words.addAll((r['items'] as List).cast<Map>().where((m) => _ok(m) && !have.contains('${m['word']}')));
    } on ApiError { /* again on the next word */ }
    _more = false;
  }

  Future<void> _finish() async {
    if (_over) return;
    setState(() => _over = true);
    Sfx.play('win');
    final r = await _saveScore('spell', _score);
    if (mounted && r != null) setState(() => _best = (r['best'] as num?)?.toInt());
  }

  Future<void> _start() async {
    setState(() { _loading = true; _over = false; _i = 0; _score = 0; _best = null; _right = null; });
    try {
      final r = await Api.I.get('/api/games/words', {'n': 20});
      _words = (r['items'] as List).cast<Map>().where(_ok).toList();
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
      if (mounted) toast(context, tr('Could not play the word. Check your connection.'));
    }
  }

  Future<void> _check() async {
    if (_right != null || _in.text.trim().isEmpty) return;
    final right = _in.text.trim().toLowerCase() == '${_words[_i]['word']}'.toLowerCase();
    Sfx.play(right ? 'right' : 'error');
    setState(() { _right = right; _mood = right ? _mood.abs() + 1 : -(_mood.abs() + 1); if (right) _score += 10; });
    await Future.delayed(Duration(milliseconds: right ? 600 : 1400));
    if (!mounted) return;
    await _loadMore();
    if (!mounted) return;
    if (_i + 1 >= _words.length) { _finish(); return; }
    setState(() { _i++; _right = null; _in.clear(); });
    _say();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), actions: [_finishButton(!_loading && !_over, _finish)]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _over || _words.isEmpty
              ? _GameOver(score: _score, best: _best, again: _start)
              : ListView(padding: const EdgeInsets.all(20), children: [
                  Row(children: [Hudi(mood: _mood, size: 56), const SizedBox(width: 12),
                    Text(tr('Score {n}', {'n': _score}), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), const Spacer(),
                    Text(tr('{n} words', {'n': _i}), style: TextStyle(color: Theme.of(context).hintColor))]),
                  const SizedBox(height: 28),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    IconButton.filled(iconSize: 40, onPressed: _say, icon: const Icon(Icons.volume_up_rounded)),
                    const SizedBox(width: 16),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                      onPressed: () => _say(sentence: true),
                      icon: const Icon(Icons.short_text_rounded),
                      label: Text(tr('In a sentence')),
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
                      hintText: tr('Type the word'),
                      filled: true,
                      fillColor: _right == null ? null : (_right! ? C.green : C.red).withValues(alpha: .18),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                  if (_right == false)
                    Padding(padding: const EdgeInsets.only(top: 10), child: Text('It is "${_words[_i]['word']}"',
                        textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
                  const SizedBox(height: 18),
                  FilledButton(onPressed: _check, child: Text(tr('Check'))),
                ]),
    );
  }
}

// ---------------------------------------------------------------- My words (saved words, spaced review)
const _stageNames = ['1 day', '3 days', '1 week', '2 weeks', '1 month', 'Learned'];
const _stageColours = [C.red, C.accent, C.gold, C.blue, Color(0xFF9B7BEA), C.green];

/// My words, as on the website: how many words wait at each stage, how many are due today (Review them),
/// and every saved word with its meaning and stage.
class WordsBoardScreen extends StatefulWidget {
  const WordsBoardScreen({super.key});
  @override
  State<WordsBoardScreen> createState() => _WordsBoardScreenState();
}

class _WordsBoardScreenState extends State<WordsBoardScreen> {
  Key _k = UniqueKey();
  String _q = '';
  int? _stage;                     // a stage picked above: only its words are listed

  Future<void> _remove(Map w) async {
    try {
      await Api.I.post('/api/games/words/remove', {'word': w['word']});
      setState(() => _k = UniqueKey());
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: rootBar(context, AppBar(title: Text(tr('My words')))),
      body: Loader<Map<String, dynamic>>(
        key: _k,
        load: () => Api.I.get('/api/app/words'),
        build: (context, d, reload) {
          final boxes = (d['boxes'] as List? ?? []).cast<Map>();
          final words = (d['words'] as List? ?? []).cast<Map>();
          final due = (d['due'] as num?)?.toInt() ?? 0;
          final q = _q.trim().toLowerCase();
          bool inStage(Map w) => _stage == null || (_stage == 5 ? w['mastered'] == true : w['mastered'] != true && (w['stage'] as num?)?.toInt() == _stage);
          final shown = words.where((w) => inStage(w) && (q.isEmpty || '${w['word']} ${w['definition']}'.toLowerCase().contains(q))).toList();
          final dark = Theme.of(context).brightness == Brightness.dark;
          return ListView(padding: const EdgeInsets.all(16), children: [
            // today's review
            Card(
              color: C.green.withValues(alpha: .12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Hudi(mood: 0, size: 64, face: due > 0 ? 'thinking' : 'happy'),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(due > 0 ? '$due words to review today' : 'Nothing to review today',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text('${d['total'] ?? 0} words saved', style: TextStyle(color: Theme.of(context).hintColor)),
                    ]),
                  ),
                  if (due > 0)
                    FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 44), backgroundColor: C.green),
                      onPressed: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => const WordsReviewScreen()));
                        setState(() => _k = UniqueKey());
                      },
                      child: Text(tr('Review')),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            // the stages: each word climbs one when you remember it, back to the first when you forget
            Row(children: [
              for (var i = 0; i < boxes.length && i < _stageNames.length; i++)
                Expanded(
                  // tap a stage to see only its words; tap again for all
                  child: GestureDetector(
                    onTap: () => setState(() => _stage = _stage == i ? null : i),
                    child: Container(
                    margin: EdgeInsets.only(right: i < boxes.length - 1 ? 6 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _stageColours[i].withValues(alpha: _stage == i ? (dark ? .45 : .32) : (dark ? .2 : .13)),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _stage == i ? _stageColours[i] : Colors.transparent, width: 1.5),
                    ),
                    child: Column(children: [
                      Text('${boxes[i]['n'] ?? 0}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _stageColours[i])),
                      const SizedBox(height: 2),
                      Text(tr(_stageNames[i]), textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, color: Theme.of(context).hintColor)),
                    ]),
                  ),
                  ),
                ),
            ]),
            const SizedBox(height: 14),
            if (words.isNotEmpty)
              TextField(
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(hintText: tr('Find a word'), prefixIcon: Icon(Icons.search_rounded), isDense: true),
              ),
            const SizedBox(height: 10),
            if (words.isEmpty)
              Padding(
                padding: const EdgeInsets.all(28),
                child: Column(children: [
                  const Hudi(mood: 0, size: 90, face: 'sleep'),
                  const SizedBox(height: 10),
                  Text(tr('No saved words yet. In Reading, tap a word to see its meaning and save it here.'),
                      textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).hintColor)),
                ]),
              ),
            for (final w in shown)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Row(children: [
                    Flexible(child: Text('${w['word']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                    if ('${w['pos'] ?? ''}'.isNotEmpty) Text('  ${w['pos']}', style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                  ]),
                  subtitle: Text('${w['translation'] ?? ''}'.isNotEmpty ? '${w['translation']}' : '${w['definition'] ?? ''}',
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _stageColours[w['mastered'] == true ? 5 : ((w['stage'] as num?)?.toInt() ?? 0).clamp(0, 4)].withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(tr(w['mastered'] == true ? 'Learned' : _stageNames[((w['stage'] as num?)?.toInt() ?? 0).clamp(0, 4)]),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _stageColours[w['mastered'] == true ? 5 : ((w['stage'] as num?)?.toInt() ?? 0).clamp(0, 4)])),
                  ),
                  onTap: () => showModalBottomSheet(
                    context: context,
                    showDragHandle: true,
                    builder: (c) => SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${w['word']}  ${w['ipa'] ?? ''}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                          if ('${w['definition'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${w['definition']}', style: const TextStyle(fontSize: 16))),
                          if ('${w['sentence'] ?? w['example'] ?? ''}'.isNotEmpty)
                            Padding(padding: const EdgeInsets.only(top: 8),
                                child: Text('${'${w['sentence'] ?? ''}'.isNotEmpty ? w['sentence'] : w['example']}', style: const TextStyle(fontStyle: FontStyle.italic))),
                          if ((w['synonyms'] as List? ?? []).isNotEmpty)
                            Padding(padding: const EdgeInsets.only(top: 8), child: Text('Synonyms: ${(w['synonyms'] as List).join(', ')}')),
                          const SizedBox(height: 16),
                          TextButton.icon(
                            style: TextButton.styleFrom(foregroundColor: C.red),
                            icon: const Icon(Icons.delete_outline_rounded),
                            label: Text(tr('Remove from My words')),
                            onPressed: () { Navigator.pop(c); _remove(w); },
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

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
      appBar: AppBar(title: Text(tr('Review'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty || _i >= _items.length
              ? Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Hudi(mood: 0, size: 100, face: _items.isEmpty ? 'sleep' : 'cheer'),
                  const SizedBox(height: 16),
                  Text(_items.isEmpty ? tr('No words to review today.') : 'All done for today!', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
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
            decoration: InputDecoration(hintText: tr('The missing word'), filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)),
            onSubmitted: (v) => _answer(v.trim().toLowerCase() == '${it['answer']}')),
        const SizedBox(height: 12),
        if (!_shown) FilledButton(onPressed: () => _answer(_in.text.trim().toLowerCase() == '${it['answer']}'), child: Text(tr('Check'))),
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
        FilledButton(onPressed: _next, child: Text(tr('Next'))),
      ],
    ]);
  }
}
