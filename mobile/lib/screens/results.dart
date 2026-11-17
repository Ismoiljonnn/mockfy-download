// A finished attempt as the website's results page shows it: bands, the examiner's feedback, Writing
// criteria, tips and model answers, Speaking statistics and your recordings, and Listening / Reading by type.
import 'package:flutter/material.dart';

import '../i18n.dart';
import 'package:just_audio/just_audio.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'exam.dart' show ReviewScreen;
import 'tests.dart';

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
String _band(Object? v) => v == null ? '–' : (v is num ? (v == v.roundToDouble() ? v.toStringAsFixed(1) : '$v') : '$v');

class ResultsView extends StatelessWidget {
  const ResultsView({super.key, required this.attemptId});
  final int attemptId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Results'))),
      body: Loader<Map<String, dynamic>>(
        load: () => Api.I.get('/api/app/results/$attemptId'),
        build: (context, r, reload) {
          final secs = (r['sections'] as List).cast<Map>();
          final overall = r['overall'];
          return RefreshIndicator(
            onRefresh: () async => reload(),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Text('${r['test']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              if (overall != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(children: [
                      Text(tr('Overall band'), style: TextStyle(color: Theme.of(context).hintColor)),
                      Text(_band(overall), style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: C.accent)),
                    ]),
                  ),
                ),
              for (var i = 0; i < secs.length; i++) _Section(attemptId: attemptId, index: i, s: secs[i].cast<String, dynamic>()),
            ]),
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.attemptId, required this.index, required this.s});
  final int attemptId;
  final int index;
  final Map<String, dynamic> s;

  @override
  Widget build(BuildContext context) {
    final key = '${s['key']}';
    final hint = Theme.of(context).hintColor;
    final kids = <Widget>[
      Row(children: [
        Icon(sectionIcons[key], color: sectionColors[key]),
        const SizedBox(width: 8),
        Expanded(child: Text(_cap(key), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
        Text(s['band'] == null ? '…' : _band(s['band']), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
      ]),
    ];
    if (s['pending'] == true) {
      kids.add(Padding(padding: const EdgeInsets.only(top: 8), child: Text(tr('Being marked: pull down to refresh in a minute'), style: TextStyle(color: hint))));
    } else {
      if (s['feedback'] is Map) kids.add(_Feedback(fb: (s['feedback'] as Map).cast<String, dynamic>()));
      if (key == 'writing') {
        for (final t in ((s['tasks'] as List?) ?? []).cast<Map>()) { kids.add(_WritingTask(t: t.cast<String, dynamic>())); }
      } else if (key == 'speaking') {
        kids.add(_Speaking(attemptId: attemptId, s: s));
      } else {
        if (s['raw'] != null) kids.add(Padding(padding: const EdgeInsets.only(top: 6), child: Text('${s['raw']} / ${s['total']} correct', style: TextStyle(color: hint))));
        final by = ((s['byType'] as Map?) ?? {});
        if (by.isNotEmpty) {
          kids.add(Padding(padding: EdgeInsets.fromLTRB(0, 14, 0, 6), child: Text(tr('By question type'), style: TextStyle(fontWeight: FontWeight.w700))));
          for (final e in by.entries) {
            final v = (e.value as Map);
            final total = (v['total'] as num?) ?? 0, ok = (v['correct'] as num?) ?? 0;
            final pct = total == 0 ? 0.0 : ok / total;
            kids.add(Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(flex: 4, child: Text(_cap('${e.key}'.replaceAll('_', ' ')), maxLines: 1, overflow: TextOverflow.ellipsis)),
                Expanded(flex: 5, child: LinearProgressIndicator(value: pct, minHeight: 6, borderRadius: BorderRadius.circular(4),
                    color: pct >= .7 ? C.green : pct >= .5 ? C.gold : C.red)),
                SizedBox(width: 48, child: Text('$ok/$total', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
              ]),
            ));
          }
        }
        kids.add(Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.fact_check_rounded, size: 18),
            label: Text(tr('Review answers')),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReviewScreen(attemptId: attemptId, section: index))),
          ),
        ));
      }
    }
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: kids)),
    );
  }
}

