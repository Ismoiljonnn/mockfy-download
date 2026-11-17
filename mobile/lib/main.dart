// Mockfy for Android: a native app on the Mockfy server's JSON API.
// Sign-in happens in the phone's browser (Google does not allow it inside apps); the site then opens
// mockfy://auth?code=..., and the app trades that one-time code for its own session.
import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import 'i18n.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:workmanager/workmanager.dart';

import 'api.dart';
import 'prefs.dart';
import 'screens/daily.dart';
import 'screens/home.dart';
import 'screens/leaderboard.dart';
import 'screens/profile.dart';
import 'desktop_shell.dart';
import 'notify.dart';
import 'screens/more.dart';
import 'screens/teach.dart';
import 'screens/tests.dart';
import 'theme.dart';
import 'updater.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait([Api.I.init(), Prefs.I.init(), Notify.I.init(), I18n.I.init()]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // news from Mockfy reaches the phone even when the app is closed: Android wakes this check about
  // every 15 minutes (its shortest period) while there is a connection
  try {
    await Workmanager().initialize(newsInBackground);
    await Workmanager().registerPeriodicTask('mockfy-news', 'mockfy-news',
        frequency: const Duration(minutes: 15), constraints: Constraints(networkType: NetworkType.connected));
  } catch (_) { /* no background work on this phone: news still arrives when the app opens */ }
  runApp(const MockfyApp());
}

@pragma('vm:entry-point')
void newsInBackground() {
  Workmanager().executeTask((task, data) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    try {
      await Api.I.init();
      await Notify.I.sync();
    } catch (_) {}
    return true;
  });
}

// built once: switching day / night only swaps them, nothing is worked out again
final _light = mockfyTheme(Brightness.light);
final _dark = mockfyTheme(Brightness.dark);

class MockfyApp extends StatelessWidget {
  const MockfyApp({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
        valueListenable: I18n.I.lang,
        builder: (context, lang, _) => ValueListenableBuilder<ThemeMode>(
        valueListenable: Prefs.I.theme,
        builder: (context, mode, _) => MaterialApp(
          key: ValueKey(lang),
          title: 'Mockfy',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: _light,
          darkTheme: _dark,
          // day / night fades over in a quarter of a second instead of snapping
          themeAnimationDuration: const Duration(milliseconds: 280),
          themeAnimationCurve: Curves.easeOutCubic,
          home: const Intro(),
          // the phone's own bars follow day / night on every page (status icons, the button strip at the foot)
          builder: (context, child) {
            final dark = Theme.of(context).brightness == Brightness.dark;
            final bg = Theme.of(context).scaffoldBackgroundColor;
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
                statusBarBrightness: dark ? Brightness.dark : Brightness.light,
                systemNavigationBarColor: dark ? Colors.black : bg,
                systemNavigationBarDividerColor: dark ? Colors.black : bg,
                systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
                systemNavigationBarContrastEnforced: false,
              ),
              // Arabic reads right to left
              child: Directionality(textDirection: I18n.I.rtl ? TextDirection.rtl : TextDirection.ltr, child: child!),
            );
          },
        ),
      ),
      );
}

/// Opening the app: Hudi pops in once, clear and smooth, while the app checks the session; then the app.
class Intro extends StatefulWidget {
  const Intro({super.key});
  @override
  State<Intro> createState() => _IntroState();
}

