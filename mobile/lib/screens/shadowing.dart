// Shadowing, as on the website: a video plays one sentence, stops, and you say it after the speaker;
// then the next sentence. The video is YouTube's own player; everything around it is the app's.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../api.dart';
import '../i18n.dart';
import '../prefs.dart';
import '../theme.dart';
import '../widgets.dart';

class ShadowingScreen extends StatefulWidget {
  const ShadowingScreen({super.key});
  @override
  State<ShadowingScreen> createState() => _ShadowingScreenState();
}

class _ShadowingScreenState extends State<ShadowingScreen> {
  Key _k = UniqueKey();
  String _filter = 'all';
  final _q = TextEditingController();
  final List<Map> _found = [];
  String _next = '';
  bool _searching = false;
  String? _searchError;
  Set<String> _savedIds = {};

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  // YouTube, through the website: a filter (TED, BBC, songs and more) or your own words
  Future<void> _search({bool more = false}) async {
    if (_searching) return;
    setState(() { _searching = true; _searchError = null; if (!more) { _found.clear(); _next = ''; } });
    try {
      final r = await Api.I.get('/api/shadowing/feed', {'f': _filter, 'q': _q.text.trim(), if (more && _next.isNotEmpty) 'page': _next});
      setState(() { _found.addAll(((r['items'] as List?) ?? []).cast<Map>()); _next = '${r['next'] ?? ''}'; });
    } on ApiError catch (e) {
      setState(() => _searchError = e.message);
    }
    if (mounted) setState(() => _searching = false);
  }

  Future<void> _watch(String yid, String title, List? segments, bool auto) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ShadowWatch(yid: yid, title: title, segments: segments, auto: auto, saved: _savedIds.contains(yid))));
    if (mounted) setState(() => _k = UniqueKey());
  }

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Shadowing'))),
      body: Loader<Map<String, dynamic>>(
        key: _k,
        load: () => Api.I.get('/api/app/shadowing'),
        build: (context, d, reload) {
          final vids = ((d['videos'] as List?) ?? []).cast<Map>();
          final saved = ((d['saved'] as List?) ?? []).cast<Map>();
          final auto = d['auto'] == true;
          final feed = d['feed'] == true;
          final filters = ((d['filters'] as List?) ?? []).cast<Map>();
          _savedIds = saved.map((v) => '${v['youtube_id']}').toSet();
          Widget card(String yid, String title, String sub, List? segments) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _watch(yid, title, segments, auto),
                  child: Row(children: [
                    Image.network('https://i.ytimg.com/vi/$yid/mqdefault.jpg', width: 128, height: 72, fit: BoxFit.cover,
                        errorBuilder: (c, e, st) => const SizedBox(width: 128, height: 72)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: hint)),
                      ]),
                    ),
                    if (_savedIds.contains(yid)) const Padding(padding: EdgeInsets.only(right: 8), child: Icon(Icons.bookmark_rounded, color: C.gold, size: 20)),
                    const SizedBox(width: 8),
                  ]),
                ),
              );
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text(tr('Listen to one sentence, then say it the same way. It builds fluency and pronunciation for IELTS Speaking.'),
                style: TextStyle(color: hint)),
            if (feed) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _q,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  hintText: tr('Search YouTube: a song, a film, a topic'),
                  prefixIcon: const Icon(Icons.search_rounded),
                  isDense: true,
                  suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward_rounded), onPressed: _search),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 40,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final f in filters)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(tr('${f['label']}')),
                        selected: _filter == f['id'] && _found.isNotEmpty,
                        onSelected: (_) { setState(() => _filter = '${f['id']}'); _search(); },
                      ),
                    ),
                ]),
              ),
              if (_searchError != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_searchError!, style: const TextStyle(color: C.red))),
              if (_found.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (final v in _found) card('${v['id']}', '${v['title']}', '${v['channel'] ?? ''}', null),
                if (_next.isNotEmpty)
                  OutlinedButton(onPressed: _searching ? null : () => _search(more: true), child: Text(tr('Show more'))),
              ],
              if (_searching) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
            ],
            const SizedBox(height: 14),
            if (vids.isNotEmpty)
              Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 8), child: Text(tr('Picked for you'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
            if (vids.isEmpty && saved.isEmpty && !feed) Center(child: Padding(padding: const EdgeInsets.all(30), child: Text(tr('No videos yet.')))),
            for (final v in vids)
              card('${v['youtube_id']}', '${v['title']}', [if (v['level'] != null) '${v['level']}', tr('{n} sentences', {'n': v['count'] ?? 0})].join(' · '),
                  v['segments'] as List?),
            if (saved.isNotEmpty) ...[
              Padding(padding: const EdgeInsets.fromLTRB(4, 12, 4, 8), child: Text(tr('Saved'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              for (final v in saved) card('${v['youtube_id']}', '${v['title'] ?? ''}', '', null),
            ],
          ]);
        },
      ),
    );
  }
}