List<String> _strs(Object? v) => v is List ? [for (final x in v) '$x'] : const [];

Widget _bullets(List<String> items, {Color? dot}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final x in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 7, right: 8), child: Icon(Icons.circle, size: 6, color: dot)),
            Expanded(child: Text(x, style: const TextStyle(height: 1.4))),
          ]),
        ),
    ]);

Widget _h(String t) => Padding(padding: const EdgeInsets.fromLTRB(0, 12, 0, 6), child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)));

/// The examiner's feedback: summary, strengths, weaknesses, mistakes with the fix, next steps.
class _Feedback extends StatelessWidget {
  const _Feedback({required this.fb, this.heading});
  final Map<String, dynamic> fb;
  final String? heading;
  @override
  Widget build(BuildContext context) {
    final mistakes = ((fb['mistakes'] as List?) ?? []).cast<Map>();
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: C.accent.withValues(alpha: .07)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.auto_awesome_rounded, color: C.accent, size: 18),
          const SizedBox(width: 6),
          Expanded(child: Text('Examiner feedback${heading == null ? '' : ' · $heading'}', style: const TextStyle(fontWeight: FontWeight.w800))),
        ]),
        if ('${fb['summary'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${fb['summary']}', style: const TextStyle(height: 1.4))),
        if (_strs(fb['strengths']).isNotEmpty) ...[_h('Strengths'), _bullets(_strs(fb['strengths']), dot: C.green)],
        if (_strs(fb['weaknesses']).isNotEmpty) ...[_h('Weaknesses'), _bullets(_strs(fb['weaknesses']), dot: C.red)],
        if (mistakes.isNotEmpty) ...[
          _h('Mistakes'),
          for (final m in mistakes)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(TextSpan(children: [
                  TextSpan(text: '${m['wrong'] ?? ''}', style: const TextStyle(decoration: TextDecoration.lineThrough, color: C.red)),
                  const TextSpan(text: '  →  '),
                  TextSpan(text: '${m['fix'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700, color: C.green)),
                ])),
                if ('${m['why'] ?? ''}'.isNotEmpty) Text('${m['why']}', style: TextStyle(fontSize: 13, color: Theme.of(context).hintColor)),
              ]),
            ),
        ],
        if (_strs(fb['tips']).isNotEmpty) ...[_h('Next steps'), _bullets(_strs(fb['tips']), dot: C.blue)],
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value, label;
  @override
  Widget build(BuildContext context) => Container(
        width: 140,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: Theme.of(context).dividerColor)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
        ]),
      );
}

const _wcrit = [('task', 'Task achievement / response'), ('coherence', 'Coherence and cohesion'), ('lexical', 'Lexical resource'), ('grammar', 'Grammar range and accuracy')];
const _scrit = [('fluency', 'Fluency and coherence'), ('lexical', 'Lexical resource'), ('grammar', 'Grammar range and accuracy'), ('pronunciation', 'Pronunciation')];

class _WritingTask extends StatelessWidget {
  const _WritingTask({required this.t});
  final Map<String, dynamic> t;
  @override
  Widget build(BuildContext context) {
    final name = t['type'] == 'task1' ? 'Task 1' : 'Task 2';
    final crit = ((t['criteria'] as Map?) ?? {});
    final st = ((t['stats'] as Map?) ?? {});
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
          Text(_band(t['band']), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: C.accent)),
        ]),
        if ('${t['text'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${t['text']}', style: TextStyle(fontSize: 13, color: Theme.of(context).hintColor))),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final c in _wcrit) _Stat(_band(crit[c.$1]), c.$2)]),
        if (st['words'] != null) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _Stat('${st['words']}', 'Words (min ${st['min_words'] ?? ''})'),
            _Stat('${st['paragraphs'] ?? '–'}', 'Paragraphs'),
            _Stat('${st['avg_sentence'] ?? '–'}', 'Words per sentence'),
            _Stat('${st['linking_per_100'] ?? '–'}', 'Linking words per 100'),
          ]),
        ],
        if ('${t['summary'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text('Examiner: ${t['summary']}', style: const TextStyle(height: 1.4))),
        if (_strs(t['tips']).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: _bullets(_strs(t['tips']), dot: C.blue)),
        if (t['feedback'] is Map) _Feedback(fb: (t['feedback'] as Map).cast<String, dynamic>(), heading: name),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(tr('Your answer')),
          children: [Align(alignment: Alignment.centerLeft, child: SelectableText('${t['answer'] ?? 'No answer.'}'))],
        ),
        if ('${t['model_answer'] ?? ''}'.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(tr('Model answer (band 8-9)'), style: TextStyle(color: C.green)),
            children: [Align(alignment: Alignment.centerLeft, child: SelectableText('${t['model_answer']}'))],
          ),
      ]),
    );
  }
}