class _IntroState extends State<Intro> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();
  // carries on from the phone's splash (Hudi already on screen, in his frame): a small breath, then he
  // grows and fades as the app comes through
  late final Animation<double> _scale = TweenSequence([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.08).chain(CurveTween(curve: Curves.easeOutCubic)), weight: 30),
    TweenSequenceItem(tween: Tween(begin: 1.08, end: 1.0).chain(CurveTween(curve: Curves.easeInOutSine)), weight: 25),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 15),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.7).chain(CurveTween(curve: Curves.easeInCubic)), weight: 30),
  ]).animate(_c);
  late final Animation<double> _fade = TweenSequence([
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 70),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)), weight: 30),
  ]).animate(_c);
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) { if (s == AnimationStatus.completed && mounted) setState(() => _done = true); });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // the app is built underneath straight away, so it is ready when Hudi steps aside
    return Stack(children: [
      const Gate(),
      if (!_done)
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => ColoredBox(
                color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: _fade.value),
                child: Center(
                  child: Opacity(
                    opacity: _fade.value,
                    child: Transform.scale(
                      scale: _scale.value,
                      child: Image.asset('assets/hudi.png', width: 130, height: 130, filterQuality: FilterQuality.high),   // Hudi himself, no frame
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}

/// Signed in → the app; signed out → the sign-in screen. Listens for mockfy://auth links all the time.
class Gate extends StatefulWidget {
  const Gate({super.key});
  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> {
  Map<String, dynamic>? _me;
  bool _checking = true;
  bool _claiming = false;
  String? _error;
  StreamSubscription<Uri>? _links;

  @override
  void initState() {
    super.initState();
    final links = AppLinks();
    _links = links.uriLinkStream.listen(_onLink);
    links.getInitialLink().then((u) { if (u != null) _onLink(u); });
    Prefs.I.workspaceChanged.addListener(_check);
    _check();
  }

  @override
  void dispose() {
    Prefs.I.workspaceChanged.removeListener(_check);
    _links?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      final r = await Api.I.get('/api/app/me');
      setState(() { _me = r['me'] as Map<String, dynamic>; _error = null; });
      final lang = (r['me'] as Map)['lang'];
      if (lang is String) I18n.I.set(lang);              // the account's language, as on the website
    } on ApiError catch (e) {
      setState(() { _me = null; _error = e.signedOut || e.status == 403 ? null : e.message; });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _onLink(Uri u) async {
    final code = u.queryParameters['code'];
    if (u.scheme != 'mockfy' || u.host != 'auth' || code == null) return;
    setState(() => _claiming = true);
    final ok = await Api.I.claim(code);
    if (!mounted) return;
    setState(() => _claiming = false);
    if (!ok) {
      setState(() => _error = 'That sign-in link has expired. Please sign in again.');
      return;
    }
    await _check();
  }

  Future<void> _signOut() async {
    await Api.I.signOut();
    if (mounted) setState(() => _me = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking || _claiming) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_me == null) return SignInScreen(error: _error, onRetry: _check);
    return Shell(me: _me!, onSignedOut: _signOut, onRefreshMe: _check);
  }
}

class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key, this.error, required this.onRetry});
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Theme.of(context).brightness == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const Spacer(),
              ClipRRect(borderRadius: BorderRadius.circular(28), child: Image.asset('assets/icon.png', width: 112, height: 112)),
              const SizedBox(height: 24),
              Text('Mockfy', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1)),
              const SizedBox(height: 8),
              Text(tr('IELTS practice that feels like the real exam.'), textAlign: TextAlign.center, style: TextStyle(color: hint, fontSize: 16)),
              const Spacer(),
              if (error != null) ...[
                Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: C.red)),
                const SizedBox(height: 12),
              ],
              FilledButton.icon(
                icon: const Icon(Icons.public_rounded),
                label: Text(tr('Sign in with your browser')),
                onPressed: () => launchUrl(Uri.parse('$kBaseUrl/auth/desktop/start'), mode: LaunchMode.externalApplication),
              ),
              const SizedBox(height: 10),
              Text(tr('Your browser opens. Sign in there with Google or Telegram, and you come straight back to the app.'),
                  textAlign: TextAlign.center, style: TextStyle(color: hint, fontSize: 13)),
              const SizedBox(height: 8),
              TextButton(onPressed: onRetry, child: Text(tr('I have signed in'))),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The five tabs.
