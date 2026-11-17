import 'package:flutter/material.dart';

import '../i18n.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'activity.dart';
import '../notify.dart';
import '../webpage.dart';
import 'more.dart';
import 'settings.dart';

const _sections = ['listening', 'reading', 'writing', 'speaking'];

/// A learner's profile; the Pro tick opens what Pro gives. On your own (the Me tab): settings and sign out.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.username, required this.onSignedOut, this.isRoot = false});
  final String username;
  final VoidCallback onSignedOut;
  final bool isRoot;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: isRoot ? menuButton(context) : null, title: isRoot ? Text(tr('Profile')) : _Title(username: username)),
      body: Loader<Map<String, dynamic>>(
        load: () => Api.I.get('/api/app/profile/$username'),
        onSignedOut: onSignedOut,
        build: (context, r, reload) {
          final p = (r['profile'] as Map).cast<String, dynamic>();
          final viewerPro = r['viewerPro'] == true;
          final best = (p['best'] as Map?) ?? {};
          final isMe = p['isMe'] == true;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Center(child: Avatar(url: p['avatar'] as String?, initial: '${p['initial']}', size: 96)),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Flexible(child: Text('${p['name']}', overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800))),
              if (p['isPro'] == true)
                IconButton(
                  tooltip: 'Mockfy Pro',
                  icon: const ProTick(size: 26),
                  onPressed: () => showProSheet(context, who: '${p['name']}', isMe: isMe, viewerPro: viewerPro),
                ),
            ]),
            Text('@${p['username']}', textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).hintColor)),
            if (p['isBot'] == true)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(tr('Mockfy bot · a practice rival run by Mockfy, not a person'), textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12)),
              ),
            const SizedBox(height: 18),
            Row(children: [
              StatTile(icon: Icons.star_rounded, color: C.gold, value: '${p['points'] ?? 0}', label: tr('Points')),
              const SizedBox(width: 10),
              StatTile(icon: Icons.local_fire_department_rounded, color: C.accent, value: '${p['streak'] ?? 0}', label: tr('Streak')),
              const SizedBox(width: 10),
              StatTile(icon: Icons.task_alt_rounded, color: C.green, value: '${p['testsDone'] ?? 0}', label: tr('Tests')),
            ]),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('Best band by section'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 12),
                  Row(children: [
                    for (final s in _sections)
                      Expanded(
                        child: Column(children: [
                          Text(best[s] == null ? '–' : '${best[s]}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text(s[0].toUpperCase() + s.substring(1), style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                        ]),
                      ),
                  ]),
                ]),
              ),
            ),
            if (r['activity'] is Map) ...[
              const SizedBox(height: 12),
              ActivityCard(username: '${p['username']}', initial: (r['activity'] as Map).cast<String, dynamic>()),
            ],
            const SizedBox(height: 12),
            Card(
              child: Column(children: [
                ListTile(
                  leading: const Icon(Icons.map_rounded, color: C.green),
                  title: Text(tr('Daily English')),
                  trailing: Text('${p['dailyDone'] ?? 0} / ${p['dailyTotal'] ?? 0}'),
                ),
                ListTile(
                  leading: const Icon(Icons.emoji_events_rounded, color: C.gold),
                  title: Text(tr('Best streak')),
                  trailing: Text('${p['bestStreak'] ?? 0} days'),
                ),
                if (r['friendsOpen'] == true)
                  ListTile(
                    leading: const Icon(Icons.people_alt_rounded, color: C.blue),
                    title: Text(tr('Friends')),
                    trailing: Text('${p['friendCount'] ?? 0}'),
                  ),
              ]),
            ),
            if (isMe) ...[
              const SizedBox(height: 12),
              if (!viewerPro)
                Card(
                  color: C.gold.withValues(alpha: .12),
                  child: ListTile(
                    leading: const ProTick(size: 28),
                    title: Text(tr('Get Mockfy Pro'), style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(tr('More tests a week, detailed AI feedback and a free streak freeze every month')),
                    onTap: () => showProSheet(context, who: '', isMe: false, viewerPro: false),
                  ),
                ),
              const SizedBox(height: 12),
              // your own page: notifications, settings and help at the foot
              Card(
                child: Column(children: [
                  ValueListenableBuilder<int>(
                    valueListenable: Notify.I.unread,
                    builder: (context, n, _) => ListTile(
                      leading: const Icon(Icons.notifications_rounded, color: C.red),
                      title: Text(tr('Notifications')),
                      trailing: n > 0 ? Badge(label: Text('$n')) : const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.settings_rounded),
                    title: Text(tr('Settings')),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen(username: username, onSignedOut: onSignedOut)));
                      reload();
                    },
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(children: [
                  ListTile(
                    leading: const Icon(Icons.menu_book_rounded, color: C.blue),
                    title: Text(tr('Guide')),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WebPage(title: 'Guide', path: '/docs'))),
                  ),
                  ListTile(
                    leading: const Icon(Icons.chat_rounded, color: C.green),
                    title: Text(tr('Send feedback')),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FeedbackScreen())),
                  ),
                ]),
              ),
            ],
          ]);
        },
      ),
    );
  }
}

/// Someone else's profile: their name in the top bar (not the @username).
class _Title extends StatelessWidget {
  const _Title({required this.username});
  final String username;
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: Api.I.get('/api/app/profile/$username'),
        builder: (context, s) => Text(s.hasData ? '${(s.data!['profile'] as Map)['name']}' : ''),
      );
}
