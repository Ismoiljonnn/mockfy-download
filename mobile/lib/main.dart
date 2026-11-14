// Mockfy for Android: a native app on the Mockfy server's JSON API.
// Sign-in happens in the phone's browser (Google does not allow it inside apps); the site then opens
// mockfy://auth?code=..., and the app trades that one-time code for its own session.
import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'screens/daily.dart';
import 'screens/home.dart';
import 'screens/leaderboard.dart';
import 'screens/profile.dart';
import 'screens/shop.dart';
import 'theme.dart';
import 'updater.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.I.init();
  runApp(const MockfyApp());
}

class MockfyApp extends StatelessWidget {
  const MockfyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Mockfy',
        debugShowCheckedModeBanner: false,
        theme: mockfyTheme(Brightness.light),
        darkTheme: mockfyTheme(Brightness.dark),
        home: const Gate(),
      );
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
    _check();
  }

  @override
  void dispose() {
    _links?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      final r = await Api.I.get('/api/app/me');
      setState(() { _me = r['me'] as Map<String, dynamic>; _error = null; });
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
              Text('IELTS practice that feels like the real exam.', textAlign: TextAlign.center, style: TextStyle(color: hint, fontSize: 16)),
              const Spacer(),
              if (error != null) ...[
                Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: C.red)),
                const SizedBox(height: 12),
              ],
              FilledButton.icon(
                icon: const Icon(Icons.public_rounded),
                label: const Text('Sign in with your browser'),
                onPressed: () => launchUrl(Uri.parse('$kBaseUrl/auth/desktop/start'), mode: LaunchMode.externalApplication),
              ),
              const SizedBox(height: 10),
              Text('Your browser opens. Sign in there with Google or Telegram, and you come straight back to the app.',
                  textAlign: TextAlign.center, style: TextStyle(color: hint, fontSize: 13)),
              const SizedBox(height: 8),
              TextButton(onPressed: onRetry, child: const Text('I have signed in')),
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

class _ShellState extends State<Shell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => checkForUpdate(context));   // a newer APK installs itself
  }

  void go(int i) => setState(() => _tab = i);

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(me: widget.me, onSignedOut: widget.onSignedOut, goTab: go),
      DailyScreen(onSignedOut: widget.onSignedOut),
      LeaderboardScreen(onSignedOut: widget.onSignedOut),
      ShopScreen(onSignedOut: widget.onSignedOut),
      ProfileScreen(username: widget.me['username'] as String, onSignedOut: widget.onSignedOut, isRoot: true),
    ];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: go,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map_rounded), label: 'Daily'),
          NavigationDestination(icon: Icon(Icons.emoji_events_outlined), selectedIcon: Icon(Icons.emoji_events_rounded), label: 'Leaderboard'),
          NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront_rounded), label: 'Shop'),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Me'),
        ],
      ),
    );
  }
}
