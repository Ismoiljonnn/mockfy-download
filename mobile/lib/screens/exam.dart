// Taking a test in the app: the same attempt as on the website (server clock, answers saved as you go,
// one section after another), with Listening audio, Reading passages, Writing tasks and recorded Speaking.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'tests.dart';

class ExamScreen extends StatefulWidget {
  const ExamScreen({super.key, required this.attemptId});
  final int attemptId;
  @override
  State<ExamScreen> createState() => _ExamScreenState();
}

class _ExamScreenState extends State<ExamScreen> {
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

  @override
  void initState() {
    super.initState();
    _startSection();
  }

  @override
  void dispose() {
    _clock?.cancel();
    _saveSoon?.cancel();
    if (_dirty) _save();
    super.dispose();
  }

  Future<void> _startSection() async {
    setState(() { _busy = true; _error = null; });
    try {
      final r = await Api.I.post('$_base/start');
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
    _left = (st['remainingSeconds'] as num?)?.toInt() ?? 0;
    setState(() { _st = st; _busy = false; });
    if (st['status'] == 'in_progress') {
      _clock = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _left = _left > 0 ? _left - 1 : 0);
        if (_left == 0) { _clock?.cancel(); _submit(force: true); }
      });
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
      await Api.I.post('$_base/answers', {'answers': body});
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
          title: Text('Finish ${(_st!['section'] as Map?)?['title'] ?? 'this section'}?'),
          content: const Text('You cannot come back to this section after you finish it.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep going')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Finish')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _submitting = true);
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
        title: const Text('Leave the test?'),
        content: const Text('Your answers are saved. The clock keeps running while you are away.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Stay')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Leave')),
        ],
      ),
    );
    return ok == true;
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
              TextButton(onPressed: _submitting ? null : () => _submit(), child: const Text('Finish')),
            ],
            bottom: parts.length > 1
                ? TabBar(isScrollable: parts.length > 3, tabs: [for (final p in parts) Tab(text: '${p['title']}')])
                : null,
          ),
          body: Column(children: [
            Expanded(
              child: TabBarView(children: [
                for (final p in parts)
                  _PartView(
                    key: PageStorageKey('${p['title']}'),
                    sectionKey: key,
                    part: p.cast<String, dynamic>(),
                    answers: _answers,
                    onAnswer: _answer,
                    attemptBase: _base,
                    keyFor: _key,
                  ),
              ]),
            ),
            if (key == 'listening' || key == 'reading') _NumberBar(parts: parts, answers: _answers, keyFor: _key),
          ]),
        ),
      ),
    );
  }
}

class _PartView extends StatelessWidget {
  const _PartView({super.key, required this.sectionKey, required this.part, required this.answers, required this.onAnswer, required this.attemptBase, required this.keyFor});
  final GlobalKey Function(String) keyFor;
  final String sectionKey;
  final Map<String, dynamic> part;
  final Map<String, String> answers;
  final void Function(String, String?) onAnswer;
  final String attemptBase;

  @override
  Widget build(BuildContext context) {
    final groups = (part['groups'] as List? ?? []).cast<Map>();
    final hint = Theme.of(context).hintColor;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
      if ((part['intro'] ?? '').toString().isNotEmpty)
        Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('${part['intro']}', style: TextStyle(color: hint))),
      if (part['recording'] is Map) _Recording(recording: (part['recording'] as Map).cast<String, dynamic>()),
      if (part['passage'] is Map) _Passage(passage: (part['passage'] as Map).cast<String, dynamic>()),
      if (part['task'] is Map) _WritingTask(task: (part['task'] as Map).cast<String, dynamic>(), answers: answers, onAnswer: onAnswer),
      if (part['prompts'] is List)
        for (final pr in (part['prompts'] as List).cast<Map>())
          _SpeakingPrompt(prompt: pr.cast<String, dynamic>(), attemptBase: attemptBase),
      for (final g in groups) _Group(group: g.cast<String, dynamic>(), answers: answers, onAnswer: onAnswer, keyFor: keyFor),
    ]);
  }
}