const _page = '''<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body{margin:0;background:#000;height:100%;overflow:hidden}#p{width:100vw;height:100vh}</style></head><body><div id="p"></div>
<script src="https://www.youtube.com/iframe_api"></script><script>
var player, stopAt = null, tick = null;
function send(o){ App.postMessage(JSON.stringify(o)); }
function onYouTubeIframeAPIReady(){
  player = new YT.Player('p', { videoId: '__YID__', playerVars: { playsinline: 1, rel: 0, modestbranding: 1, controls: 0, disablekb: 1 },
    events: { onReady: function(){ send({ready: true, dur: player.getDuration()}); } } });
}
function playSeg(s, e, rate){
  clearInterval(tick); stopAt = e; player.setPlaybackRate(rate); player.seekTo(s, true); player.playVideo();
  tick = setInterval(function(){ var t = player.getCurrentTime(); send({t: t});
    if (stopAt !== null && t >= stopAt - 0.08){ clearInterval(tick); player.pauseVideo(); send({end: true}); } }, 120);
}
function stop(){ clearInterval(tick); stopAt = null; if (player) player.pauseVideo(); }
</script></body></html>''';

class ShadowWatch extends StatefulWidget {
  const ShadowWatch({super.key, required this.yid, required this.title, this.segments, this.auto = false, this.saved = false});
  final bool saved;
  final String yid;
  final String title;
  final List? segments;
  final bool auto;
  @override
  State<ShadowWatch> createState() => _ShadowWatchState();
}

class _ShadowWatchState extends State<ShadowWatch> {
  late final WebViewController _web;
  List<Map> _segs = [];
  int _i = 0, _said = 0;
  String _state = 'loading';      // loading, playing, turn, paused, done
  double _rate = 1;
  double _turnLeft = 0;
  Timer? _turn;
  bool _ready = false;
  String _note = '';
  late bool _saved = widget.saved;

  Future<void> _toggleSave() async {
    final on = !_saved;
    setState(() => _saved = on);
    try {
      await Api.I.post('/api/shadowing/save', {'v': widget.yid, 'title': widget.title, 'on': on});
      if (mounted) toast(context, on ? tr('Saved') : tr('Removed'));
    } on ApiError catch (e) {
      if (mounted) { setState(() => _saved = !on); toast(context, e.message); }
    }
  }

  @override
  void initState() {
    super.initState();
    _segs = (widget.segments ?? []).cast<Map>();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('App', onMessageReceived: (m) => _message(m.message))
      ..loadHtmlString(_page.replaceAll('__YID__', widget.yid), baseUrl: kBaseUrl);
  }

  @override
  void dispose() {
    _turn?.cancel();
    if (_said > 0) Api.I.post('/api/shadowing/done', {'said': _said}).catchError((_) => <String, dynamic>{});
    super.dispose();
  }

  Future<void> _message(String raw) async {
    final m = jsonDecode(raw) as Map;
    if (m['ready'] == true) {
      _ready = true;
      if (_segs.isEmpty && widget.auto) await _autoSegments();
      if (_segs.isEmpty) {
        // no sentences: stop every few seconds instead
        final dur = ((m['dur'] as num?) ?? 0).toDouble();
        _segs = [for (double s = 0; s < dur; s += 5) {'s': s, 'e': (s + 5) > dur ? dur : s + 5, 't': ''}];
      }
      if (mounted) _play();
    } else if (m['end'] == true) {
      _yourTurn();
    }
  }

  Future<void> _autoSegments() async {
    setState(() => _note = tr('Getting the sentences…'));
    try {
      var r = await Api.I.get('/api/shadowing/auto', {'v': widget.yid});
      for (var n = 0; '${r['job'] ?? ''}'.isNotEmpty && n < 40; n++) {
        if (mounted) setState(() => _note = tr('Writing down the words…'));
        await Future<void>.delayed(const Duration(seconds: 3));
        r = await Api.I.get('/api/shadowing/auto', {'v': widget.yid, 'job': '${r['job']}'});
      }
      _segs = ((r['segments'] as List?) ?? []).cast<Map>();
    } on ApiError { /* stop every few seconds */ }
    if (mounted) setState(() => _note = '');
  }

  void _play() {
    if (!_ready || _segs.isEmpty) return;
    _turn?.cancel();
    final s = _segs[_i];
    setState(() => _state = 'playing');
    _web.runJavaScript('playSeg(${s['s']}, ${s['e']}, $_rate)');
  }

