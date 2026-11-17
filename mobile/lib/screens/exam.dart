// Taking a test in the app: the same attempt as on the website (server clock, answers saved as you go,
// one section after another), with Listening audio, Reading passages, Writing tasks and recorded Speaking.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../i18n.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'listening.dart';
import 'exam_intro.dart';
import 'results.dart';
import 'wordcard.dart';
import 'tests.dart';

class ExamScreen extends StatefulWidget {
  const ExamScreen({super.key, required this.attemptId});
  final int attemptId;
  @override
  State<ExamScreen> createState() => _ExamScreenState();
}

/// What the questions and the passage need from the exam: flags, hints and highlights.
class _ExamScope extends InheritedWidget {
  const _ExamScope({required this.flags, required this.onFlag, required this.hints, required this.onHint,
      required this.highlights, required this.onHighlights, required this.hintShown, required this.attemptId, required super.child});
  final int attemptId;
  final Set<String> flags;
  final void Function(String qid) onFlag;
  final Object? hints;                                  // null: no hints in this section; '∞' or a number
  final void Function(String qid) onHint;
  final Map<String, dynamic> highlights;                // part -> paragraph -> [[start, end]]
  final void Function(int part, Map<String, List<List<int>>> ranges) onHighlights;
  final Map<int, Map<String, dynamic>> hintShown;       // part -> {para, quote}
  static _ExamScope? of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<_ExamScope>();
  @override
  bool updateShouldNotify(_ExamScope old) => true;
}

class _ExamScreenState extends State<ExamScreen> with WidgetsBindingObserver {
  final Set<String> _flags = {};
  Map<String, dynamic> _highlights = {};
  Object? _hints;
  ListeningPlayer? _player;
  bool _softPaused = false;                              // Listening paused by the learner (band 6.0 tests and below)
  bool _away = false;                                    // the app was sent to the background: paused on the server
  final Map<int, Map<String, dynamic>> _hintShown = {};  // part -> {para, quote}
  TabController? _tabs;
  Map<String, dynamic>? _st;
  String? _error;
  bool _busy = true;
  final Map<String, String> _answers = {};
  int _left = 0;
  Timer? _clock;
  Timer? _saveSoon;
  bool _dirty = false;
  bool _submitting = false;
  final Map<String, GlobalKey> _qKeys = {};
  GlobalKey _key(String qid) => _qKeys.putIfAbsent(qid, () => GlobalKey());

  String get _base => '/api/attempts/${widget.attemptId}';

