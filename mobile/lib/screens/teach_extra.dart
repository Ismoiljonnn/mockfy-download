// More of the Teaching workspace, as on the website: a group's join link and QR code, the link for a
// student's parents, the centre report and the centre's settings (name and logo on reports, the pilot).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../api.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets.dart';

Future<void> _copy(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) toast(context, tr('Copied'));
}

/// A group's join link: students open it (or scan the QR code) and join the group themselves.
Future<void> showJoinLink(BuildContext context, int groupId) async {
  Map<String, dynamic>? r;
  try {
    r = await Api.I.post('/api/teach/groups/$groupId/link');
  } on ApiError catch (e) {
    if (context.mounted) toast(context, e.message);
    return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, set) {
        final url = '${r!['url']}';
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr('Join link'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              Text('${(r['group'] as Map?)?['name'] ?? ''}', style: TextStyle(color: Theme.of(sheet).hintColor)),
              const SizedBox(height: 14),
              if ('${r['qr'] ?? ''}'.isNotEmpty)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                    child: SvgPicture.string('${r['qr']}', width: 200, height: 200),
                  ),
                ),
              const SizedBox(height: 12),
              SelectableText(url, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(tr('Students open the link or scan the code and join this group.'), textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(sheet).hintColor)),
              const SizedBox(height: 14),
              FilledButton.icon(onPressed: () => _copy(sheet, url), icon: const Icon(Icons.copy_rounded), label: Text(tr('Copy link'))),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: () => openExternal('https://t.me/share/url?url=${Uri.encodeComponent(url)}'),
                icon: const Icon(Icons.send_rounded),
                label: Text(tr('Share in Telegram')),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    final n = await Api.I.post('/api/teach/groups/$groupId/link', {'action': 'reset'});
                    set(() => r = n);
                    if (sheet.mounted) toast(sheet, tr('New link made. The old one no longer works.'));
                  } on ApiError catch (e) {
                    if (sheet.mounted) toast(sheet, e.message);
                  }
                },
                child: Text(tr('Make a new link')),
              ),
            ]),
          ),
        );
      },
    ),
  );
}

/// The parents' link for one student: a page with their progress, no sign-in, to send to the family.
Future<void> showParentLink(BuildContext context, int studentId) async {
  Map<String, dynamic> r;
  try {
    r = await Api.I.post('/api/teach/students/$studentId/parent');
  } on ApiError catch (e) {
    if (context.mounted) toast(context, e.message);
    return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('Link for parents'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(tr('Parents see this student\'s progress on this page, without signing in.'), style: TextStyle(color: Theme.of(sheet).hintColor)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: C.blue.withValues(alpha: .08)),
            child: SelectableText('${r['text']}'),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(onPressed: () => _copy(sheet, '${r['text']}'), icon: const Icon(Icons.copy_rounded), label: Text(tr('Copy message'))),
          const SizedBox(height: 6),
          OutlinedButton.icon(onPressed: () => openExternal('${r['telegram']}'), icon: const Icon(Icons.send_rounded), label: Text(tr('Share in Telegram'))),
          if (r['bot'] != null)
            TextButton(onPressed: () => _copy(sheet, '${r['bot']}'), child: Text(tr('Copy the Telegram bot link'))),
        ]),
      ),
    ),
  );
}

/// The centre report: every student with active days, tests and homework, and who is behind.
class TeachReportScreen extends StatefulWidget {
  const TeachReportScreen({super.key});
  @override
  State<TeachReportScreen> createState() => _TeachReportScreenState();
}

