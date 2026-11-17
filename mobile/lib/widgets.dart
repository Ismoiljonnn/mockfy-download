import 'package:flutter/material.dart';

import 'i18n.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'theme.dart';

/// Loads a JSON screen: a spinner, an error with Try again, or the content; pull down to refresh.
class Loader<T> extends StatefulWidget {
  const Loader({super.key, required this.load, required this.build, this.onSignedOut});
  final Future<T> Function() load;
  final Widget Function(BuildContext, T, Future<void> Function() reload) build;
  final VoidCallback? onSignedOut;
  @override
  State<Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<Loader<T>> {
  T? _data;
  ApiError? _err;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _busy = _data == null);
    try {
      final d = await widget.load();
      if (mounted) setState(() { _data = d; _err = null; _busy = false; });
    } on ApiError catch (e) {
      if (e.signedOut) widget.onSignedOut?.call();
      if (mounted) setState(() { _err = e; _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) return const Center(child: CircularProgressIndicator());
    if (_data == null) return ErrorView(message: _err?.message ?? 'Something went wrong.', onRetry: _reload);
    return RefreshIndicator(onRefresh: _reload, child: widget.build(context, _data as T, _reload));
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.wifi_off_rounded, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: Text(tr('Try again'))),
          ]),
        ),
      );
}

/// The gold Pro tick, like on the website.
class ProTick extends StatelessWidget {
  const ProTick({super.key, this.size = 18});
  final double size;
  @override
  Widget build(BuildContext context) => Icon(Icons.verified_rounded, color: C.gold, size: size);
}

const proPerks = [
  '50 tests a week in each of the four sections (Free: 10)',
  '30 full mock tests a week (Free: 4)',
  'Detailed AI feedback in all four sections: Listening, Reading, Writing and Speaking',
  'A free streak freeze every month',
  'A Pro mark by your name on the leaderboard and your profile',
];

/// What Mockfy Pro gives; without Pro, a button to get it.
void showProSheet(BuildContext context, {required String who, required bool isMe, required bool viewerPro}) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ProTick(size: 72),
          const SizedBox(height: 8),
          Text('Mockfy Pro', style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(isMe ? tr('You have Mockfy Pro. Here is what it gives you:') : '$who has Mockfy Pro. Here is what Pro gives:',
              textAlign: TextAlign.center, style: TextStyle(color: Theme.of(ctx).hintColor)),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(color: Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF282828) : const Color(0xFFF0EEE6),
                borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              for (final p in proPerks)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.check_rounded, color: C.gold, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text(p)),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 18),
          if (!viewerPro)
            FilledButton(onPressed: () => openWeb('/pricing'), child: Text(tr('Get Mockfy Pro')))
          else
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.onSurface, foregroundColor: Theme.of(ctx).scaffoldBackgroundColor),
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('Close')),
            ),
          if (!viewerPro) TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Not now'))),
        ]),
      ),
    ),
  );
}

Future<void> openWeb(String path) => launchUrl(Uri.parse('$kBaseUrl$path'), mode: LaunchMode.externalApplication);
Future<void> openExternal(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

class Avatar extends StatelessWidget {
  const Avatar({super.key, this.url, required this.initial, this.size = 40});
  final String? url;
  final String initial;
  final double size;
  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: size / 2,
        backgroundColor: C.accent.withValues(alpha: .2),
        foregroundImage: url != null ? NetworkImage(_sharp(url!, size)) : null,
        child: Text(initial, style: TextStyle(fontSize: size * .42, fontWeight: FontWeight.w700, color: C.accent)),
      );
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.icon, required this.color, required this.value, required this.label, this.onTap});
  final VoidCallback? onTap;
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: color),
              const SizedBox(height: 8),
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              Text(label, style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13)),
            ]),
          ),
          ),
        ),
      );
}

void toast(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));

/// Google profile photos come small (…=s96-c); ask for one sized for the screen, so they are never blurry.
String _sharp(String url, double size) {
  if (!url.contains('googleusercontent.com')) return url;
  final px = (size * 3).clamp(96, 600).round();
  final m = RegExp(r'=s\d+(-c)?$');
  return m.hasMatch(url) ? url.replaceFirst(m, '=s$px-c') : '$url=s$px-c';
}

/// Tablets held upright fold the side menu into a drawer; the tab pages then show a ☰ button.
class ShellScope extends InheritedWidget {
  const ShellScope({super.key, required this.openMenu, required super.child});
  final VoidCallback? openMenu;
  static VoidCallback? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ShellScope>()?.openMenu;
  @override
  bool updateShouldNotify(ShellScope old) => old.openMenu != openMenu;
}

/// The ☰ button for a tab page's top bar: null (nothing shown) unless the menu is a drawer.
Widget? menuButton(BuildContext context) {
  final open = ShellScope.of(context);
  return open == null ? null : IconButton(tooltip: tr('Menu'), icon: const Icon(Icons.menu_rounded), onPressed: open);
}
