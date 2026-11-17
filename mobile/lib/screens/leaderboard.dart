import 'dart:async';

import 'package:flutter/material.dart';

import '../i18n.dart';

import '../desktop_shell.dart';
import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'profile.dart';

/// The leaderboard: this week and all time.
class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key, required this.onSignedOut});
  final VoidCallback onSignedOut;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: rootBar(context, AppBar(
          leading: menuButton(context),
          title: Text(tr('Leaderboard')),
          bottom: const TabBar(tabs: [Tab(text: 'This week'), Tab(text: 'All time')]),
        )),
        body: TabBarView(children: [
          _Board(period: 'week', onSignedOut: onSignedOut),
          _Board(period: 'all', onSignedOut: onSignedOut),
        ]),
      ),
    );
  }
}

class _Board extends StatelessWidget {
  const _Board({required this.period, required this.onSignedOut});
  final String period;
  final VoidCallback onSignedOut;
  @override
  Widget build(BuildContext context) {
    return Loader<Map<String, dynamic>>(
      load: () async => (await Api.I.get('/api/leaderboard', {'period': period}))['board'] as Map<String, dynamic>,
      onSignedOut: onSignedOut,
      build: (context, b, reload) => _BoardView(board: b, period: period),
    );
  }
}

/// The list with a search box on top; your own row stays pinned at the bottom until you scroll to it.
class _BoardView extends StatefulWidget {
  const _BoardView({required this.board, required this.period});
  final Map<String, dynamic> board;
  final String period;
  @override
  State<_BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<_BoardView> {
  final _scroll = ScrollController();
  final _meKey = GlobalKey();
  final _search = TextEditingController();
  bool _meVisible = false;
  List<Map<String, dynamic>>? _found;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // is my own row on the screen now?
  void _check() {
    final ctx = _meKey.currentContext;
    var visible = false;
    if (ctx != null) {
      final box = ctx.findRenderObject() as RenderBox?;
      final view = context.findRenderObject() as RenderBox?;
      if (box != null && view != null && box.attached && view.attached) {
        final top = box.localToGlobal(Offset.zero, ancestor: view).dy;
        visible = top + box.size.height > 0 && top < view.size.height - 8;
      }
    }
    if (visible != _meVisible && mounted) setState(() => _meVisible = visible);
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) { setState(() => _found = null); return; }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final r = await Api.I.get('/api/leaderboard/search', {'q': q.trim(), 'period': widget.period});
        if (mounted) setState(() => _found = (r['results'] as List).cast<Map>().map((e) => e.cast<String, dynamic>()).toList());
      } on ApiError catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final top = (widget.board['top'] as List? ?? []).cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
    final me = (widget.board['me'] as Map?)?.cast<String, dynamic>();
    final searching = _found != null;
    final rows = searching ? _found! : top;
    final meInList = !searching && top.any((p) => p['isMe'] == true);
    return Stack(children: [
      ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(16, 12, 16, 100), children: [
        TextField(
          controller: _search,
          onChanged: _onSearch,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: tr('Search learners by name or @username'),
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _search.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close_rounded),
                onPressed: () { _search.clear(); setState(() => _found = null); }),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          Padding(padding: const EdgeInsets.all(32),
              child: Center(child: Text(searching ? 'No one found.' : 'No one on the board yet. Be the first!'))),
        for (var i = 0; i < rows.length; i++)
          KeyedSubtree(
            key: rows[i]['isMe'] == true && !searching ? _meKey : null,
            child: _Row(p: rows[i], rank: (rows[i]['rank'] as num?)?.toInt() ?? i + 1),
          ),
        if (me != null && !meInList && !searching) ...[
          const Divider(height: 28),
          KeyedSubtree(key: _meKey, child: _Row(p: me, rank: (me['rank'] as num?)?.toInt() ?? 0)),
        ],
      ]),
      if (me != null && !searching)
        Positioned(
          left: 12, right: 12, bottom: 10,
          child: IgnorePointer(
            ignoring: _meVisible,
            child: AnimatedSlide(
              offset: _meVisible ? const Offset(0, 1.4) : Offset.zero,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: _meVisible ? 0 : 1,
                duration: const Duration(milliseconds: 180),
                child: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(14),
                  color: Theme.of(context).colorScheme.surface,
                  child: _Row(p: me, rank: (me['rank'] as num?)?.toInt() ?? 0),
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.p, required this.rank, this.up = false});
  final Map<String, dynamic> p;
  final int rank;
  final bool up;
  @override
  Widget build(BuildContext context) {
    final medal = rank == 1 ? C.gold : rank == 2 ? const Color(0xFFB8B8C0) : rank == 3 ? const Color(0xFFCD7F32) : null;
    final me = p['isMe'] == true;
    // every learner on a card of their own (filled, no border), yours in the accent colour
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: me ? C.accent.withValues(alpha: dark ? .26 : .14) : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        elevation: me ? 0 : (dark ? 0 : .6),
        shadowColor: Colors.black26,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          onTap: p['username'] == null ? null : () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => ProfileScreen(username: '${p['username']}', onSignedOut: () {}))),
          leading: SizedBox(
            width: 76,
            child: Row(children: [
              SizedBox(
                width: 28,
                child: medal != null ? Icon(Icons.emoji_events_rounded, color: medal, size: 22)
                    : Text('$rank', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, color: up ? C.green : null)),
              ),
              const SizedBox(width: 8),
              Avatar(url: p['avatar'] as String?, initial: '${p['initial'] ?? '?'}', size: 38),
            ]),
          ),
          title: Row(children: [
            Flexible(child: Text('${p['name']}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
            if (p['pro'] == true) ...[const SizedBox(width: 4), const ProTick(size: 16)],
            if (p['bot'] == true) ...[
              const SizedBox(width: 6),
              Text(tr('Mockfy bot'), style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
            ],
          ]),
          subtitle: p['streak'] != null ? Text('🔥 ${p['streak']}') : null,
          trailing: Text('${p['points'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        ),
      ),
    );
  }
}
