// The profile's activity grid, as on the website: one square per day (Monday at the top), darker on
// days with more practice; the year picker shows a whole year.
import 'package:flutter/material.dart';

import '../i18n.dart';

import '../api.dart';
import '../theme.dart';

class ActivityCard extends StatefulWidget {
  const ActivityCard({super.key, required this.username, required this.initial});
  final String username;
  final Map<String, dynamic> initial;
  @override
  State<ActivityCard> createState() => _ActivityCardState();
}

class _ActivityCardState extends State<ActivityCard> {
  late Map<String, dynamic> _a = widget.initial;
  int? _year;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _toEnd();
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients && _year == null) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });

  Future<void> _pick(int? y) async {
    try {
      final r = await Api.I.get('/api/app/profile/${widget.username}', {if (y != null) 'year': '$y'});
      if (!mounted || r['activity'] == null) return;
      setState(() { _year = y; _a = (r['activity'] as Map).cast<String, dynamic>(); });
      if (y == null) {
        _toEnd();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) { if (_scroll.hasClients) _scroll.jumpTo(0); });
      }
    } on ApiError {
      /* keep the grid shown */
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hint = Theme.of(context).hintColor;
    final empty = dark ? const Color(0xFF232323) : const Color(0xFFEDEBE6);
    final shades = [empty, for (final a in [.3, .5, .75, 1.0]) C.green.withValues(alpha: a)];
    final weeks = ((_a['weeks'] as List?) ?? []).cast<List>();
    final months = ((_a['months'] as List?) ?? []).cast<Map>();
    final years = ((_a['years'] as List?) ?? []).map((e) => (e as num).toInt()).toList();
    const cell = 12.0, gap = 3.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(tr('Activity'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            if (years.length > 1)
              DropdownButton<int?>(
                value: _year,
                isDense: true,
                underline: const SizedBox.shrink(),
                items: [
                  DropdownMenuItem<int?>(value: null, child: Text(tr('Last year'))),
                  for (final y in years) DropdownMenuItem<int?>(value: y, child: Text('$y')),
                ],
                onChanged: _pick,
              ),
          ]),
          const SizedBox(height: 4),
          Text('${_a['activeDays'] ?? 0} active days · longest run ${_a['maxStreak'] ?? 0}', style: TextStyle(color: hint, fontSize: 13)),
          const SizedBox(height: 12),
          SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                height: 16,
                width: weeks.length * (cell + gap),
                child: Stack(children: [
                  for (final m in months)
                    Positioned(left: ((m['col'] as num).toDouble()) * (cell + gap), child: Text('${m['label']}', style: TextStyle(fontSize: 11, color: hint))),
                ]),
              ),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final w in weeks)
                  Padding(
                    padding: const EdgeInsets.only(right: gap),
                    child: Column(children: [
                      for (final d in w)
                        Padding(
                          padding: const EdgeInsets.only(bottom: gap),
                          child: d == null
                              ? const SizedBox(width: cell, height: cell)
                              : Tooltip(
                                  message: '${(d as Map)['date']}: ${d['points']} ${d['points'] == 1 ? 'activity' : 'activities'}',
                                  child: Container(
                                    width: cell,
                                    height: cell,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(3),
                                      color: d['later'] == true ? empty.withValues(alpha: .4) : shades[((d['level'] as num?) ?? 0).toInt().clamp(0, 4)],
                                    ),
                                  ),
                                ),
                        ),
                    ]),
                  ),
              ]),
            ]),
          ),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            Text(tr('Less '), style: TextStyle(fontSize: 11, color: hint)),
            for (final c in shades) Container(width: 10, height: 10, margin: const EdgeInsets.only(left: 3), decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
            Text(tr(' More'), style: TextStyle(fontSize: 11, color: hint)),
          ]),
        ]),
      ),
    );
  }
}
