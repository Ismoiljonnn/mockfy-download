// The Listening recording as on the website: for every part the examiner's introduction, a silent
// reading pause, the recording and the examiner saying the part has ended. Spoken parts are audio files
// or a script read aloud. It plays once, forwards only, and the place is saved on the server so the
// test goes on from the same second after the app is closed.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

import '../api.dart';
import '../prefs.dart';

class ListeningStatus {
  const ListeningStatus({required this.finished, this.playing = false, this.part = 0, this.kind = '', this.remaining, this.fraction});
  final bool finished;
  final bool playing;
  final int part;
  final String kind;          // intro, prep, play, end
  final double? remaining;    // seconds left of the reading pause
  final double? fraction;     // how far into a spoken segment
}

class _Seg {
  _Seg(this.kind, this.part, {this.rec, this.seconds = 0});
  final String kind;
  final int part;
  final Map? rec;
  final double seconds;
}

class ListeningPlayer extends ChangeNotifier {
  ListeningPlayer({required List<Map> parts, Map? progress, required this.onSave, required this.onPartStart, required this.onFinished, required this.onError}) {
    for (var i = 0; i < parts.length; i++) {
      final rec = (parts[i]['recording'] as Map?) ?? {};
      _segs.add(_Seg('intro', i, rec: rec['intro'] as Map?));
      _segs.add(_Seg('prep', i, seconds: ((rec['prep'] as num?) ?? 30).toDouble()));
      _segs.add(_Seg('play', i, rec: rec));
      _segs.add(_Seg('end', i, rec: rec['end'] as Map?));
    }
    if (progress != null) {
      _seg = (progress['seg'] as num?)?.toInt() ?? 0;
      if (progress['v'] != 2 && _seg > 0) _seg = (_seg ~/ 2) * 4 + 1 + (_seg % 2);
      _pos = ((progress['pos'] as num?) ?? 0).toDouble();
      _finished = progress['finished'] == true;
    }
    if (_seg >= _segs.length) _finished = true;
    _audio.positionStream.listen((p) {
      if (_kindNow == 'audio' && _playing) { _pos = p.inMilliseconds / 1000; notifyListeners(); _save(false); }
    });
    _audio.durationStream.listen((d) { _dur = d; });
  }

  final void Function(Map<String, dynamic>) onSave;
  final void Function(int part) onPartStart;
  final VoidCallback onFinished;
  final void Function(String) onError;