class _Speaking extends StatefulWidget {
  const _Speaking({required this.attemptId, required this.s});
  final int attemptId;
  final Map<String, dynamic> s;
  @override
  State<_Speaking> createState() => _SpeakingState();
}

class _SpeakingState extends State<_Speaking> {
  final _player = AudioPlayer();
  String? _playing;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _play(String id) async {
    if (_playing == id) { await _player.stop(); setState(() => _playing = null); return; }
    setState(() => _playing = id);
    try {
      final f = await Api.I.media('/api/attempts/${widget.attemptId}/recordings/$id');
      await _player.setFilePath(f.path);
      await _player.play();
    } catch (_) {
      if (mounted) toast(context, tr('Could not play the recording.'));
    }
    if (mounted) setState(() => _playing = null);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final crit = ((s['criteria'] as Map?) ?? {});
    final st = ((s['stats'] as Map?) ?? {});
    final hint = Theme.of(context).hintColor;
    final prompts = ((s['prompts'] as List?) ?? []).cast<Map>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 12),
      if (s['has_transcript'] == false)
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(tr('No words could be made out in the recordings, so only fluency could be estimated.'), style: TextStyle(color: hint))),
      Wrap(spacing: 8, runSpacing: 8, children: [for (final c in _scrit) _Stat(crit[c.$1] == null ? 'Not assessed' : _band(crit[c.$1]), c.$2)]),
      if (st.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (st['words'] != null) _Stat('${st['words']}', 'Words spoken'),
          if (st['words_per_minute'] != null) _Stat('${st['words_per_minute']}', 'Words per minute'),
          if (st['long_pauses_per_minute'] != null) _Stat('${st['long_pauses_per_minute']}', 'Long pauses / min'),
          if (st['fillers_per_100'] != null) _Stat('${st['fillers_per_100']}', '"um / uh" per 100 words'),
          if (st['linking_per_100'] != null) _Stat('${st['linking_per_100']}', 'Linking words per 100'),
        ]),
      ],
      if ('${s['summary'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text('Examiner: ${s['summary']}', style: const TextStyle(height: 1.4))),
      if (_strs(s['tips']).isNotEmpty) ...[_h('How to improve'), _bullets(_strs(s['tips']), dot: C.blue)],
      _h('Your answers'),
      for (var i = 0; i < prompts.length; i++)
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          leading: CircleAvatar(radius: 13, backgroundColor: (prompts[i]['recorded'] == true ? C.green : C.red).withValues(alpha: .15),
              child: Text('${i + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800))),
          title: Text('${prompts[i]['text'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(prompts[i]['recorded'] == true ? '${((prompts[i]['duration'] as num?) ?? 0).round()} s · ${prompts[i]['words'] ?? 0} words' : 'not answered'),
          children: [
            if (prompts[i]['recorded'] == true) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: Icon(_playing == '${prompts[i]['id']}' ? Icons.stop_rounded : Icons.play_arrow_rounded),
                  label: Text(_playing == '${prompts[i]['id']}' ? tr('Stop') : 'Play my answer'),
                  onPressed: () => _play('${prompts[i]['id']}'),
                ),
              ),
              Align(alignment: Alignment.centerLeft, child: Text('${prompts[i]['transcript'] ?? 'No transcript.'}', style: TextStyle(color: hint))),
              const SizedBox(height: 8),
            ],
          ],
        ),
    ]);
  }
}