// ---------------------------------------------------------------- Reading passage
class _Passage extends StatelessWidget {
  const _Passage({required this.passage});
  final Map<String, dynamic> passage;
  @override
  Widget build(BuildContext context) {
    final paras = (passage['paragraphs'] as List? ?? []);
    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        shape: const Border(),
        title: Text('${passage['title'] ?? 'Reading passage'}', style: const TextStyle(fontWeight: FontWeight.w700)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          for (final p in paras)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SelectableText.rich(TextSpan(children: [
                if (p is Map && (p['label'] ?? '').toString().isNotEmpty)
                  TextSpan(text: '${p['label']}  ', style: const TextStyle(fontWeight: FontWeight.w800)),
                TextSpan(text: p is Map ? '${p['text']}' : '$p'),
              ]), style: const TextStyle(fontSize: 16, height: 1.55)),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Listening audio (played once, like the exam)
class _Recording extends StatefulWidget {
  const _Recording({required this.recording});
  final Map<String, dynamic> recording;
  @override
  State<_Recording> createState() => _RecordingState();
}

class _RecordingState extends State<_Recording> {
  final _player = AudioPlayer();
  String _status = 'ready';   // ready, loading, playing, done
  Duration _pos = Duration.zero, _dur = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player.positionStream.listen((p) { if (mounted) setState(() => _pos = p); });
    _player.durationStream.listen((d) { if (mounted && d != null) setState(() => _dur = d); });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String? _src(dynamic v) => v is Map ? v['src'] as String? : v is String ? v : null;

  Future<void> _play() async {
    setState(() => _status = 'loading');
    try {
      final r = widget.recording;
      final srcs = [_src(r['intro']), _src(r['src']), _src(r['end'])].whereType<String>().toList();
      final files = <AudioSource>[];
      for (final s in srcs) { files.add(AudioSource.file((await Api.I.media(s)).path)); }
      await _player.setAudioSource(ConcatenatingAudioSource(children: files));
      setState(() => _status = 'playing');
      await _player.play();
      if (mounted) setState(() => _status = 'done');
    } catch (e) {
      if (mounted) { setState(() => _status = 'ready'); toast(context, 'Could not play the recording. Check your connection.'); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final playing = _status == 'playing';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            IconButton.filled(
              onPressed: _status == 'ready' ? _play : null,
              icon: _status == 'loading'
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4))
                  : Icon(playing ? Icons.graphic_eq_rounded : _status == 'done' ? Icons.check_rounded : Icons.play_arrow_rounded),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_status == 'done' ? 'Recording finished' : playing ? 'Listening…' : 'Play the recording (once only)',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: _dur.inMilliseconds == 0 ? 0 : (_pos.inMilliseconds / _dur.inMilliseconds).clamp(0, 1),
                  borderRadius: BorderRadius.circular(4), color: C.blue,
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Writing
class _WritingTask extends StatefulWidget {
  const _WritingTask({required this.task, required this.answers, required this.onAnswer});
  final Map<String, dynamic> task;
  final Map<String, String> answers;
  final void Function(String, String?) onAnswer;
  @override
  State<_WritingTask> createState() => _WritingTaskState();
}

class _WritingTaskState extends State<_WritingTask> {
  late final TextEditingController _c = TextEditingController(text: widget.answers['${widget.task['id']}'] ?? '');

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  int get _words => _c.text.trim().isEmpty ? 0 : _c.text.trim().split(RegExp(r'\s+')).length;

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    final min = (t['min_words'] as num?)?.toInt() ?? 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${t['text']}', style: const TextStyle(fontSize: 16, height: 1.5)),
            if (t['image'] is String) ...[const SizedBox(height: 12), _MediaImage(path: t['image'] as String)],
          ]),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _c,
        minLines: 12,
        maxLines: null,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: TextInputType.multiline,
        onChanged: (v) { setState(() {}); widget.onAnswer('${t['id']}', v); },
        decoration: InputDecoration(hintText: 'Write your answer here', border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
      ),
      const SizedBox(height: 6),
      Text('$_words words${min > 0 ? ' · at least $min' : ''}', textAlign: TextAlign.right,
          style: TextStyle(color: _words >= min ? C.green : Theme.of(context).hintColor, fontWeight: FontWeight.w600)),
    ]);
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
      if (mounted) toast(context, 'Allow the microphone to answer the Speaking questions.');
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
      if (mounted) { setState(() => _status = 'ready'); toast(context, 'Something went wrong. Please try this question again.'); }
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
        Text.rich(TextSpan(children: [
          TextSpan(text: '$number  ', style: const TextStyle(fontWeight: FontWeight.w800, color: C.accent)),
          TextSpan(text: '${q['text'] ?? ''}'),
        ]), style: const TextStyle(fontSize: 15.5, height: 1.4)),
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
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Results')),
      body: Loader<Map<String, dynamic>>(
        load: () => Api.I.get('/api/app/results/$attemptId'),
        build: (context, r, reload) {
          final secs = (r['sections'] as List).cast<Map>();
          final overall = r['overall'];
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text('${r['test']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            if (overall != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    Text('Overall band', style: TextStyle(color: Theme.of(context).hintColor)),
                    Text('$overall', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: C.accent)),
                  ]),
                ),
              ),
            const SizedBox(height: 8),
            for (final s in secs)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    leading: Icon(sectionIcons[s['key']], color: sectionColors[s['key']]),
                    title: Text('${s['key']}'[0].toUpperCase() + '${s['key']}'.substring(1)),
                    subtitle: s['pending'] == true
                        ? const Text('Being marked: pull down to refresh in a minute')
                        : s['raw'] != null ? Text('${s['raw']} / ${s['total']} correct') : null,
                    trailing: Text(s['band'] == null ? '…' : '${s['band']}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            for (var i = 0; i < secs.length; i++)
              if (secs[i]['key'] == 'listening' || secs[i]['key'] == 'reading')
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.fact_check_rounded, size: 18),
                    label: Text('Review ${'${secs[i]['key']}'[0].toUpperCase()}${'${secs[i]['key']}'.substring(1)} answers'),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReviewScreen(attemptId: attemptId, section: i))),
                  ),
                ),
          ]);
        },
      ),
    );
  }
}