  // which half of each part is showing: 0 = passage / task, 1 = questions / your answer
  final Map<int, ValueNotifier<int>> _view = {};
  ValueNotifier<int> _viewOf(int part) => _view.putIfAbsent(part, () => ValueNotifier<int>(0));

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addObserver(this);
    _startSection();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WidgetsBinding.instance.removeObserver(this);
    final pl = _player;
    if (pl != null) {
      if (!pl.finished) Api.I.post('$_base/progress', pl.position()).catchError((_) => <String, dynamic>{});
      pl.dispose();
    }
    for (final v in _view.values) { v.dispose(); }
    _clock?.cancel();
    _saveSoon?.cancel();
    if (_dirty) _save();
    super.dispose();
  }

  // Leaving the app pauses the test, as leaving the page does on the website; coming back goes on.
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (_st == null || _st!['status'] != 'in_progress' || _submitting) return;
    if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) {
      if (_away) return;
      _away = true;
      _clock?.cancel();
      _player?.pause();
      if (_dirty) _save();
      Api.I.post('$_base/pause').catchError((_) => <String, dynamic>{});
    } else if (s == AppLifecycleState.resumed && _away) {
      _away = false;
      if (!_softPaused) _goOn();
    }
  }

  Future<void> _goOn() async {
    try {
      final r = await Api.I.post('$_base/start');
      final st = r['state'] as Map<String, dynamic>;
      if (!mounted) return;
      if (st['sectionIndex'] != _st?['sectionIndex'] || st['status'] != 'in_progress') { _take(st); return; }
      _softPaused = false;
      _left = (st['remainingSeconds'] as num?)?.toInt() ?? _left;
      _runClock();
      _player?.start();
      setState(() {});
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  Future<void> _togglePause() async {
    if (!_softPaused) {
      _clock?.cancel();
      await _player?.pause();
      setState(() => _softPaused = true);
      if (_dirty) await _save();
      try { await Api.I.post('$_base/pause'); } on ApiError catch (e) { if (mounted) toast(context, e.message); }
    } else {
      await _goOn();
    }
  }

  bool get _canPause => (((_st?['test'] as Map?)?['level'] as num?) ?? 9) <= 6.0;

  void _runClock() {
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _left = _left > 0 ? _left - 1 : 0);
      if (_left == 0) { _clock?.cancel(); _submit(force: true); }
    });
  }

  void _flag(String qid) {
    setState(() { if (!_flags.remove(qid)) _flags.add(qid); });
    _dirty = true;
    _saveSoon?.cancel();
    _saveSoon = Timer(const Duration(milliseconds: 800), _save);
  }

  Future<void> _hint(String qid, int part) async {
    final have = _hints;
    if (have != '∞' && (have is! num || have <= 0)) {
      toast(context, tr('No hints left. Get more in the Shop.'));
      return;
    }
    final ok = have == '∞' || await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(tr('Use a hint?')),
            content: Text(tr('A hint marks the paragraph that has the answer. You have {n} left.', {'n': have})),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Cancel'))),
              TextButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Use a hint'))),
            ],
          ),
        ) == true;
    if (!ok) return;
    try {
      final r = await Api.I.post('$_base/hint', {'question': qid});
      final h = (r['hint'] as Map).cast<String, dynamic>();
      setState(() { _hints = h['left']; _hintShown[part] = h; });
      _viewOf(part).value = 0;                         // show the passage with the paragraph marked
      if (mounted) toast(context, tr('Look at the marked paragraph.'));
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  void _saveHighlights(int part, Map<String, List<List<int>>> ranges) {
    setState(() => _highlights = {..._highlights, '$part': ranges});
    Api.I.post('$_base/highlights', {'part': part, 'ranges': ranges}).catchError((Object e) {
      if (mounted && e is ApiError) toast(context, e.message);
      return <String, dynamic>{};
    });
  }

  void _setupPlayer(Map<String, dynamic> st) {
    _player?.dispose();
    _player = null;
    final section = (st['section'] as Map?) ?? {};
    if (section['key'] != 'listening') return;
    final parts = (section['parts'] as List? ?? []).cast<Map>();
    late final ListeningPlayer pl;
    pl = ListeningPlayer(
      parts: parts,
      progress: st['progress'] as Map?,
      onSave: (p) => Api.I.post('$_base/progress', p).catchError((_) => <String, dynamic>{}),
      onPartStart: (pi) { final t = _tabs; if (t != null && t.index != pi && pi < t.length) t.animateTo(pi); },
      onFinished: () async {
        try {
          final r = await Api.I.post('$_base/progress', pl.position());
          final left = (r['remainingSeconds'] as num?)?.toInt();
          if (left != null && mounted) setState(() => _left = left);
          final mins = ((section['review_seconds'] as num?) ?? 120) ~/ 60;
          if (mounted) toast(context, tr('The recording has finished. You have {n} minutes to check your answers.', {'n': mins}));
        } on ApiError { /* the clock still ends the section */ }
      },
      onError: (m) { if (mounted) toast(context, m); },
    );
    _player = pl;
  }

  Map<String, dynamic>? _intro;          // the section has not started: its intro page shows first

  Future<void> _startSection() async {
    setState(() { _busy = true; _error = null; });
    try {
      final now = (await Api.I.get(_base))['state'] as Map<String, dynamic>;
      if (now['status'] == 'in_progress' && now['sectionState'] == 'intro') {
        setState(() { _intro = now; _st = now; _busy = false; });
        return;
      }
      await _begin();
    } on ApiError catch (e) {
      setState(() { _error = e.message; _busy = false; });
    }
  }

  Future<void> _begin() async {
    try {
      final r = await Api.I.post('$_base/start');
      _intro = null;
      _take(r['state'] as Map<String, dynamic>);
    } on ApiError catch (e) {
      setState(() { _error = e.message; _busy = false; });
    }
  }

  void _take(Map<String, dynamic> st) {
    _clock?.cancel();
    _answers
      ..clear()
      ..addAll(((st['answers'] as Map?) ?? {}).map((k, v) => MapEntry('$k', '$v')));
    _flags
      ..clear()
      ..addAll(((st['flags'] as List?) ?? []).map((e) => '$e'));
    _highlights = ((st['highlights'] as Map?) ?? {}).cast<String, dynamic>();
    _hints = st['hints'];
    _hintShown.clear();
    _softPaused = false;
    _left = (st['remainingSeconds'] as num?)?.toInt() ?? 0;
    setState(() { _st = st; _busy = false; });
    if (st['status'] == 'in_progress') {
      _setupPlayer(st);
      _runClock();
      _player?.start();
    } else {
      _player?.dispose();
      _player = null;
    }
  }

  void _answer(String qid, String? value) {
    setState(() { if (value == null || value.isEmpty) { _answers.remove(qid); } else { _answers[qid] = value; } });
    _dirty = true;
    _saveSoon?.cancel();
    _saveSoon = Timer(const Duration(milliseconds: 1200), _save);
  }

  Future<void> _save() async {
    if (!_dirty) return;
    _dirty = false;
    final section = (_st?['section'] as Map?) ?? {};
    final ids = <String>{};
    for (final p in (section['parts'] as List? ?? [])) {
      for (final g in ((p as Map)['groups'] as List? ?? [])) {
        for (final q in ((g as Map)['questions'] as List? ?? [])) { ids.add('${(q as Map)['id']}'); }
      }
      final task = p['task'];
      if (task is Map) ids.add('${task['id']}');
    }
    final body = {for (final id in ids) id: _answers[id]};
    try {
      await Api.I.post('$_base/answers', {'answers': body, 'flags': {for (final id in ids) id: _flags.contains(id)}});
    } on ApiError {
      _dirty = true;                                  // try again with the next change or on submit
    }
  }

  Future<void> _submit({bool force = false}) async {
    if (_submitting || _st == null) return;
    if (!force) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(tr('Finish {s}?', {'s': (_st!['section'] as Map?)?['title'] ?? ''})),
          content: Text(tr('You cannot come back to this section after you finish it.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Keep going'))),
            TextButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Finish'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _submitting = true);
    await _player?.pause();
    _saveSoon?.cancel();
    _dirty = true;
    await _save();
    try {
      final r = await Api.I.post('$_base/submit-section', {'sectionIndex': _st!['sectionIndex']});
      final st = r['state'] as Map<String, dynamic>;
      if (st['status'] == 'completed') {
        _clock?.cancel();
        if (!mounted) return;
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ResultsScreen(attemptId: widget.attemptId)));
        return;
      }
      await _startSection();                         // the next section of a full mock
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<bool> _confirmLeave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Leave the test?')),
        content: Text(tr('Your answers are saved. The clock keeps running while you are away.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Stay'))),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Leave'))),
        ],
      ),
    );
    return ok == true;
  }

  void _numbers(BuildContext ctx, List<Map> parts, String key) {
    final tabs = DefaultTabController.of(ctx);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var pi = 0; pi < parts.length; pi++) ...[
                Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('${parts[pi]['title']}', style: const TextStyle(fontWeight: FontWeight.w800))),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final g in (parts[pi]['groups'] as List? ?? []).cast<Map>())
                    for (final q in (g['questions'] as List? ?? []).cast<Map>())
                      _NumberChip(
                        label: q['numbers'] is List ? (q['numbers'] as List).join('–') : '${q['number']}',
                        answered: (_answers['${q['id']}'] ?? '').isNotEmpty,
                        flagged: _flags.contains('${q['id']}'),
                        onTap: () {
                          Navigator.pop(sheet);
                          tabs.animateTo(pi);
                          _viewOf(pi).value = 1;                    // Reading: show the questions half
                          Future.delayed(const Duration(milliseconds: 400), () {
                            final c = _key('${q['id']}').currentContext;
                            if (c != null) Scrollable.ensureVisible(c, alignment: .2, duration: const Duration(milliseconds: 300));
                          });
                        },
                      ),
                ]),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  String get _clockText {
    final m = _left ~/ 60, s = _left % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null || _st == null) {
      return Scaffold(appBar: AppBar(), body: ErrorView(message: _error ?? 'Something went wrong.', onRetry: _startSection));
    }
    final st = _st!;
    if (st['status'] != 'in_progress') return ResultsScreen(attemptId: widget.attemptId);
    if (_intro != null) {
      return Scaffold(appBar: AppBar(title: Text('${(st['test'] as Map?)?['title'] ?? ''}')), body: SectionIntro(state: _intro!, onStart: _begin));
    }
    final section = (st['section'] as Map).cast<String, dynamic>();
    final key = '${section['key']}';
    final parts = (section['parts'] as List).cast<Map>();
    final sections = (st['sections'] as List).cast<Map>();
    final idx = (st['sectionIndex'] as num).toInt();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) Navigator.pop(context);
      },
      child: DefaultTabController(
        key: ValueKey('$key-$idx'),
        length: parts.length,
        child: Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: Row(children: [
              Icon(sectionIcons[key], color: sectionColors[key]),
              const SizedBox(width: 8),
              Flexible(child: Text('${section['title']}', overflow: TextOverflow.ellipsis)),
              if (sections.length > 1)
                Text('  ${idx + 1}/${sections.length}', style: TextStyle(fontSize: 14, color: Theme.of(context).hintColor)),
            ]),
            actions: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: (_left < 300 ? C.red : Theme.of(context).dividerColor).withValues(alpha: .16),
                ),
                child: Text(_clockText, style: TextStyle(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()],
                    color: _left < 300 ? C.red : null)),
              ),
              if (key == 'listening' || key == 'reading')
                Builder(builder: (ctx) => IconButton(
                  tooltip: tr('Questions'),
                  icon: const Icon(Icons.grid_view_rounded),
                  onPressed: () => _numbers(ctx, parts, key),
                )),
              TextButton(onPressed: _submitting ? null : () => _submit(), child: Text(tr('Finish'))),
            ],
            bottom: parts.length > 1
                ? TabBar(isScrollable: parts.length > 3, tabs: [for (final p in parts) Tab(text: '${p['title']}')])
                : null,
          ),
          body: Builder(builder: (ctx) {
            _tabs = DefaultTabController.of(ctx);
            final pages = TabBarView(children: [
              for (var i = 0; i < parts.length; i++)
                _PartView(
                  key: ValueKey('$key-$idx-$i'),
                  sectionKey: key,
                  partIndex: i,
                  part: parts[i].cast<String, dynamic>(),
                  answers: _answers,
                  onAnswer: _answer,
                  attemptBase: _base,
                  keyFor: _key,
                  view: _viewOf(i),
                ),
            ]);
            return _ExamScope(
              flags: _flags,
              onFlag: _flag,
              hints: _hints,
              onHint: (qid) => _hint(qid, _tabs?.index ?? 0),
              highlights: _highlights,
              onHighlights: _saveHighlights,
              hintShown: _hintShown,
              attemptId: widget.attemptId,
              child: Column(children: [
                if (_player != null)
                  _AudioPanel(player: _player!, parts: parts, canPause: _canPause, paused: _softPaused, onPause: _togglePause),
                Expanded(
                  child: _softPaused
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.pause_circle_rounded, size: 64, color: C.blue),
                              const SizedBox(height: 12),
                              Text(tr('Paused'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 6),
                              Text(tr('The recording and the timer have stopped. The questions come back when you go on.'),
                                  textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).hintColor)),
                              const SizedBox(height: 16),
                              FilledButton.icon(onPressed: _togglePause, icon: const Icon(Icons.play_arrow_rounded), label: Text(tr('Go on'))),
                            ]),
                          ),
                        )
                      : pages,
                ),
              ]),
            );
          }),
        ),
      ),
    );
  }
}

