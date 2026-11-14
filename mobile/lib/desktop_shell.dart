// Tablets: the app laid out like the Mockfy desktop app. A sidebar (fold, back, forward at the top;
// every section listed; the account at the foot), a top row on the page (its name; points, crystals,
// streak, the bell), and the pages opening beside the sidebar. All native, as on the phone.
import 'package:flutter/material.dart';

import 'api.dart';
import 'notify.dart';
import 'screens/daily.dart';
import 'screens/games.dart';
import 'screens/home.dart';
import 'screens/leaderboard.dart';
import 'screens/more.dart';
import 'screens/profile.dart';
import 'screens/settings.dart';
import 'screens/shop.dart';
import 'screens/teach.dart';
import 'screens/tests.dart';
import 'theme.dart';
import 'widgets.dart';

/// Set around the pages shown inside the desktop layout: their own top bars give way to the shell's row.
class DesktopScope extends InheritedWidget {
  const DesktopScope({super.key, required super.child});
  static bool on(BuildContext context) => context.dependOnInheritedWidgetOfExactType<DesktopScope>() != null;
  @override
  bool updateShouldNotify(DesktopScope old) => false;
}

/// A section page's top bar: as is on the phone; inside the desktop layout only its tabs remain (the
/// page's name is in the shell's top row).
PreferredSizeWidget? rootBar(BuildContext context, AppBar bar) {
  if (!DesktopScope.on(context)) return bar;
  if (bar.bottom == null) return null;
  return AppBar(toolbarHeight: 0, automaticallyImplyLeading: false, bottom: bar.bottom);
}

class _Item {
  const _Item(this.label, this.icon, this.page);
  final String label;
  final IconData icon;
  final Widget Function() page;
}