/// Every question number of the section in one row: answered ones filled; a tap opens that part and
/// brings the question into view.
class _NumberBar extends StatelessWidget {
  const _NumberBar({required this.parts, required this.answers, required this.keyFor});
  final List<Map> parts;
  final Map<String, String> answers;
  final GlobalKey Function(String) keyFor;

  @override
  Widget build(BuildContext context) {
    final items = <({String label, String qid, int part})>[];
    for (var pi = 0; pi < parts.length; pi++) {
      for (final g in (parts[pi]['groups'] as List? ?? []).cast<Map>()) {
        for (final q in (g['questions'] as List? ?? []).cast<Map>()) {
          final label = q['numbers'] is List ? (q['numbers'] as List).join('–') : '${q['number']}';
          items.add((label: label, qid: '${q['id']}', part: pi));
        }
      }
    }
    final done = items.where((i) => (answers[i.qid] ?? '').isNotEmpty).length;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 6,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(children: [
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 6),
              child: Text('$done/${items.length}', style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 11),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, i) {
                  final it = items[i];
                  final answered = (answers[it.qid] ?? '').isNotEmpty;
                  return InkWell(
                    borderRadius: BorderRadius.circular(9),
                    onTap: () {
                      DefaultTabController.of(context).animateTo(it.part);
                      Future.delayed(const Duration(milliseconds: 350), () {
                        final ctx = keyFor(it.qid).currentContext;
                        if (ctx != null) Scrollable.ensureVisible(ctx, alignment: .2, duration: const Duration(milliseconds: 300));
                      });
                    },
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 36),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(9),
                        color: answered ? C.accent : (dark ? Colors.white.withValues(alpha: .08) : const Color(0xFF141413).withValues(alpha: .06)),
                      ),
                      child: Text(it.label, style: TextStyle(fontWeight: FontWeight.w700, color: answered ? Colors.white : null)),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A finished Listening or Reading section: every question with your answer, the right one and why.
class ReviewScreen extends StatelessWidget {
  const ReviewScreen({super.key, required this.attemptId, required this.section});
  final int attemptId;
  final int section;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Answers')),
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
                      Text('Your answer: ${answers['${q['id']}'] ?? '—'}'),
                      if (!ok) Text('Answer: ${m['answer'] is List ? (m['answer'] as List).join(' / ') : m['answer'] ?? ''}',
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
