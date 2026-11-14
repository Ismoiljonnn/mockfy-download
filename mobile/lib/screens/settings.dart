import 'package:flutter/material.dart';

import '../api.dart';
import '../prefs.dart';
import '../theme.dart';
import '../widgets.dart';

const _langs = {
  'en': 'English', 'uz': "O'zbekcha", 'ru': 'Русский', 'tr': 'Türkçe', 'ar': 'العربية',
  'hi': 'हिन्दी', 'tg': 'Тоҷикӣ', 'ky': 'Кыргызча', 'zh': '中文',
};
const _visibility = {'nobody': 'Only me', 'friends': 'Friends', 'everyone': 'Everyone'};

/// Settings in the app: account, look and sound, privacy, plan.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.username, required this.onSignedOut});
  final String username;
  final VoidCallback onSignedOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Loader<Map<String, dynamic>>(
        load: () async {
          final r = await Future.wait([Api.I.get('/api/app/me'), Api.I.get('/api/app/profile/$username')]);
          return {'me': r[0]['me'], 'profile': r[1]['profile']};
        },
        onSignedOut: onSignedOut,
        build: (context, d, reload) => _Body(me: (d['me'] as Map).cast<String, dynamic>(),
            profile: (d['profile'] as Map).cast<String, dynamic>(), reload: reload, onSignedOut: onSignedOut),
      ),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body({required this.me, required this.profile, required this.reload, required this.onSignedOut});
  final Map<String, dynamic> me;
  final Map<String, dynamic> profile;
  final Future<void> Function() reload;
  final VoidCallback onSignedOut;
  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  late String _visible = '${widget.profile['resultsVisibility'] ?? 'nobody'}';
  late bool _shareActivity = widget.profile['sharesActivity'] != false;

  Future<void> _privacy(String field, Object value) async {
    try {
      await Api.I.post('/api/settings/privacy', {'field': field, 'value': value});
      Sfx.play('tap');
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  Future<void> _editAccount() async {
    final name = TextEditingController(text: '${widget.me['name']}');
    final user = TextEditingController(text: '${widget.me['username']}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Name and username'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 10),
          TextField(controller: user, decoration: const InputDecoration(labelText: 'Username', prefixText: '@')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.I.post('/api/account/profile', {'name': name.text.trim(), 'username': user.text.trim()});
      Sfx.play('right');
      await widget.reload();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  Future<void> _language() async {
    final code = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final e in _langs.entries) ListTile(title: Text(e.value), onTap: () => Navigator.pop(c, e.key)),
        ]),
      ),
    );
    if (code == null) return;
    try {
      await Api.I.post('/api/lang', {'lang': code});
      if (mounted) toast(context, 'Language saved: ${_langs[code]}. Lessons and messages from Mockfy use it.');
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  // IELTS is what this app is made for; Learning English and Teaching open on the website
  Future<void> _workspace(Map w) async {
    if (w['active'] == true) return;
    try {
      await Api.I.post('/api/workspace/${w['have'] == true ? 'switch' : 'create'}', {'kind': '${w['kind']}'});
      Sfx.play('right');
      if (!mounted) return;
      Navigator.popUntil(context, (r) => r.isFirst);
      Prefs.I.workspaceChanged.value++;               // the app rebuilds with this workspace's tabs
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(title.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .6, color: Theme.of(context).hintColor))),
          Card(child: Column(children: children)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final me = widget.me;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
      _section('Account', [
        ListTile(
          leading: Avatar(url: me['avatar'] as String?, initial: '${me['name']}'.isEmpty ? '?' : '${me['name']}'[0].toUpperCase()),
          title: Text('${me['name']}'),
          subtitle: Text('@${me['username']}'),
          trailing: const Icon(Icons.edit_rounded, size: 20),
          onTap: _editAccount,
        ),
        ListTile(leading: const Icon(Icons.translate_rounded), title: const Text('Language'), trailing: const Icon(Icons.chevron_right_rounded), onTap: _language),
      ]),
      _section('Workspace', [
        for (final w in (me['workspaces'] as List? ?? []).cast<Map>().where((w) => w['kind'] != 'learner'))
          ListTile(
            leading: Icon(
              w['kind'] == 'teacher' ? Icons.school_rounded : w['kind'] == 'learner' ? Icons.translate_rounded : Icons.assignment_rounded,
              color: w['active'] == true ? C.accent : null,
            ),
            title: Text('${w['title']}', style: TextStyle(fontWeight: w['active'] == true ? FontWeight.w700 : FontWeight.w500)),
            subtitle: Text(w['active'] == true ? 'In use' : w['have'] == true ? 'Tap to switch' : 'Add this workspace'),
            trailing: w['active'] == true
                ? const Icon(Icons.check_circle_rounded, color: C.accent)
                : const Icon(Icons.chevron_right_rounded, size: 20),
            onTap: () => _workspace(w),
          ),
      ]),
      _section('Look and sound', [
        ValueListenableBuilder<ThemeMode>(
          valueListenable: Prefs.I.theme,
          builder: (context, mode, _) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(children: [
              const Icon(Icons.contrast_rounded),
              const SizedBox(width: 16),
              const Expanded(child: Text('Theme')),
              SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('Auto')),
                  ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded, size: 18)),
                  ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded, size: 18)),
                ],
                selected: {mode},
                onSelectionChanged: (s) { Prefs.I.setTheme(s.first); Sfx.play('tap'); },
              ),
            ]),
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: Prefs.I.sound,
          builder: (context, on, _) => SwitchListTile(
            secondary: const Icon(Icons.volume_up_rounded),
            title: const Text('Sound effects'),
            subtitle: const Text('Right and wrong answers, finished stages, purchases'),
            value: on,
            onChanged: (v) { Prefs.I.setSound(v); if (v) Sfx.play('press'); },
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: Prefs.I.haptics,
          builder: (context, on, _) => SwitchListTile(
            secondary: const Icon(Icons.vibration_rounded),
            title: const Text('Vibration'),
            value: on,
            onChanged: Prefs.I.setHaptics,
          ),
        ),
      ]),
      _section('Privacy', [
        ListTile(
          leading: const Icon(Icons.lock_outline_rounded),
          title: const Text('Who can open my finished tests'),
          trailing: DropdownButton<String>(
            value: _visibility.containsKey(_visible) ? _visible : 'nobody',
            underline: const SizedBox(),
            items: [for (final e in _visibility.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) { if (v == null) return; setState(() => _visible = v); _privacy('results_visibility', v); },
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.grid_view_rounded),
          title: const Text('Show my activity on my profile'),
          value: _shareActivity,
          onChanged: (v) { setState(() => _shareActivity = v); _privacy('share_activity', v); },
        ),
      ]),
      _section('Plan', [
        ListTile(
          leading: me['isPro'] == true ? const ProTick(size: 26) : const Icon(Icons.workspace_premium_outlined),
          title: Text(me['isPro'] == true ? 'Mockfy Pro' : 'Free'),
          subtitle: Text(me['isPro'] == true ? 'Manage your plan and payments' : 'See what Pro gives'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => me['isPro'] == true ? openWeb('/settings') : showProSheet(context, who: '', isMe: false, viewerPro: false),
        ),
      ]),
      _section('More', [
        ListTile(leading: const Icon(Icons.help_outline_rounded), title: const Text('Help'), trailing: const Icon(Icons.open_in_new_rounded, size: 18), onTap: () => openWeb('/docs')),
        ListTile(leading: const Icon(Icons.description_outlined), title: const Text('Terms and privacy'), trailing: const Icon(Icons.open_in_new_rounded, size: 18), onTap: () => openWeb('/privacy')),
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
            if (ok == true && context.mounted) { Navigator.popUntil(context, (r) => r.isFirst); widget.onSignedOut(); }
          },
        ),
      ]),
    ]);
  }
}