class _PartView extends StatefulWidget {
  const _PartView({super.key, required this.sectionKey, required this.partIndex, required this.part, required this.answers, required this.onAnswer,
      required this.attemptBase, required this.keyFor, required this.view});
  final GlobalKey Function(String) keyFor;
  final String sectionKey;
  final int partIndex;
  final Map<String, dynamic> part;
  final Map<String, String> answers;
  final void Function(String, String?) onAnswer;
  final String attemptBase;
  final ValueNotifier<int> view;
  @override
  State<_PartView> createState() => _PartViewState();
}

class _PartViewState extends State<_PartView> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  Widget _scroll(List<Widget> children) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  List<Widget> _questions() => [
        for (final g in (widget.part['groups'] as List? ?? []).cast<Map>())
          _Group(group: g.cast<String, dynamic>(), answers: widget.answers, onAnswer: widget.onAnswer, keyFor: widget.keyFor),
      ];

  Widget _intro(BuildContext context) => (widget.part['intro'] ?? '').toString().isEmpty
      ? const SizedBox.shrink()
      : Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('${widget.part['intro']}', style: TextStyle(color: Theme.of(context).hintColor)));

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final part = widget.part;
    switch (widget.sectionKey) {
      case 'reading':
        return _TwoHalves(view: widget.view, labels: const ['Passage', 'Questions'], icons: const [Icons.article_rounded, Icons.checklist_rounded], halves: [
          _scroll([_intro(context), if (part['passage'] is Map) _Passage(part: widget.partIndex, passage: (part['passage'] as Map).cast<String, dynamic>())]),
          _scroll(_questions()),
        ]);
      case 'writing':
        final task = (part['task'] as Map?)?.cast<String, dynamic>() ?? {};
        return _TwoHalves(view: widget.view, labels: const ['Task', 'Write'], icons: const [Icons.description_rounded, Icons.edit_rounded], halves: [
          _scroll([_intro(context), _WritingBrief(task: task)]),
          _WritingAnswer(task: task, answers: widget.answers, onAnswer: widget.onAnswer),
        ]);
      case 'listening':
        return _scroll([_intro(context), ..._questions()]);
      default:
        return _scroll([
          _intro(context),
          if (part['prompts'] is List)
            for (final pr in (part['prompts'] as List).cast<Map>()) _SpeakingPrompt(prompt: pr.cast<String, dynamic>(), attemptBase: widget.attemptBase),
        ]);
    }
  }
}