class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key, required this.me, required this.teacher, required this.onSignedOut, required this.drawer});
  final Map<String, dynamic> me;
  final bool teacher;
  final VoidCallback onSignedOut;
  final bool drawer;          // a tablet held upright: the sidebar is a drawer
  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  final _nav = GlobalKey<NavigatorState>();
  final _scaffold = GlobalKey<ScaffoldState>();
  final List<int> _back = [], _forward = [];
  int _sel = 0;
  bool _folded = false;
  Map<String, dynamic> _me = {};
  int _pageKey = 0;

  @override
  void initState() {
    super.initState();
    _me = widget.me;
  }

  Future<void> _refreshMe() async {
    try {
      final r = await Api.I.get('/api/app/me');
      if (mounted) setState(() => _me = (r['me'] as Map).cast<String, dynamic>());
    } on ApiError catch (_) {}
  }

  List<_Item> get _items {
    final so = widget.onSignedOut;
    if (widget.teacher) {
      return [
        _Item('My class', Icons.dashboard_rounded, () => TeachHomeScreen(me: _me, onSignedOut: so, goTab: (i) => _select(i))),
        _Item('Students', Icons.people_alt_rounded, () => StudentsScreen(onSignedOut: so)),
        _Item('Homework', Icons.assignment_rounded, () => AssignmentsScreen(onSignedOut: so)),
      ];
    }
    return [
      _Item('Dashboard', Icons.dashboard_rounded, () => HomeScreen(me: _me, onSignedOut: so, goTab: (i) => _select(const [0, 1, 3, 5, 9][i.clamp(0, 4)]))),
      _Item('Full mock', Icons.assignment_turned_in_rounded, () => TestsScreen(onSignedOut: so, initialTab: 0)),
      _Item('Section practice', Icons.track_changes_rounded, () => TestsScreen(onSignedOut: so, initialTab: 1)),
      _Item('Daily English', Icons.map_rounded, () => DailyScreen(onSignedOut: so)),
      _Item('Games', Icons.sports_esports_rounded, () => const GamesScreen()),
      _Item('Leaderboard', Icons.emoji_events_rounded, () => LeaderboardScreen(onSignedOut: so)),
      _Item('Shop', Icons.storefront_rounded, () => ShopScreen(onSignedOut: so)),
      _Item('My words', Icons.style_rounded, () => const WordsReviewScreen()),
      _Item('My results', Icons.history_rounded, () => const HistoryScreen()),
      _Item('Recommendations', Icons.lightbulb_rounded, () => const RecommendationsScreen()),
    ];
  }

  void _select(int i, {bool record = true}) {
    if (i < 0 || i >= _items.length) return;
    if (widget.drawer && (_scaffold.currentState?.isDrawerOpen ?? false)) Navigator.of(context).pop();
    if (i == _sel && !(_nav.currentState?.canPop() ?? false)) return;
    setState(() {
      if (record && i != _sel) { _back.add(_sel); _forward.clear(); }
      _sel = i;
      _pageKey++;
    });
    _refreshMe();
  }

  void _goBack() {
    final nav = _nav.currentState;
    if (nav != null && nav.canPop()) { nav.pop(); return; }
    if (_back.isEmpty) return;
    _forward.add(_sel);
    _select(_back.removeLast(), record: false);
  }

  void _goForward() {
    if (_forward.isEmpty) return;
    _back.add(_sel);
    _select(_forward.removeLast(), record: false);
  }

  void _open(Widget page) {
    if (widget.drawer && (_scaffold.currentState?.isDrawerOpen ?? false)) Navigator.of(context).pop();
    _nav.currentState?.push(MaterialPageRoute(builder: (_) => page));
  }

  // ---------------------------------------------------------------- the sidebar
  Widget _sidebar(BuildContext context, {required bool narrow}) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF141414) : const Color(0xFFF3F1EA);
    final items = _items;
    final name = '${_me['name'] ?? ''}';
    Widget topBtn(IconData icon, String tip, VoidCallback? onTap) =>
        IconButton(tooltip: tip, onPressed: onTap, icon: Icon(icon, size: 22), color: t.hintColor, visualDensity: VisualDensity.compact);
    return Container(
      width: narrow ? 72 : 260,
      color: bg,
      child: SafeArea(
        right: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // the top row, as in the desktop app: fold, back, forward
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: narrow
                ? topBtn(Icons.view_sidebar_outlined, 'Show the sidebar', () => setState(() => _folded = false))
                : Row(children: [
                    if (!widget.drawer) topBtn(Icons.view_sidebar_outlined, 'Fold the sidebar', () => setState(() => _folded = true)),
                    topBtn(Icons.chevron_left_rounded, 'Back', (_back.isNotEmpty || (_nav.currentState?.canPop() ?? false)) ? _goBack : null),
                    topBtn(Icons.chevron_right_rounded, 'Forward', _forward.isNotEmpty ? _goForward : null),
                    const Spacer(),
                    Image.asset('assets/hudi.png', width: 28, height: 28),
                    const SizedBox(width: 8),
                  ]),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView(padding: const EdgeInsets.symmetric(horizontal: 10), children: [
              for (var i = 0; i < items.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Material(
                    color: i == _sel ? (dark ? Colors.white.withValues(alpha: .09) : const Color(0xFF141413).withValues(alpha: .07)) : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _select(i),
                      child: Tooltip(
                        message: narrow ? items[i].label : '',
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: narrow ? 0 : 12, vertical: 11),
                          child: Row(mainAxisAlignment: narrow ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
                            Icon(items[i].icon, size: 21, color: i == _sel ? t.colorScheme.onSurface : t.hintColor),
                            if (!narrow) ...[
                              const SizedBox(width: 12),
                              Expanded(child: Text(items[i].label, overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 15, fontWeight: i == _sel ? FontWeight.w700 : FontWeight.w500))),
                            ],
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
          // the account at the foot: the line runs edge to edge; photo, name · plan, and the gear
          Divider(height: 1, thickness: 1, color: t.dividerColor.withValues(alpha: .5)),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
            child: narrow
                ? IconButton(tooltip: 'Settings', icon: const Icon(Icons.settings_rounded),
                    onPressed: () => _open(SettingsScreen(username: '${_me['username']}', onSignedOut: widget.onSignedOut)))
                : Row(children: [
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _open(ProfileScreen(username: '${_me['username']}', onSignedOut: widget.onSignedOut)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                          child: Row(children: [
                            Avatar(url: _me['avatar'] as String?, initial: name.isEmpty ? '?' : name[0].toUpperCase(), size: 30),
                            const SizedBox(width: 10),
                            Flexible(child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                            Text(' · ${_me['isPro'] == true ? 'Pro' : 'Free'}', style: TextStyle(color: t.hintColor)),
                          ]),
                        ),
                      ),
                    ),
                    IconButton(tooltip: 'Settings', icon: Icon(Icons.settings_outlined, color: t.hintColor),
                        onPressed: () => _open(SettingsScreen(username: '${_me['username']}', onSignedOut: widget.onSignedOut))),
                  ]),
          ),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- the top row of the page
  Widget _topRow(BuildContext context) {
    final t = Theme.of(context);
    Widget chip(IconData icon, Color color, String value, String tip, VoidCallback onTap) => Tooltip(
          message: tip,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 5),
                Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 15)),
              ]),
            ),
          ),
        );
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.dividerColor.withValues(alpha: .4)))),
      child: Row(children: [
        if (widget.drawer)
          IconButton(icon: const Icon(Icons.menu_rounded), onPressed: () => _scaffold.currentState?.openDrawer()),
        Expanded(child: Text(_items[_sel].label, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
        if (!widget.teacher) ...[
          chip(Icons.star_rounded, C.gold, '${_me['points'] ?? 0}', 'Points', () => _select(5)),
          const SizedBox(width: 6),
          chip(Icons.diamond_rounded, const Color(0xFF9B7BEA), '${_me['crystals'] ?? 0}', 'Crystals', () => _select(6)),
          const SizedBox(width: 6),
          chip(Icons.local_fire_department_rounded, (_me['streak'] ?? 0) > 0 ? C.accent : t.hintColor, '${_me['streak'] ?? 0}', 'Day streak', () => _select(3)),
          const SizedBox(width: 6),
        ],
        ValueListenableBuilder<int>(
          valueListenable: Notify.I.unread,
          builder: (context, n, _) => IconButton(
            tooltip: 'Notifications',
            icon: Badge(isLabelVisible: n > 0, label: Text('$n'), child: Icon(Icons.notifications_none_rounded, color: t.hintColor)),
            onPressed: () => _open(const NotificationsScreen()),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = DesktopScope(
      child: Navigator(
        key: _nav,
        observers: [_Watch(() { if (mounted) setState(() {}); })],
        onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => KeyedSubtree(key: ValueKey(_pageKey), child: _items[_sel].page())),
      ),
    );
    final content = Column(children: [
      _topRow(context),
      Expanded(child: KeyedSubtree(key: ValueKey('page-$_pageKey'), child: page)),
    ]);
    if (widget.drawer) {
      return Scaffold(
        key: _scaffold,
        drawer: Drawer(width: 280, child: _sidebar(context, narrow: false)),
        body: SafeArea(child: content),
      );
    }
    return Scaffold(
      key: _scaffold,
      body: Row(children: [
        AnimatedSize(duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic, child: _sidebar(context, narrow: _folded)),
        VerticalDivider(width: 1, thickness: 1, color: Theme.of(context).dividerColor.withValues(alpha: .4)),
        Expanded(child: SafeArea(left: false, child: content)),
      ]),
    );
  }
}

/// Redraws the sidebar's back / forward buttons when a page opens or closes inside the content area.
class _Watch extends NavigatorObserver {
  _Watch(this.changed);
  final VoidCallback changed;
  @override
  void didPush(Route route, Route? previousRoute) => WidgetsBinding.instance.addPostFrameCallback((_) => changed());
  @override
  void didPop(Route route, Route? previousRoute) => WidgetsBinding.instance.addPostFrameCallback((_) => changed());
}
