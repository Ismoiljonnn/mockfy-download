// The Teaching workspace in the app: the class at a glance, students and groups, homework (assignments).
import 'package:flutter/material.dart';

import '../api.dart';
import '../prefs.dart';
import '../theme.dart';
import '../widgets.dart';
import 'profile.dart';
import 'tests.dart';

// ---------------------------------------------------------------- Home
class TeachHomeScreen extends StatelessWidget {
  const TeachHomeScreen({super.key, required this.me, required this.onSignedOut, required this.goTab});
  final Map<String, dynamic> me;
  final VoidCallback onSignedOut;
  final void Function(int) goTab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: menuButton(context), title: const Text('My class')),
      body: Loader<Map<String, dynamic>>(
        load: () => Api.I.get('/api/app/teach'),
        onSignedOut: onSignedOut,
        build: (context, d, reload) {
          final o = (d['overview'] as Map).cast<String, dynamic>();
          final soon = (o['soon'] as List? ?? []).cast<Map>();
          final quiet = (o['quiet'] as List? ?? []).cast<Map>();
          final recent = (o['recent'] as List? ?? []).cast<Map>();
          return ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              StatTile(icon: Icons.people_alt_rounded, color: C.blue, value: '${o['students'] ?? 0}', label: 'Students', onTap: () => goTab(1)),
              const SizedBox(width: 10),
              StatTile(icon: Icons.assignment_rounded, color: C.accent, value: '${o['open_assignments'] ?? 0}', label: 'Open homework', onTap: () => goTab(2)),
              const SizedBox(width: 10),
              StatTile(icon: Icons.hourglass_top_rounded, color: C.gold, value: '${o['pending'] ?? 0}', label: 'Invites sent', onTap: () => goTab(1)),
            ]),
            if ((o['students'] ?? 0) == 0 && (o['pending'] ?? 0) == 0) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Start your class', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text('Make a group, then add students by their @username. They get a request in Mockfy.',
                        style: TextStyle(color: Theme.of(context).hintColor)),
                    const SizedBox(height: 14),
                    FilledButton(onPressed: () => goTab(1), child: const Text('Add students')),
                  ]),
                ),
              ),
            ],
            if (soon.isNotEmpty) _block(context, 'Due soon', [
              for (final a in soon)
                ListTile(
                  leading: const Icon(Icons.event_rounded, color: C.accent),
                  title: Text('${a['title']}'),
                  subtitle: Text(_dueText(a['due_at'])),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AssignmentScreen(id: (a['id'] as num).toInt()))),
                ),
            ]),
            if (recent.isNotEmpty) _block(context, 'Recent results', [
              for (final r in recent)
                ListTile(
                  leading: Avatar(initial: '${(r['name'] ?? '?')}'.isEmpty ? '?' : '${r['name']}'[0], url: r['avatar'] is String && '${r['avatar']}'.startsWith('http') ? '${r['avatar']}' : null),
                  title: Text('${r['name'] ?? ''}'),
                  subtitle: Text('${r['title'] ?? r['test'] ?? ''}'),
                  trailing: Text('${r['band'] ?? ''}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
            ]),
            if (quiet.isNotEmpty) _block(context, 'Quiet this week', [
              for (final q in quiet)
                ListTile(
                  leading: const Icon(Icons.notifications_paused_rounded, color: C.gold),
                  title: Text('${q['name'] ?? ''}'),
                  subtitle: Text('@${q['username'] ?? ''}'),
                ),
            ]),
          ]);
        },
      ),
    );
  }
}

Widget _block(BuildContext context, String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 8), child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
        Card(child: Column(children: children)),
      ]),
    );

