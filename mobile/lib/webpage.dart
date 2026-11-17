// A part of Mockfy shown inside the app (games, vocabulary, shadowing, Speaking Room, Mock Day): the
// website's page in the app's own window, already signed in with the app's session.
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'api.dart';
import 'prefs.dart';
import 'widgets.dart';

class WebPage extends StatefulWidget {
  const WebPage({super.key, required this.title, required this.path});
  final String title;
  final String path;
  @override
  State<WebPage> createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  WebViewController? _c;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Color _bg = const Color(0xFF1A1A1A);

  Future<void> _open() async {
    await Future<void>.delayed(Duration.zero);          // after the first frame: the theme is known
    if (!mounted) return;
    _bg = Theme.of(context).scaffoldBackgroundColor;
    final host = Uri.parse(kBaseUrl).host;
    final jar = WebViewCookieManager();
    for (final c in await Api.I.cookies()) {
      await jar.setCookie(WebViewCookie(name: c.name, value: c.value, domain: c.domain ?? host, path: c.path ?? '/'));
    }
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(_bg)
      ..setUserAgent('MockfyMobile/1.0 (Android) Mozilla/5.0 Mobile')
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) { if (mounted) setState(() => _progress = p); },
        // the games and Daily on the website play sounds too: they follow the app's Sound effects switch
        onPageFinished: (_) => _c?.runJavaScript("try{localStorage.setItem('mf-sound','${Prefs.I.sound.value ? 'on' : 'off'}')}catch(e){}"),
        onNavigationRequest: (r) {
          final u = Uri.tryParse(r.url);
          // our own pages stay here; anything else opens in the browser
          if (u != null && u.host.isNotEmpty && u.host != host) {
            openExternal(r.url);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse('$kBaseUrl${widget.path}'));
    if (mounted) setState(() => _c = c);
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (c != null && await c.canGoBack()) { c.goBack(); } else if (context.mounted) { Navigator.pop(context); }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          bottom: _progress < 100
              ? PreferredSize(preferredSize: const Size.fromHeight(2), child: LinearProgressIndicator(value: _progress / 100, minHeight: 2))
              : null,
        ),
        body: c == null ? const Center(child: CircularProgressIndicator()) : WebViewWidget(controller: c),
      ),
    );
  }
}
