import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

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
      appBar: AppBar(title: Text(isRoot ? 'Me' : '@$username')),
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
                child: Text('Mockfy bot · a practice rival run by Mockfy, not a person', textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12)),
              ),
            const SizedBox(height: 18),
            Row(children: [
              StatTile(icon: Icons.star_rounded, color: C.gold, value: '${p['points'] ?? 0}', label: 'Points'),
              const SizedBox(width: 10),
              StatTile(icon: Icons.local_fire_department_rounded, color: C.accent, value: '${p['streak'] ?? 0}', label: 'Streak'),
              const SizedBox(width: 10),
              StatTile(icon: Icons.task_alt_rounded, color: C.green, value: '${p['testsDone'] ?? 0}', label: 'Tests'),
            ]),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Best band by section', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
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
            const SizedBox(height: 12),
            Card(
              child: Column(children: [
                ListTile(
                  leading: const Icon(Icons.map_rounded, color: C.green),
                  title: const Text('Daily English'),
                  trailing: Text('${p['dailyDone'] ?? 0} / ${p['dailyTotal'] ?? 0}'),
                ),
                ListTile(
                  leading: const Icon(Icons.emoji_events_rounded, color: C.gold),
                  title: const Text('Best streak'),
                  trailing: Text('${p['bestStreak'] ?? 0} days'),
                ),
                ListTile(
                  leading: const Icon(Icons.people_alt_rounded, color: C.blue),
                  title: const Text('Friends'),
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
                    title: const Text('Get Mockfy Pro', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('More tests a week, detailed AI feedback and a free streak freeze every month'),
                    onTap: () => showProSheet(context, who: '', isMe: false, viewerPro: false),
                  ),
                ),
              const SizedBox(height: 12),
              Card(
                child: Column(children: [
                  ListTile(leading: const Icon(Icons.settings_rounded), title: const Text('Settings'),
                      trailing: const Icon(Icons.open_in_new_rounded, size: 18), onTap: () => openWeb('/settings')),
                  ListTile(leading: const Icon(Icons.help_outline_rounded), title: const Text('Help'),
                      trailing: const Icon(Icons.open_in_new_rounded, size: 18), onTap: () => openWeb('/docs')),
                  ListTile(
                    leading: const Icon(Icons.logout_rounded, color: C.red),
                    title: const Text('Sign out', style: TextStyle(color: C.red)),
                    onTap: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('Sign out of Mockfy?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sign out')),
                          ],
                        ),
                      );
                      if (ok == true) onSignedOut();
                    },
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
