// "More": everything that is not a tab. Lists live in the app; games, vocabulary, shadowing, the Speaking
// Room and Mock Day open inside the app, already signed in.
import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../notify.dart';
import '../theme.dart';
import '../webpage.dart';
import '../widgets.dart';
import 'exam.dart';
import 'games.dart';
import 'mockday.dart';
import 'profile.dart';
import 'settings.dart';
import 'shop.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key, required this.me, required this.onSignedOut});
  final Map<String, dynamic> me;
  final VoidCallback onSignedOut;

  void _go(BuildContext context, Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    Widget tile(IconData icon, Color color, String title, Widget page, {Widget? trailing}) => ListTile(
          leading: Container(
            width: 38, height: 38,
            decoration: BoxDecoration(color: color.withValues(alpha: .15), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 21),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
          onTap: () => _go(context, page),
        );
    Widget group(String title, List<Widget> items) => Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(title.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .6, color: Theme.of(context).hintColor))),
            Card(child: Column(children: items)),
          ]),
        );
    final user = '${me['username']}';
    final on = ((me['features'] as Map?) ?? {}).cast<String, dynamic>();   // what the website has switched off stays hidden
    return Scaffold(
      appBar: AppBar(title: const Text('More'), actions: [
        IconButton(tooltip: 'Search', icon: const Icon(Icons.search_rounded), onPressed: () => _go(context, const SearchScreen())),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: Avatar(url: me['avatar'] as String?, initial: '${me['name']}'.isEmpty ? '?' : '${me['name']}'[0].toUpperCase(), size: 48),
            title: Row(children: [
              Flexible(child: Text('${me['name']}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
              if (me['isPro'] == true) ...[const SizedBox(width: 6), const ProTick()],
            ]),
            subtitle: Text('@$user · My profile'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _go(context, ProfileScreen(username: user, onSignedOut: onSignedOut)),
          ),
        ),
        group('Practise', [
          tile(Icons.sports_esports_rounded, C.accent, 'Games', const GamesScreen()),
          tile(Icons.style_rounded, C.green, 'My words', const WordsReviewScreen()),
          tile(Icons.event_rounded, C.gold, 'Mock Day', const MockDayScreen()),
        ]),
        group('Me', [
          ValueListenableBuilder<int>(
            valueListenable: Notify.I.unread,
            builder: (context, n, _) => tile(Icons.notifications_rounded, C.red, 'Notifications', const NotificationsScreen(),
                trailing: n > 0 ? Badge(label: Text('$n')) : null),
          ),
          tile(Icons.history_rounded, C.blue, 'My results', const HistoryScreen()),
          tile(Icons.lightbulb_rounded, C.gold, 'Recommendations', const RecommendationsScreen()),
          if (on['friends'] == true) tile(Icons.people_alt_rounded, C.green, 'Friends', FriendsScreen(username: user)),
          tile(Icons.storefront_rounded, C.accent, 'Shop', ShopScreen(onSignedOut: onSignedOut)),
          tile(Icons.settings_rounded, Theme.of(context).hintColor, 'Settings', SettingsScreen(username: user, onSignedOut: onSignedOut)),
        ]),
        group('Help', [
          tile(Icons.menu_book_rounded, C.blue, 'Guide', const WebPage(title: 'Guide', path: '/docs')),
          tile(Icons.chat_rounded, C.green, 'Send feedback', const FeedbackScreen()),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------- Notifications
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    Api.I.post('/api/notifications/seen').then((_) => Notify.I.unread.value = 0).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: Loader<List<Map>>(
        load: () async => ((await Api.I.get('/api/notifications'))['items'] as List).cast<Map>(),
        build: (context, items, reload) => items.isEmpty
            ? ListView(children: const [Padding(padding: EdgeInsets.all(40), child: Center(child: Text('Nothing new yet.')))])
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final n = items[i];
                  return Card(
                    color: n['unread'] == true ? C.accent.withValues(alpha: .1) : null,
                    child: ListTile(
                      title: Text('${n['title']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: '${n['body'] ?? ''}'.isEmpty ? null : Text('${n['body']}'),
                      trailing: appScreenFor('${n['url'] ?? ''}') == null ? null : const Icon(Icons.chevron_right_rounded),
                      onTap: appScreenFor('${n['url'] ?? ''}') == null ? null : () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => appScreenFor('${n['url']}')!)),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------- My results
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My results')),
      body: Loader<Map<String, dynamic>>(
        load: () => Api.I.get('/api/history'),
        build: (context, d, reload) {
          final items = (d['attempts'] as List? ?? []).cast<Map>();
          if (items.isEmpty) {
            return ListView(children: const [Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No finished tests yet.')))]);
          }
          return ListView(padding: const EdgeInsets.all(16), children: [
            for (final a in items)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text('${a['title'] ?? a['testTitle'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${a['scope'] == 'full' ? 'Full mock' : '${a['scope'] ?? ''}'} · ${'${a['completedAt'] ?? a['startedAt'] ?? ''}'.split(' ').first}'),
                  trailing: Text('${a['band'] ?? a['overallBand'] ?? (a['status'] == 'in_progress' ? '…' : '')}',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  onTap: a['id'] == null ? null : () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => a['status'] == 'in_progress'
                          ? ExamScreen(attemptId: (a['id'] as num).toInt())
                          : ResultsScreen(attemptId: (a['id'] as num).toInt()))),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- Recommendations
class RecommendationsScreen extends StatelessWidget {
  const RecommendationsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recommendations')),
      body: Loader<List<Map>>(
        load: () async => ((await Api.I.get('/api/recommendations'))['recommendations'] as List).cast<Map>(),
        build: (context, items, reload) => items.isEmpty
            ? ListView(children: const [Padding(padding: EdgeInsets.all(40),
                child: Center(child: Text('Finish a test and Mockfy suggests what to work on next.', textAlign: TextAlign.center)))])
            : ListView(padding: const EdgeInsets.all(16), children: [
                for (final r in items)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.lightbulb_rounded, color: C.gold),
                      title: Text('${r['title']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${r['description'] ?? ''}'),
                    ),
                  ),
              ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- Friends
class FriendsScreen extends StatelessWidget {
  const FriendsScreen({super.key, required this.username});
  final String username;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Friends')),
      body: Loader<Map<String, dynamic>>(
        load: () async => (((await Api.I.get('/api/app/profile/$username'))['profile'] as Map)['friends'] as Map?)?.cast<String, dynamic>() ?? {},
        build: (context, f, reload) {
          final friends = (f['friends'] as List? ?? []).cast<Map>();
          final incoming = (f['incoming'] as List? ?? []).cast<Map>();
          Widget person(Map p, {Widget? trailing}) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Avatar(url: '${p['avatar'] ?? ''}'.startsWith('http') ? '${p['avatar']}' : null, initial: '${p['initial'] ?? '?'}'),
                  title: Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('@${p['username']}'),
                  trailing: trailing,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(username: '${p['username']}', onSignedOut: () {}))),
                ),
              );
          Future<void> act(Map p, String action) async {
            try {
              await Api.I.post('/api/friends/${p['username']}/$action');
              await reload();
            } on ApiError catch (e) {
              if (context.mounted) toast(context, e.message);
            }
          }
          return ListView(padding: const EdgeInsets.all(16), children: [
            if (incoming.isNotEmpty) ...[
              const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Requests', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              for (final p in incoming)
                person(p, trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: const Icon(Icons.check_circle_rounded, color: C.green), onPressed: () => act(p, 'accept')),
                  IconButton(icon: const Icon(Icons.cancel_rounded), onPressed: () => act(p, 'decline')),
                ])),
              const SizedBox(height: 12),
            ],
            Text('Friends (${friends.length})', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (friends.isEmpty) const Padding(padding: EdgeInsets.all(24),
                child: Text('Find learners on the leaderboard or with search, open their profile and add them.', textAlign: TextAlign.center)),
            for (final p in friends) person(p),
          ]);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- Search
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  List<Map> _groups = [];
  Timer? _t;
  bool _busy = false;

  void _search(String q) {
    _t?.cancel();
    if (q.trim().length < 2) { setState(() => _groups = []); return; }
    _t = Timer(const Duration(milliseconds: 300), () async {
      setState(() => _busy = true);
      try {
        final r = await Api.I.get('/api/search', {'q': q.trim()});
        if (mounted) setState(() => _groups = (r['groups'] as List? ?? []).cast<Map>());
      } on ApiError catch (_) {
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _open(Map it) {
    final url = '${it['url'] ?? ''}';
    final user = RegExp(r'^/u/([^/?#]+)').firstMatch(url);
    final page = user != null ? ProfileScreen(username: user.group(1)!, onSignedOut: () {}) : appScreenFor(url, title: '${it['title']}');
    if (page == null) { toast(context, 'Open this from the menu: ${it['title']}'); return; }
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          autofocus: true,
          onChanged: _search,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(hintText: 'Search tests, lessons, learners, help', border: InputBorder.none),
        ),
        bottom: _busy ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2)) : null,
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        for (final g in _groups) ...[
          Padding(padding: const EdgeInsets.fromLTRB(4, 8, 4, 8), child: Text('${g['name']}', style: const TextStyle(fontWeight: FontWeight.w800))),
          Card(
            child: Column(children: [
              for (final it in (g['items'] as List? ?? []).cast<Map>())
                ListTile(
                  title: Text('${it['title']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${it['snippet'] ?? it['sub'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () => _open(it),
                ),
            ]),
          ),
        ],
      ]),
    );
  }
}

/// The app's own screen for a link of the website (help pages are the only web pages shown).
Widget? appScreenFor(String url, {String title = 'Mockfy'}) {
  final u = Uri.tryParse(url);
  if (u == null || url.isEmpty) return null;
  final path = u.path;
  final res = RegExp(r'^/results/(\d+)').firstMatch(path);
  if (res != null) return ResultsScreen(attemptId: int.parse(res.group(1)!));
  final prof = RegExp(r'^/u/([^/]+)').firstMatch(path);
  if (prof != null) return ProfileScreen(username: prof.group(1)!, onSignedOut: () {});
  if (path.startsWith('/mockday')) return const MockDayScreen();
  if (path.startsWith('/games')) return const GamesScreen();
  if (path.startsWith('/vocab')) return const WordsReviewScreen();
  if (path.startsWith('/notifications')) return const NotificationsScreen();
  if (path.startsWith('/recommendations')) return const RecommendationsScreen();
  if (path.startsWith('/history')) return const HistoryScreen();
  if (path.startsWith('/docs') || path.startsWith('/blog') || path == '/privacy' || path == '/terms') return WebPage(title: title, path: url);
  return null;
}

// ---------------------------------------------------------------- Feedback
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});
  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  String _kind = 'idea';
  final _msg = TextEditingController();
  bool _busy = false;

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      await Api.I.post('/api/feedback', {'kind': _kind, 'message': _msg.text.trim(), 'page': 'android-app'});
      if (mounted) { toast(context, 'Thank you! The Mockfy team reads every message.'); Navigator.pop(context); }
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Send feedback')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Wrap(spacing: 8, children: [
            for (final k in const [('idea', 'Idea'), ('bug', 'Something is wrong'), ('content', 'A test or question'), ('other', 'Other')])
              ChoiceChip(label: Text(k.$2), selected: _kind == k.$1, onSelected: (_) => setState(() => _kind = k.$1)),
          ]),
          const SizedBox(height: 14),
          TextField(
            controller: _msg,
            minLines: 6,
            maxLines: 12,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(hintText: 'Tell us what you think', filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy || _msg.text.trim().length < 5 ? null : _send, child: const Text('Send')),
        ]),
      );
}