String _dueText(dynamic due) {
  if (due == null || '$due'.isEmpty) return 'No deadline';
  final d = DateTime.tryParse('$due'.replaceFirst(' ', 'T'));
  if (d == null) return 'Due $due';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return 'Due ${d.day} ${m[d.month - 1]}, ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------- Students and groups
class StudentsScreen extends StatefulWidget {
  const StudentsScreen({super.key, required this.onSignedOut});
  final VoidCallback onSignedOut;
  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  int? _group;                   // null: everyone
  Key _k = UniqueKey();

  void _refresh() => setState(() => _k = UniqueKey());

  Future<void> _newGroup() async {
    final name = await _ask(context, 'New group', 'Group name, e.g. IELTS evening');
    if (name == null || name.isEmpty) return;
    try {
      await Api.I.post('/api/teach/groups', {'name': name});
      _refresh();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  Future<void> _invite(List<Map> groups) async {
    final q = TextEditingController();
    int? gid = _group ?? (groups.isNotEmpty ? (groups.first['id'] as num).toInt() : null);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Add a student'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: q, autofocus: true, decoration: const InputDecoration(labelText: '@username or email')),
            if (groups.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: gid,
                decoration: const InputDecoration(labelText: 'Group'),
                items: [for (final g in groups) DropdownMenuItem(value: (g['id'] as num).toInt(), child: Text('${g['name']}'))],
                onChanged: (v) => set(() => gid = v),
              ),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Send request')),
          ],
        ),
      ),
    );
    if (ok != true || q.text.trim().isEmpty) return;
    try {
      final r = await Api.I.post('/api/teach/invite', {'query': q.text.trim(), 'group_id': gid});
      if (mounted) toast(context, 'Request sent to ${(r['student'] as Map?)?['name'] ?? q.text}.');
      _refresh();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Loader<Map<String, dynamic>>(
      key: _k,
      load: () => Api.I.get('/api/app/teach/students'),
      onSignedOut: widget.onSignedOut,
      build: (context, d, reload) {
        final groups = (d['groups'] as List).cast<Map>();
        final all = (d['students'] as List).cast<Map>();
        final shown = _group == null ? all : all.where((s) => s['group_id'] == _group).toList();
        return Scaffold(
          appBar: AppBar(leading: menuButton(context), title: const Text('Students'), actions: [
            IconButton(tooltip: 'New group', icon: const Icon(Icons.create_new_folder_outlined), onPressed: _newGroup),
          ]),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'add-student',
            onPressed: () => _invite(groups),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Add student'),
          ),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 90), children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                ChoiceChip(label: Text('Everyone (${all.length})'), selected: _group == null, onSelected: (_) => setState(() => _group = null)),
                for (final g in groups)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ChoiceChip(
                      label: Text('${g['name']} (${g['count']})'),
                      selected: _group == g['id'],
                      onSelected: (_) => setState(() => _group = (g['id'] as num).toInt()),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            if (shown.isEmpty)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No students here yet.'))),
            for (final s in shown)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Avatar(url: '${s['avatar']}'.startsWith('http') ? '${s['avatar']}' : null, initial: '${s['initial'] ?? '?'}'),
                  title: Text('${s['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(s['status'] == 'pending' ? 'Request sent · @${s['username']}' : '${s['group'] ?? 'No group'} · 🔥 ${s['streak'] ?? 0}'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: s['status'] == 'pending' ? null : () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => StudentScreen(id: (s['id'] as num).toInt(), name: '${s['name']}')));
                    _refresh();
                  },
                ),
              ),
          ]),
        );
      },
    );
  }
}

Future<String?> _ask(BuildContext context, String title, String hint) async {
  final c = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, autofocus: true, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Save')),
      ],
    ),
  );
  return ok == true ? c.text.trim() : null;
}

class StudentScreen extends StatelessWidget {
  const StudentScreen({super.key, required this.id, required this.name});
  final int id;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: Loader<Map<String, dynamic>>(
        load: () => Api.I.get('/api/app/teach/students/$id'),
        build: (context, d, reload) {
          final p = (d['profile'] as Map).cast<String, dynamic>();
          final best = (p['best'] as Map?) ?? {};
          final attempts = (d['attempts'] as List? ?? []).cast<Map>();
          final hw = (d['homework'] as List? ?? []).cast<Map>();
          final groups = (d['groups'] as List? ?? []).cast<Map>();
          return ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Avatar(url: p['avatar'] as String?, initial: '${p['initial']}', size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${p['name']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  Text('@${p['username']} · 🔥 ${p['streak'] ?? 0}', style: TextStyle(color: Theme.of(context).hintColor)),
                ]),
              ),
              IconButton(
                tooltip: 'Profile',
                icon: const Icon(Icons.person_rounded),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(username: '${p['username']}', onSignedOut: () {}))),
              ),
            ]),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  for (final s in ['listening', 'reading', 'writing', 'speaking'])
                    Expanded(
                      child: Column(children: [
                        Icon(sectionIcons[s], color: sectionColors[s], size: 20),
                        const SizedBox(height: 4),
                        Text(best[s] == null ? '–' : '${best[s]}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      ]),
                    ),
                ]),
              ),
            ),
            if (groups.isNotEmpty) ...[
              const SizedBox(height: 10),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: const Text('Move to a group'),
                  trailing: PopupMenuButton<int>(
                    icon: const Icon(Icons.more_horiz_rounded),
                    itemBuilder: (_) => [for (final g in groups) PopupMenuItem(value: (g['id'] as num).toInt(), child: Text('${g['name']}'))],
                    onSelected: (gid) async {
                      try {
                        await Api.I.post('/api/teach/students/$id', {'group_id': gid});
                        if (context.mounted) toast(context, 'Moved.');
                      } on ApiError catch (e) {
                        if (context.mounted) toast(context, e.message);
                      }
                    },
                  ),
                ),
              ),
            ],
            if (hw.isNotEmpty) _block(context, 'Homework', [
              for (final h in hw)
                ListTile(
                  leading: Icon(h['done'] == true ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      color: h['done'] == true ? C.green : Theme.of(context).hintColor),
                  title: Text('${h['title']}'),
                  subtitle: Text(_dueText(h['due_at'])),
                  trailing: h['band'] != null ? Text('${h['band']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)) : null,
                ),
            ]),
            if (attempts.isNotEmpty) _block(context, 'Tests', [
              for (final a in attempts.take(15))
                ListTile(
                  title: Text('${a['title'] ?? a['testTitle'] ?? ''}'),
                  subtitle: Text('${a['scope'] ?? ''} · ${a['status'] ?? ''}'),
                  trailing: Text('${a['band'] ?? a['overallBand'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
            ]),
            const SizedBox(height: 18),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: C.red),
              icon: const Icon(Icons.person_remove_rounded),
              label: const Text('Remove from my class'),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: Text('Remove ${p['name']}?'),
                    content: const Text('Their own results stay theirs. You can add them again later.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove')),
                    ],
                  ),
                );
                if (ok != true) return;
                try {
                  await Api.I.post('/api/teach/students/$id', {'action': 'remove'});
                  if (context.mounted) Navigator.pop(context);
                } on ApiError catch (e) {
                  if (context.mounted) toast(context, e.message);
                }
              },
            ),
          ]);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- Homework (assignments)
