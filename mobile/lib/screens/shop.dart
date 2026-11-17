import 'package:flutter/material.dart';

import '../i18n.dart';

import '../desktop_shell.dart';
import '../api.dart';
import '../theme.dart';
import '../prefs.dart';
import '../widgets.dart';

const _icons = {
  'streak_freeze': Icons.ac_unit_rounded,
  'streak_restore': Icons.restore_rounded,
  'boost_x2': Icons.bolt_rounded,
  'second_chance': Icons.replay_rounded,
  'exam_hint': Icons.lightbulb_rounded,
  'word_cards': Icons.style_rounded,
  'pro_day': Icons.verified_rounded,
  'pro_week': Icons.verified_rounded,
};

/// The shop's useful items, bought with crystals; the ones used by hand (streak restore, Pro passes) too.
class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key, required this.onSignedOut});
  final VoidCallback onSignedOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: rootBar(context, AppBar(title: Text(tr('Shop')))),
      body: Loader<Map<String, dynamic>>(
        load: () async => (await Api.I.get('/api/shop'))['shop'] as Map<String, dynamic>,
        onSignedOut: onSignedOut,
        build: (context, s, reload) {
          final items = (s['items'] as List).cast<Map>().map((e) => e.cast<String, dynamic>())
              .where((it) => it['kind'] == 'use').toList();
          return ListView(padding: const EdgeInsets.all(16), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  const Icon(Icons.diamond_rounded, color: Color(0xFF9B7BEA), size: 32),
                  const SizedBox(width: 12),
                  Text('${s['balance']}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 6),
                  Text(tr('crystals'), style: TextStyle(color: Theme.of(context).hintColor)),
                ]),
              ),
            ),
            if (s['canRestore'] == true) ...[
              const SizedBox(height: 12),
              Card(
                color: C.accent.withValues(alpha: .12),
                child: ListTile(
                  leading: Icon(Icons.local_fire_department_rounded, color: C.accent),
                  title: Text(tr('Your streak can still be brought back')),
                  subtitle: Text(tr('Use a Streak restore below.')),
                ),
              ),
            ],
            const SizedBox(height: 8),
            for (final it in items) _ItemCard(item: it, balance: (s['balance'] as num).toInt(), canRestore: s['canRestore'] == true, reload: reload),
          ]);
        },
      ),
    );
  }
}

class _ItemCard extends StatefulWidget {
  const _ItemCard({required this.item, required this.balance, required this.canRestore, required this.reload});
  final Map<String, dynamic> item;
  final int balance;
  final bool canRestore;
  final Future<void> Function() reload;
  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  bool _busy = false;

  Future<void> _do(String what) async {
    final it = widget.item;
    if (what == 'buy') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(tr('Buy {x}?', {'x': it['name']})),
          content: Text('${it['price']} crystals. ${it['about']}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Cancel'))),
            FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(88, 44)), onPressed: () => Navigator.pop(c, true), child: Text(tr('Buy'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      await Api.I.post('/api/shop/$what', {'item': it['id']});
      
      if (mounted) toast(context, what == 'buy' ? '${it['name']} bought.' : '${it['name']} switched on.');
      await widget.reload();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final qty = (it['qty'] as num?)?.toInt() ?? 0;
    final max = (it['max'] as num?)?.toInt() ?? 99;
    final price = (it['price'] as num?)?.toInt() ?? 0;
    final usable = qty > 0 && (it['id'] == 'pro_day' || it['id'] == 'pro_week' || (it['id'] == 'streak_restore' && widget.canRestore));
    final full = qty >= max;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(color: C.accent.withValues(alpha: .14), borderRadius: BorderRadius.circular(12)),
              child: Icon(_icons[it['id']] ?? Icons.inventory_2_rounded, color: (it['id'] as String).startsWith('pro') ? C.gold : C.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text('${it['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                  if (qty > 0) ...[
                    const SizedBox(width: 6),
                    Text('×$qty', style: const TextStyle(color: C.green, fontWeight: FontWeight.w700)),
                  ],
                ]),
                const SizedBox(height: 3),
                Text('${it['about']}', style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13)),
                const SizedBox(height: 10),
                Row(children: [
                  if (usable) ...[
                    FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 38), backgroundColor: C.green),
                      onPressed: _busy ? null : () => _do('use'),
                      child: Text(tr('Use')),
                    ),
                    const SizedBox(width: 8),
                  ],
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38)),
                    onPressed: _busy || full || widget.balance < price ? null : () => _do('buy'),
                    icon: const Icon(Icons.diamond_rounded, size: 16, color: Color(0xFF9B7BEA)),
                    label: Text(full ? tr('Full') : '$price'),
                  ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