/// Two halves of a part with tabs at the bottom (Reading: Passage | Questions; Writing: Task | Write).
class _TwoHalves extends StatelessWidget {
  const _TwoHalves({required this.view, required this.labels, required this.icons, required this.halves});
  final ValueNotifier<int> view;
  final List<String> labels;
  final List<IconData> icons;
  final List<Widget> halves;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: view,
        builder: (context, v, _) => Column(children: [
          Expanded(child: IndexedStack(index: v, children: halves)),
          NavigationBar(
            height: 60,
            selectedIndex: v,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            onDestinationSelected: (i) => view.value = i,
            destinations: [for (var i = 0; i < 2; i++) NavigationDestination(icon: Icon(icons[i]), label: labels[i])],
          ),
        ]),
      );
}

class _NumberChip extends StatelessWidget {
  const _NumberChip({required this.label, required this.answered, required this.onTap, this.flagged = false});
  final String label;
  final bool answered;
  final bool flagged;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: answered ? C.accent : (dark ? Colors.white.withValues(alpha: .08) : const Color(0xFF141413).withValues(alpha: .06)),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 40),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: answered ? Colors.white : null)),
            if (flagged) Padding(padding: const EdgeInsets.only(left: 3), child: Icon(Icons.flag_rounded, size: 14, color: answered ? Colors.white : C.gold)),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Reading passage
// Select words and press Highlight, as on the website; the marks are saved with the attempt.
class _Passage extends StatelessWidget {
  const _Passage({required this.part, required this.passage});
  final int part;
  final Map<String, dynamic> passage;

  Map<String, List<List<int>>> _ranges(_ExamScope? scope) {
    final raw = (scope?.highlights['$part'] as Map?) ?? {};
    return {
      for (final e in raw.entries)
        '${e.key}': [for (final r in (e.value as List)) [((r as List)[0] as num).toInt(), (r[1] as num).toInt()]]
    };
  }

  static List<List<int>> _merge(List<List<int>> spans) {
    final list = [...spans]..sort((a, b) => a[0].compareTo(b[0]));
    final out = <List<int>>[];
    for (final r in list) {
      if (out.isNotEmpty && r[0] <= out.last[1]) { out.last[1] = r[1] > out.last[1] ? r[1] : out.last[1]; } else { out.add([r[0], r[1]]); }
    }
    return out;
  }

  /// The sentence of the paragraph that holds the character at [at].
  static String _sentenceAt(String text, int at) {
    var start = 0, end = text.length;
    for (var i = at - 1; i >= 0; i--) { if ('.!?'.contains(text[i])) { start = i + 1; break; } }
    for (var i = at; i < text.length; i++) { if ('.!?'.contains(text[i])) { end = i + 1; break; } }
    return text.substring(start, end).trim();
  }