class _TeachReportScreenState extends State<TeachReportScreen> {
  String _group = '';
  int _days = 7;
  Key _k = UniqueKey();

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Report'))),
      body: Loader<Map<String, dynamic>>(
        key: _k,
        load: () => Api.I.get('/api/app/teach/report', {'group': _group, 'days': '$_days'}),
        build: (context, d, reload) {
          final r = (d['report'] as Map).cast<String, dynamic>();
          final sum = (r['summary'] as Map?) ?? {};
          final rows = ((r['rows'] as List?) ?? []).cast<Map>();
          final behind = ((r['behind'] as List?) ?? []).map((e) => (e as Map)['id']).toSet();
          final groups = ((d['groups'] as List?) ?? []).cast<Map>();
          Widget stat(String v, String l) => Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    child: Column(children: [
                      Text(v, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      Text(l, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: hint)),
                    ]),
                  ),
                ),
              );
          return ListView(padding: const EdgeInsets.all(16), children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final n in [7, 14, 30])
                ChoiceChip(label: Text(tr('{n} days', {'n': n})), selected: _days == n, onSelected: (_) => setState(() { _days = n; _k = UniqueKey(); })),
            ]),
            if (groups.isNotEmpty) ...[
              const SizedBox(height: 8),
              DropdownButton<String>(
                value: _group,
                isExpanded: true,
                items: [
                  DropdownMenuItem(value: '', child: Text(tr('All groups'))),
                  for (final g in groups) DropdownMenuItem(value: '${g['id']}', child: Text('${g['name']}')),
                ],
                onChanged: (v) => setState(() { _group = v ?? ''; _k = UniqueKey(); }),
              ),
            ],
            const SizedBox(height: 8),
            Text('${r['from']} – ${r['to']}', style: TextStyle(color: hint)),
            const SizedBox(height: 8),
            Row(children: [
              stat('${sum['active'] ?? 0}/${sum['students'] ?? 0}', tr('Active')),
              stat('${sum['avg_days'] ?? 0}', tr('Days per student')),
              stat('${sum['tests'] ?? 0}', tr('Tests')),
            ]),
            Row(children: [
              stat('${sum['improved'] ?? 0}', tr('Improved')),
              stat('${sum['hw_done'] ?? 0}', tr('Homework done')),
              stat('${sum['hw_overdue'] ?? 0}', tr('Overdue')),
            ]),
            const SizedBox(height: 12),
            for (final s in rows)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: behind.contains(s['id']) ? C.red.withValues(alpha: .07) : null,
                child: ListTile(
                  title: Text('${s['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(tr('{d} active days · {t} tests · {h} homework done', {
                    'd': (s['stats'] as Map)['days'], 't': (s['stats'] as Map)['tests'], 'h': (s['stats'] as Map)['hw_done'],
                  })),
                  trailing: (s['stats'] as Map)['change'] == null
                      ? null
                      : Text('${((s['stats'] as Map)['change'] as num) > 0 ? '+' : ''}${(s['stats'] as Map)['change']}',
                          style: TextStyle(fontWeight: FontWeight.w800, color: ((s['stats'] as Map)['change'] as num) >= 0 ? C.green : C.red)),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

/// The centre's settings: its name (and logo) on reports and parents' pages, and the free pilot.
class TeachCentreScreen extends StatefulWidget {
  const TeachCentreScreen({super.key});
  @override
  State<TeachCentreScreen> createState() => _TeachCentreScreenState();
}

class _TeachCentreScreenState extends State<TeachCentreScreen> {
  Key _k = UniqueKey();
  final _name = TextEditingController();
  bool _filled = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      await Api.I.post('/api/teach/centre', {'name': _name.text.trim()});
      if (mounted) toast(context, tr('Saved'));
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  Future<void> _pilot() async {
    try {
      await Api.I.post('/api/teach/pilot');
      setState(() => _k = UniqueKey());
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Centre settings'))),
      body: Loader<Map<String, dynamic>>(
        key: _k,
        load: () => Api.I.get('/api/app/teach/centre'),
        build: (context, d, reload) {
          final brand = (d['brand'] as Map?) ?? {};
          final pilot = (d['pilot'] as Map?) ?? {};
          if (!_filled) { _name.text = '${brand['name'] ?? ''}'; _filled = true; }
          return ListView(padding: const EdgeInsets.all(16), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(tr('Centre name'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(tr('Shown on reports and on the parents\' pages.'), style: TextStyle(color: hint)),
                  const SizedBox(height: 10),
                  TextField(controller: _name, decoration: InputDecoration(hintText: tr('e.g. Bright English Centre'))),
                  const SizedBox(height: 10),
                  FilledButton(onPressed: _save, child: Text(tr('Save'))),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            if (d['team'] == null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(tr('Free pilot'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(
                      (pilot['days_left'] as num? ?? 0) > 0
                          ? tr('{n} days left of the pilot.', {'n': pilot['days_left']})
                          : pilot['used'] == true
                              ? tr('The pilot has ended.')
                              : tr('Pro for up to {s} students for {d} days, free.', {'s': d['seats'], 'd': d['days']}),
                      style: TextStyle(color: hint),
                    ),
                    if (pilot['used'] != true) ...[
                      const SizedBox(height: 10),
                      FilledButton(onPressed: _pilot, child: Text(tr('Start the pilot'))),
                    ],
                  ]),
                ),
              )
            else
              Card(child: ListTile(leading: const Icon(Icons.verified_rounded, color: C.green), title: Text(tr('Team plan')))),
          ]);
        },
      ),
    );
  }
}
