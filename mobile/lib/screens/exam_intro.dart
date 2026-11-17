// Before a section starts, as on the website: what it is (time, questions, parts), its instructions and
// the rules; Listening has a sound check and the volume, Speaking a microphone check. Start begins the clock.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../api.dart';
import '../i18n.dart';
import '../prefs.dart';
import '../theme.dart';
import '../widgets.dart';
import 'tests.dart';

class SectionIntro extends StatefulWidget {
  const SectionIntro({super.key, required this.state, required this.onStart});
  final Map<String, dynamic> state;
  final Future<void> Function() onStart;
  @override
  State<SectionIntro> createState() => _SectionIntroState();
}

class _SectionIntroState extends State<SectionIntro> {
  final _player = AudioPlayer();
  final _rec = AudioRecorder();
  bool _starting = false, _checking = false;
  String? _mic;            // what the microphone check heard
  double _level = 0;
  StreamSubscription<Amplitude>? _amp;

  @override
  void dispose() {
    _amp?.cancel();
    _player.dispose();
    _rec.dispose();
    super.dispose();
  }

  Future<void> _soundCheck() async {
    try {
      await _player.setVolume(Prefs.I.volume.value);
      await _player.setUrl('$kBaseUrl/static/audio/soundcheck.mp3');
      await _player.seek(Duration.zero);
      await _player.play();
    } catch (_) {
      if (mounted) toast(context, tr('Could not play the sound. Check your speakers or headphones and try again.'));
    }
  }

  Future<void> _micCheck() async {
    if (!await _rec.hasPermission()) {
      if (mounted) toast(context, tr('Allow the microphone to answer the Speaking questions.'));
      return;
    }
    setState(() { _checking = true; _mic = null; });
    final path = '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}miccheck.m4a';
    await _rec.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    _amp = _rec.onAmplitudeChanged(const Duration(milliseconds: 120)).listen((a) {
      if (mounted) setState(() => _level = ((a.current + 50) / 50).clamp(0, 1).toDouble());
    });
    await Future<void>.delayed(const Duration(seconds: 4));
    await _amp?.cancel();
    final out = await _rec.stop();
    String heard = '';
    try {
      if (out != null) {
        final r = await Api.I.uploadAnswer('/api/stt/check', File(out), 'audio/mp4');
        heard = r['available'] == false ? '—' : '${r['text'] ?? ''}';
      }
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
    if (mounted) setState(() { _checking = false; _level = 0; _mic = heard; });
  }

  Future<void> _start() async {
    final key = '${(widget.state['section'] as Map)['key']}';
    if (key == 'speaking' && !await _rec.hasPermission()) {
      if (mounted) toast(context, tr('Allow the microphone to answer the Speaking questions.'));
      return;
    }
    setState(() => _starting = true);
    await widget.onStart();
    if (mounted) setState(() => _starting = false);
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    final s = (st['section'] as Map).cast<String, dynamic>();
    final key = '${s['key']}';
    final parts = ((s['parts'] as List?) ?? []).cast<Map>();
    final sections = ((st['sections'] as List?) ?? []);
    final idx = (st['sectionIndex'] as num?)?.toInt() ?? 0;
    final hint = Theme.of(context).hintColor;
    var nQ = 0;
    for (final p in parts) {
      if (key == 'speaking') { nQ += ((p['prompts'] as List?) ?? []).length; continue; }
      if (key == 'writing') { if (p['task'] != null) nQ++; continue; }
      for (final g in ((p['groups'] as List?) ?? []).cast<Map>()) {
        for (final q in ((g['questions'] as List?) ?? []).cast<Map>()) { nQ += q['numbers'] is List ? (q['numbers'] as List).length : 1; }
      }
    }
    Widget fact(String v, String l) => Expanded(
          child: Column(children: [
            Text(v, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            Text(l, style: TextStyle(fontSize: 12, color: hint)),
          ]),
        );
    Widget rule(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.only(top: 6, right: 8), child: Icon(Icons.circle, size: 6)),
            Expanded(child: Text(t, style: const TextStyle(height: 1.4))),
          ]),
        );
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text(sections.length > 1 ? tr('Section {n} of {m}', {'n': idx + 1, 'm': sections.length}) : '', style: TextStyle(color: hint, fontWeight: FontWeight.w700)),
      Row(children: [
        Icon(sectionIcons[key], color: sectionColors[key], size: 30),
        const SizedBox(width: 10),
        Expanded(child: Text('${s['title']}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900))),
      ]),
      Text('${(st['test'] as Map?)?['title'] ?? ''}', style: TextStyle(color: hint)),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(children: [
            fact('${s['duration_min']}', tr('Minutes')),
            if (nQ > 0) fact('$nQ', tr('Questions')),
            fact('${parts.length}', tr('Parts')),
          ]),
        ),
      ),
      if ('${s['instructions'] ?? ''}'.isNotEmpty)
        Padding(padding: const EdgeInsets.only(top: 12), child: Text('${s['instructions']}', style: const TextStyle(height: 1.45))),
      const SizedBox(height: 14),
      rule(tr('The timer starts when you press Start and runs on our server, so closing the app does not reset it.')),
      rule(key == 'speaking'
          ? tr('Each answer is saved as soon as you finish it. A dropped connection does not lose it.')
          : tr('Answers are saved automatically as you type. A dropped connection does not lose them.')),
      rule(tr('Leaving the app pauses the test.')),
      rule(tr('When time runs out, your answers are submitted automatically. You cannot return to a submitted section.')),
      if (key == 'listening')
        Card(
          color: C.blue.withValues(alpha: .08),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr('Check your sound'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 4),
              Text(tr('Use headphones. The recording is heard once only and starts by itself, part by part, with time to read the questions before each part.'),
                  style: TextStyle(color: hint)),
              const SizedBox(height: 8),
              ValueListenableBuilder<double>(
                valueListenable: Prefs.I.volume,
                builder: (context, v, _) => Row(children: [
                  const Icon(Icons.volume_down_rounded),
                  Expanded(child: Slider(value: v, onChanged: (x) { Prefs.I.setVolume(x); _player.setVolume(x); })),
                  const Icon(Icons.volume_up_rounded),
                ]),
              ),
              OutlinedButton.icon(onPressed: _soundCheck, icon: const Icon(Icons.play_arrow_rounded), label: Text(tr('Play sound check'))),
            ]),
          ),
        ),
      if (key == 'speaking')
        Card(
          color: C.accent.withValues(alpha: .08),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr('Check your microphone'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 4),
              Text(_mic == null
                  ? tr('The examiner asks each question aloud and your answers are recorded. Use a quiet room. Say a sentence after you press Test.')
                  : _mic!.isEmpty
                      ? tr('No words were heard. Speak closer to the phone and try again.')
                      : _mic == '—' ? tr('The microphone works.') : tr('We heard: "{t}"', {'t': _mic}),
                  style: TextStyle(color: hint)),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _level, minHeight: 6, borderRadius: BorderRadius.circular(4), color: C.green),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _checking ? null : _micCheck,
                icon: Icon(_checking ? Icons.mic_rounded : Icons.mic_none_rounded),
                label: Text(_checking ? tr('Listening…') : tr('Test microphone')),
              ),
            ]),
          ),
        ),
      const SizedBox(height: 18),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        onPressed: _starting ? null : _start,
        child: _starting
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            : Text(tr('Start {s}', {'s': s['title']})),
      ),
    ]);
  }
}