  static List<List<int>> _cut(List<List<int>> spans, int a, int b) {
    final out = <List<int>>[];
    for (final r in spans) {
      if (r[1] <= a || r[0] >= b) { out.add(r); continue; }
      if (r[0] < a) out.add([r[0], a]);
      if (r[1] > b) out.add([b, r[1]]);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final scope = _ExamScope.of(context);
    final paras = (passage['paragraphs'] as List? ?? []);
    final ranges = _ranges(scope);
    final hint = scope?.hintShown[part];
    final dark = Theme.of(context).brightness == Brightness.dark;
    final mark = dark ? const Color(0xFF8A6D1F) : const Color(0xFFFFE58A);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${passage['title'] ?? 'Reading passage'}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          for (var i = 0; i < paras.length; i++)
            Builder(builder: (context) {
              final p = paras[i];
              final text = p is Map ? '${p['text']}' : '$p';
              final label = p is Map ? '${p['label'] ?? ''}' : '';
              final mine = ranges['$i'] ?? const <List<int>>[];
              final spans = <TextSpan>[];
              var at = 0;
              for (final r in _merge(mine)) {
                final a = r[0].clamp(0, text.length), b = r[1].clamp(0, text.length);
                if (a > at) spans.add(TextSpan(text: text.substring(at, a)));
                if (b > a) spans.add(TextSpan(text: text.substring(a, b), style: TextStyle(backgroundColor: mark)));
                at = b > at ? b : at;
              }
              if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
              final hinted = hint != null && (hint['para'] as num?)?.toInt() == i;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: hinted ? const EdgeInsets.all(8) : EdgeInsets.zero,
                decoration: hinted
                    ? BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: C.gold, width: 2), color: C.gold.withValues(alpha: .08))
                    : null,
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (label.isNotEmpty) Padding(padding: const EdgeInsets.only(right: 8), child: Text(label, style: const TextStyle(fontSize: 16, height: 1.55, fontWeight: FontWeight.w800))),
                  Expanded(
                    child: SelectableText.rich(
                      TextSpan(children: spans),
                      style: const TextStyle(fontSize: 16, height: 1.55),
                      contextMenuBuilder: scope == null
                          ? null
                          : (context, state) {
                              final sel = state.textEditingValue.selection;
                              final a = sel.start < sel.end ? sel.start : sel.end, b = sel.start < sel.end ? sel.end : sel.start;
                              final covered = mine.any((r) => r[0] < b && r[1] > a);
                              void save(List<List<int>> next) {
                                final all = {...ranges};
                                if (next.isEmpty) { all.remove('$i'); } else { all['$i'] = next; }
                                scope.onHighlights(part, all);
                                state.hideToolbar();
                              }
                              final picked = oneWord(sel.textInside(text));
                              return AdaptiveTextSelectionToolbar.buttonItems(
                                anchors: state.contextMenuAnchors,
                                buttonItems: [
                                  // one word picked: its meaning in this sentence, and save it to My words
                                  if (picked != null)
                                    ContextMenuButtonItem(label: tr('Meaning'), onPressed: () {
                                      state.hideToolbar();
                                      showWordCard(context, picked, sentence: _sentenceAt(text, a), attempt: scope.attemptId);
                                    }),
                                  if (b > a)
                                    ContextMenuButtonItem(label: tr('Highlight'), onPressed: () => save(_merge([...mine, [a, b]]))),
                                  if (b > a && covered)
                                    ContextMenuButtonItem(label: tr('Remove highlight'), onPressed: () => save(_cut(mine, a, b))),
                                  ...state.contextMenuButtonItems.where((e) => e.type == ContextMenuButtonType.copy),
                                ],
                              );
                            },
                    ),
                  ),
                ]),
              );
            }),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- Listening recording panel
class _AudioPanel extends StatelessWidget {
  const _AudioPanel({required this.player, required this.parts, required this.canPause, required this.paused, required this.onPause});
  final ListeningPlayer player;
  final List<Map> parts;
  final bool canPause;
  final bool paused;
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: player,
        builder: (context, _) {
          final s = player.status();
          final title = s.finished || s.part >= parts.length ? '' : '${parts[s.part]['title']}';
          final String text;
          if (s.finished) {
            text = 'The recording has finished. Check your answers.';
          } else if (paused) {
            text = 'Paused';
          } else if (s.kind == 'prep') {
            text = '$title: read the questions (${(s.remaining ?? 0).ceil()} s)';
          } else if (s.kind == 'intro' || s.kind == 'end') {
            text = '$title: the examiner is speaking';
          } else {
            text = s.playing ? '$title: ${tr('Listening…')}' : '$title';
          }
          final value = s.finished ? 1.0 : s.kind == 'prep' ? null : (s.fraction ?? 0);
          return Material(
            color: C.blue.withValues(alpha: .08),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(children: [
                Icon(s.finished ? Icons.check_circle_rounded : Icons.headphones_rounded, color: C.blue),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 5),
                    LinearProgressIndicator(value: paused ? (s.fraction ?? 0) : value, borderRadius: BorderRadius.circular(4), color: C.blue, minHeight: 4),
                  ]),
                ),
                if (canPause && !s.finished)
                  IconButton(
                    tooltip: paused ? tr('Resume') : 'Pause the recording and the timer',
                    icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                    onPressed: onPause,
                  )
                else
                  const SizedBox(width: 8),
              ]),
            ),
          );
        },
      );
}

// ---------------------------------------------------------------- Writing
class _WritingBrief extends StatelessWidget {
  const _WritingBrief({required this.task});
  final Map<String, dynamic> task;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${task['text'] ?? ''}', style: const TextStyle(fontSize: 16, height: 1.5)),
            if ((task['min_words'] as num? ?? 0) > 0)
              Padding(padding: const EdgeInsets.only(top: 10),
                  child: Text(tr('Write at least {n} words.', {'n': task['min_words']}), style: const TextStyle(fontWeight: FontWeight.w700))),
            if (task['image'] is String) ...[const SizedBox(height: 12), _MediaImage(path: task['image'] as String)],
          ]),
        ),
      );
}

class _WritingAnswer extends StatefulWidget {
  const _WritingAnswer({required this.task, required this.answers, required this.onAnswer});
  final Map<String, dynamic> task;
  final Map<String, String> answers;
  final void Function(String, String?) onAnswer;
  @override
  State<_WritingAnswer> createState() => _WritingAnswerState();
}

