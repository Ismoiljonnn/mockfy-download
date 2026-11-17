// The word card, as on the website: one word explained as it is used in its sentence (meaning here,
// pronunciation, synonyms by band, collocations, an example, an IELTS tip), and "Add to my words".
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../api.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets.dart';

final _tts = FlutterTts();

Future<void> _say(String word) async {
  try {
    await _tts.setLanguage('en-GB');
    await _tts.setSpeechRate(.42);
    await _tts.speak(word);
  } catch (_) {}
}

/// The one English word in a selection ("word," -> "word"), or null when it is not one word.
String? oneWord(String text) {
  final w = text.trim().replaceAll(RegExp(r"^[^A-Za-z]+|[^A-Za-z]+$"), '');
  return RegExp(r"^[A-Za-z][A-Za-z'-]*$").hasMatch(w) ? w : null;
}

Future<void> showWordCard(BuildContext context, String word, {String sentence = '', int? attempt}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _WordCard(word: word, sentence: sentence, attempt: attempt),
  );
}

class _WordCard extends StatefulWidget {
  const _WordCard({required this.word, required this.sentence, this.attempt});
  final String word;
  final String sentence;
  final int? attempt;
  @override
  State<_WordCard> createState() => _WordCardState();
}

class _WordCardState extends State<_WordCard> {
  Map<String, dynamic>? _d;
  String? _error;
  bool _saved = false, _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.I.post('/api/vocab/card', {'word': widget.word, 'sentence': widget.sentence, if (widget.attempt != null) 'attempt': widget.attempt});
      if (mounted) setState(() { _d = d; _saved = d['saved'] == true; });
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await Api.I.post('/api/vocab/save', {'word': widget.word, 'sentence': widget.sentence});
      if (mounted) {
        setState(() => _saved = true);
        toast(context, tr('Added. It comes back tomorrow, then after 3, 7, 14 and 30 days.'));
      }
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
    if (mounted) setState(() => _saving = false);
  }

  Widget _sec(String title, Widget child) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .6, color: Theme.of(context).hintColor)),
          const SizedBox(height: 4),
          child,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    Widget body;
    if (_error != null) {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        Image.asset('assets/hudi/sad.png', height: 90),
        const SizedBox(height: 10),
        Text(_error!, textAlign: TextAlign.center),
      ]);
    } else if (_d == null) {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        Image.asset('assets/hudi/thinking.png', height: 80),
        const SizedBox(height: 8),
        Text(tr('Looking it up…'), style: TextStyle(color: hint)),
      ]);
    } else {
      final c = ((_d!['card'] as Map?) ?? {}).cast<String, dynamic>();
      final syn = ((c['synonyms'] as List?) ?? []).cast<Map>();
      final col = ((c['collocations'] as List?) ?? []).map((e) => '$e').toList();
      final a = (_d!['allowance'] as Map?) ?? {};
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(
            child: Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 10, children: [
              Text('${c['word'] ?? widget.word}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
              if ('${c['ipa'] ?? ''}'.isNotEmpty) Text('${c['ipa']}', style: TextStyle(color: hint, fontSize: 16)),
            ]),
          ),
          IconButton.filledTonal(tooltip: tr('Listen'), onPressed: () => _say('${c['word'] ?? widget.word}'), icon: const Icon(Icons.volume_up_rounded)),
        ]),
        Wrap(spacing: 6, children: [
          for (final t in [c['pos'], c['level']])
            if ('${t ?? ''}'.isNotEmpty) Chip(label: Text('$t'), visualDensity: VisualDensity.compact),
        ]),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: C.accent.withValues(alpha: .08)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('In this sentence'), style: TextStyle(fontSize: 11, color: hint)),
            Text('${c['translation'] ?? ''}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            if ('${c['meaning_here'] ?? ''}'.isNotEmpty) Text('${c['meaning_here']}'),
          ]),
        ),
        if ('${c['definition'] ?? ''}'.isNotEmpty) _sec(tr('In simple English'), Text('${c['definition']}')),
        if (syn.isNotEmpty)
          _sec(tr('Synonyms by band'), Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in syn) Chip(label: Text('${s['word']}  ${s['band'] ?? ''}'), visualDensity: VisualDensity.compact),
          ])),
        if (col.isNotEmpty) _sec(tr('Goes with'), Text(col.join(' · '))),
        if ('${c['example'] ?? ''}'.isNotEmpty) _sec(tr('Example'), Text('${c['example']}', style: const TextStyle(fontStyle: FontStyle.italic))),
        if ('${c['tip'] ?? ''}'.isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 14),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: C.gold.withValues(alpha: .12)),
            child: Text('💡 ${c['tip']}'),
          ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: _saved
              ? OutlinedButton.icon(onPressed: null, icon: const Icon(Icons.check_rounded), label: Text(tr('In my words')))
              : FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: C.green),
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.bookmark_add_rounded),
                  label: Text(tr('Add to my words')),
                ),
        ),
        if (a.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              a['pro'] == true ? tr('Pro: word cards without limit') : tr('{n} free cards left today', {'n': a['freeLeft'] ?? 0}),
              style: TextStyle(fontSize: 12, color: hint),
            ),
          ),
      ]);
    }
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .85),
        child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), child: Center(child: body)),
      ),
    );
  }
}

/// A star to keep a word from a game in My words (the games' own "save" on the website).
class SaveWordButton extends StatefulWidget {
  const SaveWordButton({super.key, required this.word, this.sentence = ''});
  final String word;
  final String sentence;
  @override
  State<SaveWordButton> createState() => _SaveWordButtonState();
}

class _SaveWordButtonState extends State<SaveWordButton> {
  bool _on = false, _busy = false;
  @override
  void didUpdateWidget(SaveWordButton old) {
    super.didUpdateWidget(old);
    if (old.word != widget.word) _on = false;
  }

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: _on ? tr('In my words') : tr('Add to my words'),
        onPressed: _on || _busy
            ? null
            : () async {
                setState(() => _busy = true);
                try {
                  await Api.I.post('/api/vocab/save', {'word': widget.word, 'sentence': widget.sentence});
                  if (mounted) { setState(() => _on = true); toast(context, tr('Added to My words')); }
                } on ApiError catch (e) {
                  if (mounted) toast(context, e.message);
                }
                if (mounted) setState(() => _busy = false);
              },
        icon: Icon(_on ? Icons.star_rounded : Icons.star_border_rounded, color: _on ? C.gold : null, size: 28),
      );
}
