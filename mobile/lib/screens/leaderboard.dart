import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'profile.dart';

/// The weekly league (divisions, promotion zone) and the all-time leaderboard.
class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key, required this.onSignedOut});
  final VoidCallback onSignedOut;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Leagues'),
          bottom: const TabBar(tabs: [Tab(text: 'League'), Tab(text: 'This week'), Tab(text: 'All time')]),
        ),
        body: TabBarView(children: [
          _League(onSignedOut: onSignedOut),
          _Board(period: 'week', onSignedOut: onSignedOut),
          _Board(period: 'all', onSignedOut: onSignedOut),
        ]),
      ),
    );
  }
}

class _League extends StatelessWidget {
  const _League({required this.onSignedOut});
  final VoidCallback onSignedOut;
  @override
  Widget build(BuildContext context) {
    return Loader<Map<String, dynamic>>(
      load: () async => (await Api.I.get('/api/league'))['league'] as Map<String, dynamic>,
      onSignedOut: onSignedOut,
      build: (context, l, reload) {
        final table = (l['table'] as List? ?? []).cast<Map>();
        final promote = (l['promote'] as num?)?.toInt() ?? 0;
        final secs = (l['secondsLeft'] as num?)?.toInt() ?? 0;
        final left = secs > 86400 ? '${secs ~/ 86400} days left' : '${secs ~/ 3600} hours left';
        return ListView(padding: const EdgeInsets.all(16), children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.shield_rounded, color: C.gold, size: 36),
              title: Text('${(l['division'] as Map)['name']} league', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
              subtitle: Text(l['next'] != null ? 'Top $promote move up to ${(l['next'] as Map)['name']} · $left' : left),
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < table.length; i++)
            _Row(p: table[i].cast<String, dynamic>(), rank: (table[i]['rank'] as num?)?.toInt() ?? i + 1, up: i < promote),
        ]);
      },
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
      build: (context, b, reload) {
        final top = (b['top'] as List? ?? []).cast<Map>();
        final me = (b['me'] as Map?)?.cast<String, dynamic>();
        return ListView(padding: const EdgeInsets.all(16), children: [
          if (top.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No one on the board yet. Be the first!'))),
          for (var i = 0; i < top.length; i++) _Row(p: top[i].cast<String, dynamic>(), rank: (top[i]['rank'] as num?)?.toInt() ?? i + 1),
          if (me != null && !top.any((p) => p['isMe'] == true)) ...[
            const Divider(height: 28),
            _Row(p: me, rank: (me['rank'] as num?)?.toInt() ?? 0),
          ],
        ]);
      },
    );
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: me ? C.accent.withValues(alpha: .12) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
              Text('Mockfy bot', style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
            ],
          ]),
          subtitle: p['streak'] != null ? Text('🔥 ${p['streak']}') : null,
          trailing: Text('${p['points'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        ),
      ),
    );
  }
}