class _WritingAnswerState extends State<_WritingAnswer> {
  late final TextEditingController _c = TextEditingController(text: widget.answers['${widget.task['id']}'] ?? '');

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  int get _words => _c.text.trim().isEmpty ? 0 : _c.text.trim().split(RegExp(r'\s+')).length;

  @override
  Widget build(BuildContext context) {
    final min = (widget.task['min_words'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: TextField(
            controller: _c,
            expands: true,
            maxLines: null,
            minLines: null,
            textAlignVertical: TextAlignVertical.top,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.multiline,
            onChanged: (v) { setState(() {}); widget.onAnswer('${widget.task['id']}', v); },
            decoration: InputDecoration(hintText: tr('Write your answer here')),
          ),
        ),
        const SizedBox(height: 6),
        Text(tr('{n} words', {'n': _words}) + (min > 0 ? ' · ${tr('at least {n}', {'n': min})}' : ''), textAlign: TextAlign.right,
            style: TextStyle(color: _words >= min ? C.green : Theme.of(context).hintColor, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _MediaImage extends StatelessWidget {
  const _MediaImage({required this.path});
  final String path;
  @override
  Widget build(BuildContext context) => FutureBuilder<File>(
        future: Api.I.media(path),
        builder: (context, snap) {
          if (!snap.hasData) return const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
          final f = snap.data!;
          final img = path.toLowerCase().endsWith('.svg') ? SvgPicture.file(f) : Image.file(f);
          return InteractiveViewer(maxScale: 4, child: Container(color: Colors.white, padding: const EdgeInsets.all(8), child: img));
        },
      );
}

// ---------------------------------------------------------------- Speaking
class _SpeakingPrompt extends StatefulWidget {
  const _SpeakingPrompt({required this.prompt, required this.attemptBase});
  final Map<String, dynamic> prompt;
  final String attemptBase;
  @override
  State<_SpeakingPrompt> createState() => _SpeakingPromptState();
}

class _SpeakingPromptState extends State<_SpeakingPrompt> {
  final _player = AudioPlayer();
  final _rec = AudioRecorder();
  String _status = 'ready';     // ready, asking, preparing, recording, sending, done
  int _count = 0;
  Timer? _t;

  @override
  void dispose() {
    _t?.cancel();
    _player.dispose();
    _rec.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final p = widget.prompt;
    if (!await _rec.hasPermission()) {
      if (mounted) toast(context, tr('Allow the microphone to answer the Speaking questions.'));
      return;
    }
    try {
      if (p['audio'] is String) {
        setState(() => _status = 'asking');
        await _player.setFilePath((await Api.I.media(p['audio'] as String)).path);
        await _player.play();
      }
      final prep = (p['prep_seconds'] as num?)?.toInt() ?? 0;
      if (prep > 0) await _countdown('preparing', prep);
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}${Platform.pathSeparator}${p['id']}.m4a';
      await _rec.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      await _countdown('recording', (p['answer_seconds'] as num?)?.toInt() ?? 30);
      await _stopAndSend();
    } catch (_) {
      if (mounted) { setState(() => _status = 'ready'); toast(context, tr('Something went wrong. Please try this question again.')); }
    }
  }

  Future<void> _countdown(String status, int seconds) {
    final done = Completer<void>();
    setState(() { _status = status; _count = seconds; });
    _t?.cancel();
    _t = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _status != status) { t.cancel(); if (!done.isCompleted) done.complete(); return; }
      setState(() => _count--);
      if (_count <= 0) { t.cancel(); if (!done.isCompleted) done.complete(); }
    });
    return done.future;
  }

  Future<void> _stopAndSend() async {
    _t?.cancel();
    final path = await _rec.stop();
    if (path == null) { setState(() => _status = 'ready'); return; }
    setState(() => _status = 'sending');
    try {
      await Api.I.uploadAnswer('${widget.attemptBase}/speaking/${widget.prompt['id']}', File(path), 'audio/mp4');
      if (mounted) setState(() => _status = 'done');
    } on ApiError catch (e) {
      if (mounted) { setState(() => _status = 'ready'); toast(context, e.message); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.prompt;
    final card = p['card'];
    final recording = _status == 'recording';
    final label = switch (_status) {
      'asking' => 'Listen to the question…',
      'preparing' => 'Prepare: $_count s',
      'recording' => 'Recording: $_count s left',
      'sending' => 'Sending your answer…',
      'done' => 'Answer saved',
      _ => 'Tap to hear the question and answer',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if ((p['text'] ?? '').toString().isNotEmpty)
              Text('${p['text']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.4)),
            if (card is Map) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: C.accent.withValues(alpha: .08)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final e in card.entries)
                    if (e.value is List)
                      for (final line in (e.value as List)) Text('•  $line')
                    else
                      Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.w600))),
                ]),
              ),
            ],
            const SizedBox(height: 12),
            Row(children: [
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: recording ? C.red : null),
                onPressed: _status == 'ready' ? _go : recording ? _stopAndSend : null,
                icon: Icon(recording ? Icons.stop_rounded : _status == 'done' ? Icons.check_rounded : Icons.mic_rounded),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: TextStyle(color: recording ? C.red : Theme.of(context).hintColor, fontWeight: FontWeight.w600))),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Question groups
class _Group extends StatelessWidget {
  const _Group({required this.group, required this.answers, required this.onAnswer, required this.keyFor});
  final GlobalKey Function(String) keyFor;
  final Map<String, dynamic> group;
  final Map<String, String> answers;
  final void Function(String, String?) onAnswer;

