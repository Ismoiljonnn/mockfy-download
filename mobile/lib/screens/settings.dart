import 'package:flutter/material.dart';

import '../i18n.dart';

import '../api.dart';
import '../notify.dart';
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
      appBar: AppBar(title: Text(tr('Settings'))),
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
        title: Text(tr('Name and username')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: InputDecoration(labelText: tr('Name'))),
          const SizedBox(height: 10),
          TextField(controller: user, decoration: InputDecoration(labelText: tr('Username'), prefixText: '@')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Cancel'))),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Save'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.I.post('/api/account/profile', {'name': name.text.trim(), 'username': user.text.trim()});
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
      await I18n.I.set(code);                         // the whole app redraws in the new language
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  // IELTS is what this app is made for; Learning English and Teaching open on the website
  Future<void> _workspace(Map w) async {
    if (w['active'] == true) return;
    try {
      await Api.I.post('/api/workspace/${w['have'] == true ? 'switch' : 'create'}', {'kind': '${w['kind']}'});
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
              child: Text(tr(title).toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .6, color: Theme.of(context).hintColor))),
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
        ListTile(leading: const Icon(Icons.translate_rounded), title: Text(tr('Language')), trailing: const Icon(Icons.chevron_right_rounded), onTap: _language),
      ]),
      _section('Workspace', [
        for (final w in (me['workspaces'] as List? ?? []).cast<Map>().where((w) => w['kind'] != 'learner'))
          ListTile(
            leading: Icon(
              w['kind'] == 'teacher' ? Icons.school_rounded : w['kind'] == 'learner' ? Icons.translate_rounded : Icons.assignment_rounded,
              color: w['active'] == true ? C.accent : null,
            ),
            title: Text('${w['title']}', style: TextStyle(fontWeight: w['active'] == true ? FontWeight.w700 : FontWeight.w500)),
            subtitle: Text(w['active'] == true ? 'In use' : w['have'] == true ? tr('Tap to switch') : tr('Add this workspace')),
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
              Expanded(child: Text(tr('Theme'))),
              SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: ThemeMode.system, label: Text(tr('Auto'))),
                  ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded, size: 18)),
                  ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded, size: 18)),
                ],
                selected: {mode},
                onSelectionChanged: (s) => Prefs.I.setTheme(s.first),
              ),
            ]),
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: Prefs.I.sound,
          builder: (context, on, _) => SwitchListTile(
            secondary: const Icon(Icons.volume_up_rounded),
            title: Text(tr('Sound effects')),
            subtitle: Text(tr('In Daily English and the games')),
            value: on,
            onChanged: Prefs.I.setSound,
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: Prefs.I.haptics,
          builder: (context, on, _) => SwitchListTile(
            secondary: const Icon(Icons.vibration_rounded),
            title: Text(tr('Vibration')),
            value: on,
            onChanged: Prefs.I.setHaptics,
          ),
        ),
      ]),
      _section('Notifications', [const _Reminder()]),
      _section('Privacy', [
        ListTile(
          leading: const Icon(Icons.lock_outline_rounded),
          title: Text(tr('Who can open my finished tests')),
          trailing: DropdownButton<String>(
            value: _visibility.containsKey(_visible) ? _visible : 'nobody',
            underline: const SizedBox(),
            items: [for (final e in _visibility.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) { if (v == null) return; setState(() => _visible = v); _privacy('results_visibility', v); },
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.grid_view_rounded),
          title: Text(tr('Show my activity on my profile')),
          value: _shareActivity,
          onChanged: (v) { setState(() => _shareActivity = v); _privacy('share_activity', v); },
        ),
      ]),
      _section('Plan', [
        ListTile(
          leading: me['isPro'] == true ? const ProTick(size: 26) : const Icon(Icons.workspace_premium_outlined),
          title: Text(me['isPro'] == true ? 'Mockfy Pro' : tr('Free')),
          subtitle: Text(me['isPro'] == true ? 'Manage your plan and payments' : tr('See what Pro gives')),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => me['isPro'] == true ? openWeb('/settings') : showProSheet(context, who: '', isMe: false, viewerPro: false),
        ),
      ]),
      _section('More', [
        ListTile(leading: const Icon(Icons.help_outline_rounded), title: Text(tr('Help')), trailing: const Icon(Icons.open_in_new_rounded, size: 18), onTap: () => openWeb('/docs')),
        ListTile(leading: const Icon(Icons.description_outlined), title: Text(tr('Terms and privacy')), trailing: const Icon(Icons.open_in_new_rounded, size: 18), onTap: () => openWeb('/privacy')),
        ListTile(
          leading: const Icon(Icons.logout_rounded, color: C.red),
          title: Text(tr('Sign out'), style: TextStyle(color: C.red)),
          onTap: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: Text(tr('Sign out of Mockfy?')),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Cancel'))),
                  TextButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Sign out'))),
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

/// The daily practice reminder (a phone notification at the time you pick).
class _Reminder extends StatefulWidget {
  const _Reminder();
  @override
  State<_Reminder> createState() => _ReminderState();
}

class _ReminderState extends State<_Reminder> {
  bool _on = false;
  TimeOfDay _at = const TimeOfDay(hour: 20, minute: 0);

  @override
  void initState() {
    super.initState();
    Notify.I.reminder().then((r) { if (mounted) setState(() { _on = r.on; _at = TimeOfDay(hour: r.hour, minute: r.minute); }); });
  }

  Future<void> _save() => Notify.I.setReminder(_on, hour: _at.hour, minute: _at.minute);

  @override
  Widget build(BuildContext context) => Column(children: [
        SwitchListTile(
          secondary: const Icon(Icons.alarm_rounded),
          title: Text(tr('Daily reminder')),
          subtitle: Text(tr('A nudge to practise, so your streak keeps going')),
          value: _on,
          onChanged: (v) { setState(() => _on = v); _save(); },
        ),
        if (_on)
          ListTile(
            leading: const Icon(Icons.schedule_rounded),
            title: Text(tr('Time')),
            trailing: Text(_at.format(context), style: const TextStyle(fontWeight: FontWeight.w700)),
            onTap: () async {
              final t = await showTimePicker(context: context, initialTime: _at);
              if (t == null) return;
              setState(() => _at = t);
              _save();
            },
          ),
        ListTile(
          leading: Icon(Icons.notifications_active_outlined),
          title: Text(tr('News from Mockfy')),
          subtitle: Text(tr('Results, homework and Mock Day news arrive as notifications when you open the app')),
        ),
      ]);
}