  void _yourTurn() {
    final s = _segs[_i];
    final secs = ((((s['e'] as num) - (s['s'] as num)) * 1.4 / _rate) + .6).clamp(1.5, 20).toDouble();
    if (Prefs.I.haptics.value) HapticFeedback.selectionClick();
    setState(() { _state = 'turn'; _turnLeft = secs; });
    _turn = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (!mounted) return;
      setState(() => _turnLeft -= .1);
      if (_turnLeft <= 0) { t.cancel(); _said++; _next(); }
    });
  }

  void _next() {
    if (_i + 1 >= _segs.length) { _finish(); return; }
    setState(() => _i++);
    _play();
  }

  void _prev() { setState(() => _i = _i > 0 ? _i - 1 : 0); _play(); }

  void _pause() {
    _turn?.cancel();
    _web.runJavaScript('stop()');
    setState(() => _state = 'paused');
  }

  Future<void> _finish() async {
    _web.runJavaScript('stop()');
    setState(() => _state = 'done');
    final n = _said;
    _said = 0;
    try {
      final r = await Api.I.post('/api/shadowing/done', {'said': n});
      final got = (r['points'] as num?) ?? 0;
      if (mounted && got > 0) toast(context, tr('+{n} points', {'n': got}));
    } on ApiError { /* the practice still counts for you */ }
  }

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    final seg = _segs.isEmpty ? null : _segs[_i];
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis), actions: [
        IconButton(tooltip: _saved ? tr('Saved') : tr('Save'), onPressed: _toggleSave,
            icon: Icon(_saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, color: _saved ? C.gold : null)),
        PopupMenuButton<double>(
          tooltip: tr('Speed'),
          icon: Text('${_rate}x', style: const TextStyle(fontWeight: FontWeight.w800)),
          onSelected: (v) => setState(() => _rate = v),
          itemBuilder: (_) => [for (final v in [.75, 1.0]) PopupMenuItem(value: v, child: Text('${v}x'))],
        ),
      ]),
      body: Column(children: [
        AspectRatio(aspectRatio: 16 / 9, child: WebViewWidget(controller: _web)),
        LinearProgressIndicator(value: _segs.isEmpty ? 0 : (_i + (_state == 'done' ? 1 : 0)) / _segs.length, minHeight: 4, color: C.accent),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(20), children: [
            if (_note.isNotEmpty) Text(_note, textAlign: TextAlign.center, style: TextStyle(color: hint)),
            if (_state == 'done') ...[
              const SizedBox(height: 20),
              const Icon(Icons.celebration_rounded, size: 56, color: C.gold),
              Text(tr('Well done!'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              FilledButton(onPressed: () { setState(() => _i = 0); _play(); }, child: Text(tr('Again'))),
            ] else if (seg != null) ...[
              Text(tr('Sentence {n} of {m}', {'n': _i + 1, 'm': _segs.length}), textAlign: TextAlign.center, style: TextStyle(color: hint)),
              const SizedBox(height: 12),
              Text('${seg['t'] ?? ''}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.4)),
              const SizedBox(height: 20),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: (_state == 'turn' ? C.green : C.blue).withValues(alpha: .1),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(_state == 'turn' ? Icons.mic_rounded : _state == 'paused' ? Icons.pause_rounded : Icons.hearing_rounded,
                      color: _state == 'turn' ? C.green : C.blue),
                  const SizedBox(width: 8),
                  Text(_state == 'turn'
                      ? tr('Your turn: say it ({n} s)', {'n': _turnLeft.ceil()})
                      : _state == 'paused' ? tr('Paused') : _state == 'loading' ? tr('Loading…') : tr('Listen…'),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ]),
              ),
            ],
          ]),
        ),
        if (_state != 'done')
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                IconButton.filledTonal(tooltip: tr('Back'), onPressed: _ready ? _prev : null, icon: const Icon(Icons.skip_previous_rounded)),
                IconButton.filledTonal(tooltip: tr('Repeat'), onPressed: _ready ? _play : null, icon: const Icon(Icons.replay_rounded)),
                IconButton.filled(
                  iconSize: 34,
                  tooltip: _state == 'paused' ? tr('Play') : tr('Pause'),
                  onPressed: !_ready ? null : (_state == 'paused' ? _play : _pause),
                  icon: Icon(_state == 'paused' ? Icons.play_arrow_rounded : Icons.pause_rounded),
                ),
                IconButton.filledTonal(tooltip: tr('Next'), onPressed: _ready ? () { _turn?.cancel(); _said++; _next(); } : null, icon: const Icon(Icons.skip_next_rounded)),
              ]),
            ),
          ),
      ]),
    );
  }
}