class AssignmentsScreen extends StatefulWidget {
  const AssignmentsScreen({super.key, required this.onSignedOut});
  final VoidCallback onSignedOut;
  @override
  State<AssignmentsScreen> createState() => _AssignmentsScreenState();
}

class _AssignmentsScreenState extends State<AssignmentsScreen> {
  Key _k = UniqueKey();

  @override
  Widget build(BuildContext context) {
    return Loader<Map<String, dynamic>>(
      key: _k,
      load: () => Api.I.get('/api/app/teach/assignments'),
      onSignedOut: widget.onSignedOut,
      build: (context, d, reload) {
        final items = (d['items'] as List).cast<Map>();
        return Scaffold(
          appBar: AppBar(leading: menuButton(context), title: const Text('Homework')),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'new-homework',
            icon: const Icon(Icons.add_rounded),
            label: const Text('New homework'),
            onPressed: () async {
              final made = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => NewAssignmentScreen(data: d)));
              if (made == true) setState(() => _k = UniqueKey());
            },
          ),
          body: items.isEmpty
              ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No homework yet. Give a test to a group or to students.', textAlign: TextAlign.center)))
              : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 90), children: [
                  for (final a in items)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(sectionIcons['${a['scope']}'] ?? Icons.assignment_rounded, color: sectionColors['${a['scope']}'] ?? C.accent),
                        title: Text('${a['title']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('${_dueText(a['due_at'])} · ${a['done'] ?? 0}/${a['total'] ?? 0} done'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () async {
                          await Navigator.push(context, MaterialPageRoute(builder: (_) => AssignmentScreen(id: (a['id'] as num).toInt())));
                          setState(() => _k = UniqueKey());
                        },
                      ),
                    ),
                ]),
        );
      },
    );
  }
}

class AssignmentScreen extends StatelessWidget {
  const AssignmentScreen({super.key, required this.id});
  final int id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Homework')),
      body: Loader<Map<String, dynamic>>(
        load: () => Api.I.get('/api/app/teach/assignments/$id'),
        build: (context, d, reload) {
          final a = (d['assignment'] as Map).cast<String, dynamic>();
          final rows = (a['students'] as List? ?? a['rows'] as List? ?? []).cast<Map>();
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text('${a['title']}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('${_dueText(a['due_at'])}${a['target_band'] != null ? ' · target ${a['target_band']}' : ''}',
                style: TextStyle(color: Theme.of(context).hintColor)),
            if ('${a['note'] ?? ''}'.isNotEmpty) ...[const SizedBox(height: 10), Text('${a['note']}')],
            const SizedBox(height: 14),
            Card(
              child: Column(children: [
                for (final r in rows)
                  ListTile(
                    leading: Icon(r['done'] == true || r['status'] == 'done' ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        color: r['done'] == true || r['status'] == 'done' ? C.green : Theme.of(context).hintColor),
                    title: Text('${r['name'] ?? ''}'),
                    trailing: Text('${r['band'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
                if (rows.isEmpty) const ListTile(title: Text('No students on this homework yet.')),
              ]),
            ),
            const SizedBox(height: 18),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: C.red),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Delete this homework'),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Delete this homework?'),
                    content: const Text('Students who already did the test keep their results.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
                    ],
                  ),
                );
                if (ok != true) return;
                try {
                  await Api.I.post('/api/teach/assignments/$id', {'action': 'delete'});
                  if (context.mounted) Navigator.pop(context);
                } on ApiError catch (e) {
                  if (context.mounted) toast(context, e.message);
                }
              },
            ),
          ]);
        },
      ),
    );
  }
}