  final List<_Seg> _segs = [];
  final _audio = AudioPlayer();
  final _tts = FlutterTts();
  bool _ttsReady = false;
  int _seg = 0;
  double _pos = 0;
  bool _finished = false;
  bool _playing = false;
  int _token = 0;
  Timer? _timer;
  Duration? _dur;
  String _kindNow = '';
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);
  bool _disposed = false;

  bool get finished => _finished;
  bool get playing => _playing;
  int get partCount => _segs.length ~/ 4;

  Map<String, dynamic> position() => {'seg': _seg, 'pos': (_pos * 10).floor() / 10, 'finished': _finished, 'v': 2};

  ListeningStatus status() {
    if (_finished || _seg >= _segs.length) return const ListeningStatus(finished: true);
    final s = _segs[_seg];
    double? fraction, remaining;
    if (s.kind == 'prep') {
      remaining = (s.seconds - _pos).clamp(0, s.seconds).toDouble();
    } else if (s.rec == null) {
      fraction = 0;
    } else if (s.rec!['type'] == 'audio') {
      final d = _dur?.inMilliseconds ?? 0;
      fraction = d == 0 ? 0 : (_pos * 1000 / d).clamp(0, 1).toDouble();
    } else {
      final n = ((s.rec!['lines'] as List?) ?? []).length;
      fraction = (_pos / (n == 0 ? 1 : n)).clamp(0, 1).toDouble();
    }
    return ListeningStatus(finished: false, playing: _playing, part: s.part, kind: s.kind, remaining: remaining, fraction: fraction);
  }

  void _emit() { if (!_disposed) notifyListeners(); }

  void _save(bool force) {
    final now = DateTime.now();
    if (!force && now.difference(_lastSave).inMilliseconds < 3000) return;
    _lastSave = now;
    if (!_finished) onSave(position());
  }

  Future<void> _stopMedia() async {
    _token++;
    _timer?.cancel();
    _timer = null;
    _kindNow = '';
    try { await _audio.pause(); } catch (_) {}
    if (_ttsReady) { try { await _tts.stop(); } catch (_) {} }
  }

  Future<void> _next() async {
    await _stopMedia();
    _seg += 1;
    _pos = 0;
    if (_seg >= _segs.length) {
      _finished = true;
      _playing = false;
      _emit();
      onFinished();
      return;
    }
    _save(true);
    _run();
  }

  void _runPrep(_Seg s, int my) {
    var last = DateTime.now();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (my != _token) return;
      final now = DateTime.now();
      _pos += now.difference(last).inMilliseconds / 1000;
      last = now;
      if (_pos >= s.seconds) { _next(); } else { _emit(); _save(false); }
    });
    _emit();
  }

  Future<void> _runAudio(_Seg s, int my) async {
    try {
      final file = await Api.I.media('${s.rec!['src']}');
      if (my != _token) return;
      await _audio.setFilePath(file.path);
      await _audio.setVolume(Prefs.I.volume.value);
      if (my != _token) return;
      await _audio.seek(Duration(milliseconds: (_pos * 1000).round()));
      _kindNow = 'audio';
      _emit();
      await _audio.play();              // returns when paused or finished
      if (my != _token) return;
      if (_audio.processingState == ProcessingState.completed) _next();
    } catch (_) {
      if (my != _token) return;
      _playing = false;
      _emit();
      onError('The recording could not be loaded. Check your connection.');
    }
  }

  Future<void> _runScript(_Seg s, int my) async {
    if (!_ttsReady) {
      try {
        await _tts.awaitSpeakCompletion(true);
        await _tts.setSpeechRate(.47);
        await _tts.setVolume(Prefs.I.volume.value);
        _ttsReady = true;
      } catch (_) {}
    }
    final lines = ((s.rec!['lines'] as List?) ?? []).cast<Map>();
    final speakers = ((s.rec!['speakers'] as Map?) ?? {});
    final voices = await _voices();
    final names = <String>[];
    for (final l in lines) { final n = '${l['speaker'] ?? ''}'; if (!names.contains(n)) names.add(n); }
    for (var i = _pos.floor(); i < lines.length; i++) {
      if (my != _token) return;
      _pos = i.toDouble();
      _emit();
      _save(false);
      final line = lines[i];
      final name = '${line['speaker'] ?? ''}';
      final sp = (speakers[name] as Map?) ?? {};
      final accent = '${sp['accent'] ?? 'gb'}'.toLowerCase().contains('us') ? 'en-US' : 'en-GB';
      final female = '${sp['gender'] ?? (names.indexOf(name).isOdd ? 'male' : 'female')}' == 'female';
      try {
        await _tts.setLanguage(accent);
        final v = _pickVoice(voices, accent, female, names.indexOf(name));
        if (v != null) await _tts.setVoice(v);
        await _tts.setPitch(female ? 1.05 : .9);
        await _tts.speak('${line['text'] ?? ''}');
      } catch (_) {}
      if (my != _token) return;
      await Future<void>.delayed(Duration(milliseconds: (((line['pause'] as num?) ?? .4) * 1000).round()));
    }
    if (my == _token) _next();
  }

  List<Map<String, String>>? _voiceList;
  Future<List<Map<String, String>>> _voices() async {
    if (_voiceList != null) return _voiceList!;
    try {
      final raw = (await _tts.getVoices) as List? ?? [];
      _voiceList = [
        for (final v in raw)
          if (v is Map && '${v['locale']}'.toLowerCase().startsWith('en')) {'name': '${v['name']}', 'locale': '${v['locale']}'}
      ];
    } catch (_) {
      _voiceList = [];
    }
    return _voiceList!;
  }

  Map<String, String>? _pickVoice(List<Map<String, String>> all, String accent, bool female, int index) {
    final same = all.where((v) => v['locale']!.replaceAll('_', '-').toLowerCase() == accent.toLowerCase()).toList();
    final pool = same.isNotEmpty ? same : all;
    if (pool.isEmpty) return null;
    final g = pool.where((v) => female ? v['name']!.contains('female') || v['name']!.contains('#f') : v['name']!.contains('#m') || (v['name']!.contains('male') && !v['name']!.contains('female'))).toList();
    final list = g.isNotEmpty ? g : pool;
    return list[index % list.length];
  }

  void _run() {
    if (_finished) { _emit(); return; }
    _playing = true;
    final my = ++_token;
    final s = _segs[_seg];
    if (_pos == 0 && (s.kind == 'intro' || s.kind == 'prep')) onPartStart(s.part);
    if (s.kind == 'prep') {
      _runPrep(s, my);
    } else if (s.rec == null || (s.rec!['type'] != 'audio' && ((s.rec!['lines'] as List?) ?? []).isEmpty)) {
      scheduleMicrotask(() { if (my == _token) _next(); });
    } else if (s.rec!['type'] == 'audio') {
      _runAudio(s, my);
    } else {
      _runScript(s, my);
    }
    _emit();
  }

  void start() { if (!_playing && !_finished) _run(); }

  Future<void> pause() async {
    if (!_playing) return;
    await _stopMedia();
    _playing = false;
    _save(true);
    _emit();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopMedia();
    _audio.dispose();
    super.dispose();
  }
}