  @override
  Widget build(BuildContext context) {
    final type = '${group['type']}';
    final qs = (group['questions'] as List? ?? []).cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
    final opts = (group['options'] as List? ?? []).cast<Map>();
    final hint = Theme.of(context).hintColor;
    Widget body;
    if (type == 'gap' || type == 'gap_choice') {
      body = _Template(group: group, questions: qs, answers: answers, onAnswer: onAnswer, keyFor: keyFor);
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (type == 'matching' && opts.isNotEmpty) _OptionList(title: '${group['options_title'] ?? 'Options'}', options: opts),
        for (final q in qs) KeyedSubtree(key: keyFor('${q['id']}'), child: _Question(type: type, q: q, groupOptions: opts, answers: answers, onAnswer: onAnswer)),
      ]);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${group['title'] ?? ''}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('${group['instructions'] ?? ''}', style: TextStyle(color: hint)),
        const SizedBox(height: 10),
        body,
      ]),
    );
  }
}

class _OptionList extends StatelessWidget {
  const _OptionList({required this.title, required this.options});
  final String title;
  final List<Map> options;
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            for (final o in options)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '${o['key']}  ', style: const TextStyle(fontWeight: FontWeight.w800)),
                  TextSpan(text: '${o['text']}'),
                ])),
              ),
          ]),
        ),
      );
}

class _Question extends StatelessWidget {
  const _Question({required this.type, required this.q, required this.groupOptions, required this.answers, required this.onAnswer});
  final String type;
  final Map<String, dynamic> q;
  final List<Map> groupOptions;
  final Map<String, String> answers;
  final void Function(String, String?) onAnswer;

  @override
  Widget build(BuildContext context) {
    final id = '${q['id']}';
    final own = (q['options'] as List? ?? []).cast<Map>();
    final options = own.isNotEmpty ? own : groupOptions;
    final number = q['numbers'] is List ? (q['numbers'] as List).join('–') : '${q['number'] ?? ''}';
    final given = answers[id];
    final multi = type == 'mcq_multi';
    final picked = multi ? (given ?? '').split(',').where((e) => e.isNotEmpty).toSet() : <String>{};
    final limit = (q['select'] as num?)?.toInt() ?? 2;
    // TRUE / FALSE / NOT GIVEN and matching letters fit as chips; longer options as a list
    final chips = type == 'tfng' || type == 'ynng' || type == 'matching';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '$number  ', style: const TextStyle(fontWeight: FontWeight.w800, color: C.accent)),
                TextSpan(text: '${q['text'] ?? ''}'),
              ]), style: const TextStyle(fontSize: 15.5, height: 1.4)),
            ),
          ),
          _QuestionTools(qid: id),
        ]),
        const SizedBox(height: 8),
        if (chips)
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final o in options)
              ChoiceChip(
                label: Text('${o['key']}'),
                selected: given == '${o['key']}',
                onSelected: (on) => onAnswer(id, on ? '${o['key']}' : null),
              ),
          ])
        else
          for (final o in options)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _OptionTile(
                letter: '${o['key']}',
                text: '${o['text']}',
                selected: multi ? picked.contains('${o['key']}') : given == '${o['key']}',
                onTap: () {
                  final k = '${o['key']}';
                  if (!multi) { onAnswer(id, given == k ? null : k); return; }
                  final next = {...picked};
                  if (next.contains(k)) { next.remove(k); } else if (next.length < limit) { next.add(k); }
                  final list = next.toList()..sort();
                  onAnswer(id, list.isEmpty ? null : list.join(','));
                },
              ),
            ),
      ]),
    );
  }
}

/// Flag a question to come back to it, and (Reading practice) ask where the answer is.
class _QuestionTools extends StatelessWidget {
  const _QuestionTools({required this.qid});
  final String qid;
  @override
  Widget build(BuildContext context) {
    final scope = _ExamScope.of(context);
    if (scope == null) return const SizedBox.shrink();
    final flagged = scope.flags.contains(qid);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (scope.hints != null)
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: tr('Hint ({n} left)', {'n': scope.hints}),
          icon: const Icon(Icons.lightbulb_outline_rounded, size: 20),
          onPressed: () => scope.onHint(qid),
        ),
      IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: flagged ? tr('Remove the flag') : tr('Flag to come back to it'),
        icon: Icon(flagged ? Icons.flag_rounded : Icons.outlined_flag_rounded, size: 20, color: flagged ? C.gold : Theme.of(context).hintColor),
        onPressed: () => scope.onFlag(qid),
      ),
    ]);
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.letter, required this.text, required this.selected, required this.onTap});
  final String letter;
  final String text;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: selected ? C.accent.withValues(alpha: .12) : null,
            border: Border.all(color: selected ? C.accent : Theme.of(context).dividerColor, width: selected ? 2 : 1),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(letter, style: TextStyle(fontWeight: FontWeight.w800, color: selected ? C.accent : null)),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ]),
        ),
      );
}

/// Gap fill (type the words) and gap choice (pick from a list): the template's {n} gaps become fields.
class _Template extends StatelessWidget {
  const _Template({required this.group, required this.questions, required this.answers, required this.onAnswer, required this.keyFor});
  final GlobalKey Function(String) keyFor;
  final Map<String, dynamic> group;
  final List<Map<String, dynamic>> questions;
  final Map<String, String> answers;
  final void Function(String, String?) onAnswer;