class NewAssignmentScreen extends StatefulWidget {
  const NewAssignmentScreen({super.key, required this.data});
  final Map<String, dynamic> data;
  @override
  State<NewAssignmentScreen> createState() => _NewAssignmentScreenState();
}

class _NewAssignmentScreenState extends State<NewAssignmentScreen> {
  String? _test;
  String? _scope;
  final Set<int> _groups = {};
  final Set<int> _students = {};
  DateTime? _due;
  double? _target;
  final _note = TextEditingController();
  bool _busy = false;

  List<Map> get _tests => (widget.data['tests'] as List).cast<Map>();
  Map? get _picked => _tests.where((t) => t['slug'] == _test).firstOrNull;

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await Api.I.post('/api/teach/assignments', {
        'test_slug': _test,
        'scope': _scope,
        'groups': _groups.toList(),
        'students': _students.toList(),
        'due_at': _due?.toIso8601String().substring(0, 16),
        'target_band': _target,
        'note': _note.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = (widget.data['groups'] as List).cast<Map>();
    final students = (widget.data['students'] as List).cast<Map>();
    final t = _picked;
    final scopes = t == null ? <String>[] : [if (t['full'] == true) 'full', for (final s in (t['sections'] as List).cast<Map>()) '${s['key']}'];
    return Scaffold(
      appBar: AppBar(title: const Text('New homework')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        DropdownButtonFormField<String>(
          value: _test,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Test'),
          items: [for (final x in _tests) DropdownMenuItem(value: '${x['slug']}', child: Text('${x['title']}', overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() { _test = v; _scope = null; }),
        ),
        if (scopes.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in scopes)
              ChoiceChip(
                label: Text(s == 'full' ? 'Full mock' : s[0].toUpperCase() + s.substring(1)),
                selected: _scope == s,
                onSelected: (_) => setState(() => _scope = s),
              ),
          ]),
        ],
        const SizedBox(height: 18),
        const Text('Who', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final g in groups)
            FilterChip(
              label: Text('${g['name']}'),
              selected: _groups.contains(g['id']),
              onSelected: (on) => setState(() => on ? _groups.add((g['id'] as num).toInt()) : _groups.remove(g['id'])),
            ),
          for (final s in students)
            FilterChip(
              avatar: const Icon(Icons.person_rounded, size: 16),
              label: Text('${s['name']}'),
              selected: _students.contains(s['id']),
              onSelected: (on) => setState(() => on ? _students.add((s['id'] as num).toInt()) : _students.remove(s['id'])),
            ),
        ]),
        const SizedBox(height: 18),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_rounded),
          title: Text(_due == null ? 'No deadline' : _dueText(_due!.toIso8601String())),
          trailing: TextButton(
            child: const Text('Pick'),
            onPressed: () async {
              final now = DateTime.now();
              final day = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 365)), initialDate: now.add(const Duration(days: 7)));
              if (day == null || !context.mounted) return;
              final time = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 21, minute: 0));
              setState(() => _due = DateTime(day.year, day.month, day.day, time?.hour ?? 21, time?.minute ?? 0));
            },
          ),
        ),
        DropdownButtonFormField<double?>(
          value: _target,
          decoration: const InputDecoration(labelText: 'Target band (optional)'),
          items: [
            const DropdownMenuItem<double?>(value: null, child: Text('None')),
            for (var b = 4.0; b <= 9.0; b += .5) DropdownMenuItem<double?>(value: b, child: Text(b.toStringAsFixed(1))),
          ],
          onChanged: (v) => setState(() => _target = v),
        ),
        const SizedBox(height: 12),
        TextField(controller: _note, maxLines: 3, decoration: const InputDecoration(labelText: 'Note for students (optional)')),
        const SizedBox(height: 22),
        FilledButton(
          onPressed: _busy || _test == null || _scope == null || (_groups.isEmpty && _students.isEmpty) ? null : _save,
          child: const Text('Give homework'),
        ),
      ]),
    );
  }
}