class Shell extends StatefulWidget {
  const Shell({super.key, required this.me, required this.onSignedOut, required this.onRefreshMe});
  final Map<String, dynamic> me;
  final VoidCallback onSignedOut;
  final Future<void> Function() onRefreshMe;
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int _tab = 0;
  final _scaffold = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkForUpdate(context);                    // a newer APK installs itself
      Notify.I.askPermission();                   // Android 13+ asks once before showing notifications
      Notify.I.sync();                            // Mockfy's news as phone notifications, and the badge
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) Notify.I.sync();
  }

  void go(int i) => setState(() => _tab = i);

  @override
  Widget build(BuildContext context) {
    final ws = ((widget.me['workspaces'] as List?) ?? []).cast<Map>().where((w) => w['active'] == true).map((w) => '${w['kind']}').firstOrNull ?? 'ielts';
    final teacher = ws == 'teacher';
    // the Profile tab is your own profile page (notifications, settings and help at its foot)
    final me = ProfileScreen(username: widget.me['username'] as String, onSignedOut: widget.onSignedOut, isRoot: true);
    final pages = teacher
        ? <Widget>[
            TeachHomeScreen(me: widget.me, onSignedOut: widget.onSignedOut, goTab: go),
            StudentsScreen(onSignedOut: widget.onSignedOut),
            AssignmentsScreen(onSignedOut: widget.onSignedOut),
            me,
          ]
        : <Widget>[
            HomeScreen(me: widget.me, onSignedOut: widget.onSignedOut, goTab: go),
            TestsScreen(onSignedOut: widget.onSignedOut),
            DailyScreen(onSignedOut: widget.onSignedOut),
            FeaturesScreen(me: widget.me, onSignedOut: widget.onSignedOut),
            me,
          ];
    if (_tab >= pages.length) _tab = 0;
    final destinations = teacher
        ? <NavigationDestination>[
            NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard_rounded), label: tr('Class')),
            NavigationDestination(icon: Icon(Icons.people_alt_outlined), selectedIcon: Icon(Icons.people_alt_rounded), label: tr('Students')),
            NavigationDestination(icon: Icon(Icons.assignment_outlined), selectedIcon: Icon(Icons.assignment_rounded), label: tr('Homework')),
            NavigationDestination(icon: _MoreIcon(selected: false), selectedIcon: _MoreIcon(selected: true), label: tr('Profile')),
          ]
        : <NavigationDestination>[
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: tr('Home')),
            NavigationDestination(icon: Icon(Icons.assignment_outlined), selectedIcon: Icon(Icons.assignment_rounded), label: tr('Tests')),
            NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map_rounded), label: tr('Daily')),
            NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded), label: tr('More')),
            NavigationDestination(icon: _MoreIcon(selected: false), selectedIcon: _MoreIcon(selected: true), label: tr('Profile')),
          ];
    final body = IndexedStack(key: ValueKey(ws), index: _tab, children: pages);
    // tablets and wide windows: laid out like the desktop app, the menu down the left side with names,
    // the pages beside it; phones keep the bar at the bottom
    final screen = MediaQuery.sizeOf(context);
    if (screen.shortestSide >= 600) {
      // tablets: laid out like the desktop app (upright, the sidebar becomes a drawer)
      return DesktopShell(
        key: ValueKey('desk-$ws'),
        me: widget.me,
        teacher: teacher,
        onSignedOut: widget.onSignedOut,
        drawer: screen.height > screen.width,
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: _BottomBar(selected: _tab, onSelect: go, items: destinations),
    );
  }
}

/// The phone's bottom bar: icon buttons as tall rounded squares (not wide flat pills), the bar itself
/// no taller than it needs to be.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.selected, required this.onSelect, required this.items});
  final int selected;
  final void Function(int) onSelect;
  final List<NavigationDestination> items;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    // at night the bar (and the phone's own button strip under it) is black
    final barColour = dark ? Colors.black : t.colorScheme.surface;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        systemNavigationBarColor: barColour,
        systemNavigationBarDividerColor: barColour,
        systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      ),
      child: Material(
      color: barColour,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: Center(
                  child: Tooltip(
                    message: items[i].label,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => onSelect(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 54, height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: i == selected ? (dark ? Colors.white.withValues(alpha: .1) : const Color(0xFF141413).withValues(alpha: .08)) : Colors.transparent,
                        ),
                        child: IconTheme(
                          data: IconThemeData(size: 26, color: i == selected ? t.colorScheme.onSurface : t.hintColor),
                          child: i == selected ? (items[i].selectedIcon ?? items[i].icon) : items[i].icon,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
    ),
    );
  }
}

/// The More tab's icon, with a dot when there are unread notifications.
class _MoreIcon extends StatelessWidget {
  const _MoreIcon({required this.selected});
  final bool selected;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: Notify.I.unread,
        builder: (context, n, _) => Badge(
          isLabelVisible: n > 0,
          smallSize: 9,
          child: Icon(selected ? Icons.person_rounded : Icons.person_outline_rounded),
        ),
      );
}