  @override
  Widget build(BuildContext context) {
    final choice = group['type'] == 'gap_choice';
    final opts = (group['options'] as List? ?? []).cast<Map>();
    final byNumber = {for (final q in questions) '${q['number']}': '${q['id']}'};
    final lines = '${group['template'] ?? ''}'.split('\n');
    final widgets = <Widget>[];
    if (choice && opts.isNotEmpty) widgets.add(_OptionList(title: '${group['options_title'] ?? 'Options'}', options: opts));
    for (var raw in lines) {
      var line = raw.trim();
      if (line.isEmpty) continue;
      var heading = false;
      if (line.startsWith('#')) { heading = true; line = line.replaceFirst(RegExp(r'^#+\s*'), ''); }
      if (line.startsWith('|')) {
        if (RegExp(r'^\|[\s:|-]+\|?$').hasMatch(line)) continue;            // a table's divider row
        line = line.split('|').map((c) => c.trim()).where((c) => c.isNotEmpty).join('  ·  ');
      }
      line = line.replaceFirst(RegExp(r'^[-*]\s+'), '•  ');
      final spans = <Widget>[];
      var last = 0;
      for (final m in RegExp(r'\{(\d+)\}').allMatches(line)) {
        if (m.start > last) spans.add(Text(line.substring(last, m.start), style: TextStyle(fontWeight: heading ? FontWeight.w800 : null)));
        final qid = byNumber[m.group(1)];
        if (qid != null) {
          spans.add(KeyedSubtree(key: keyFor(qid), child: choice
              ? _GapChoice(number: m.group(1)!, value: answers[qid], options: opts, onChanged: (v) => onAnswer(qid, v))
              : _GapField(number: m.group(1)!, initial: answers[qid] ?? '', onChanged: (v) => onAnswer(qid, v.trim()))));
        }
        last = m.end;
      }
      if (last < line.length) spans.add(Text(line.substring(last), style: TextStyle(fontWeight: heading ? FontWeight.w800 : null)));
      widgets.add(Padding(
        padding: EdgeInsets.only(bottom: heading ? 10 : 8),
        child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, runSpacing: 6, children: spans),
      ));
    }
    return Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets)));
  }
}

class _GapField extends StatefulWidget {
  const _GapField({required this.number, required this.initial, required this.onChanged});
  final String number;
  final String initial;
  final ValueChanged<String> onChanged;
  @override
  State<_GapField> createState() => _GapFieldState();
}

class _GapFieldState extends State<_GapField> {
  late final _c = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 130,
        child: TextField(
          controller: _c,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: widget.onChanged,
          decoration: InputDecoration(
            isDense: true,
            hintText: widget.number,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          ),
        ),
      );
}

class _GapChoice extends StatelessWidget {
  const _GapChoice({required this.number, required this.value, required this.options, required this.onChanged});
  final String number;
  final String? value;
  final List<Map> options;
  final ValueChanged<String?> onChanged;
  @override
  Widget build(BuildContext context) => DropdownButton<String>(
        value: options.any((o) => '${o['key']}' == value) ? value : null,
        hint: Text(number),
        isDense: true,
        items: [for (final o in options) DropdownMenuItem(value: '${o['key']}', child: Text('${o['key']}'))],
        onChanged: onChanged,
      );
}

// ---------------------------------------------------------------- Results
class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key, required this.attemptId});
  final int attemptId;
  @override
  Widget build(BuildContext context) => ResultsView(attemptId: attemptId);
}

/// A finished Listening or Reading section: every question with your answer, the right one and why.
class ReviewScreen extends StatelessWidget {
  const ReviewScreen({super.key, required this.attemptId, required this.section});
  final int attemptId;
  final int section;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Answers'))),
      body: Loader<Map<String, dynamic>>(
        load: () async => (await Api.I.get('/api/attempts/$attemptId/review', {'section': section}))['state'] as Map<String, dynamic>,
        build: (context, st, reload) {
          final marking = ((st['marking'] as Map?) ?? {}).cast<String, dynamic>();
          final answers = ((st['answers'] as Map?) ?? {}).cast<String, dynamic>();
          final rows = <Widget>[];
          for (final p in ((st['section'] as Map)['parts'] as List).cast<Map>()) {
            rows.add(Padding(padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                child: Text('${p['title']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))));
            for (final g in (p['groups'] as List? ?? []).cast<Map>()) {
              for (final q in (g['questions'] as List? ?? []).cast<Map>()) {
                final m = (marking['${q['id']}'] as Map?) ?? {};
                final marks = (m['marks'] as num?) ?? 0, worth = (m['worth'] as num?) ?? 1;
                final ok = marks >= worth;
                final label = q['numbers'] is List ? (q['numbers'] as List).join('–') : '${q['number']}';
                rows.add(Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: (ok ? C.green : C.red).withValues(alpha: .08),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(ok ? Icons.check_circle_rounded : Icons.cancel_rounded, color: ok ? C.green : C.red, size: 20),
                        const SizedBox(width: 8),
                        Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(width: 8),
                        Expanded(child: Text('${q['text'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis)),
                      ]),
                      const SizedBox(height: 6),
                      Text('${tr('Your answer')}: ${answers['${q['id']}'] ?? '—'}'),
                      if (!ok) Text('${tr('Answer')}: ${m['answer'] is List ? (m['answer'] as List).join(' / ') : m['answer'] ?? ''}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      if ('${m['explanation'] ?? ''}'.isNotEmpty)
                        Padding(padding: const EdgeInsets.only(top: 6),
                            child: Text('${m['explanation']}', style: TextStyle(color: Theme.of(context).hintColor))),
                    ]),
                  ),
                ));
              }
            }
          }
          return ListView(padding: const EdgeInsets.all(16), children: rows);
        },
      ),
    );
  }
}
