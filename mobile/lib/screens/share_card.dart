// "Share result", as on the website: a picture of the band (and the four sections) with your name,
// made on the phone and handed to Telegram, Instagram or any app through the share sheet.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../i18n.dart';
import '../theme.dart';
import '../widgets.dart';

Future<void> shareResult(BuildContext context, {required String test, required String name, required Object band,
    required String label, List<(String, Object?)> sections = const []}) async {
  final key = GlobalKey();
  await showDialog<void>(
    context: context,
    builder: (c) => Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        RepaintBoundary(key: key, child: _Card(test: test, name: name, band: band, label: label, sections: sections)),
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: () async {
              try {
                final box = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
                final img = await box.toImage(pixelRatio: 3);
                final png = await img.toByteData(format: ui.ImageByteFormat.png);
                final f = File('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}mockfy_result.png');
                await f.writeAsBytes(png!.buffer.asUint8List());
                await Share.shareXFiles([XFile(f.path, mimeType: 'image/png')], text: tr('My IELTS result on Mockfy: mockfy.uz'));
              } catch (_) {
                if (c.mounted) toast(c, tr('Could not make the picture. Try again.'));
              }
            },
            icon: const Icon(Icons.share_rounded),
            label: Text(tr('Share')),
          ),
        ),
      ]),
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.test, required this.name, required this.band, required this.label, required this.sections});
  final String test, name, label;
  final Object band;
  final List<(String, Object?)> sections;
  @override
  Widget build(BuildContext context) => Container(
        width: 340,
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1F1F1F), Color(0xFF2B2018)]),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Image.asset('assets/icon.png', width: 28, height: 28),
            const SizedBox(width: 8),
            const Text('Mockfy', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
          ]),
          const SizedBox(height: 18),
          Text(test, style: const TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('$band', style: const TextStyle(color: C.accent, fontSize: 64, fontWeight: FontWeight.w900, height: 1)),
            const SizedBox(width: 10),
            Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 15)))),
          ]),
          if (sections.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(children: [
              for (final s in sections)
                Expanded(
                  child: Column(children: [
                    Text(s.$2 == null ? '–' : '${s.$2}', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                    Text(s.$1, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  ]),
                ),
            ]),
          ],
          const SizedBox(height: 18),
          Image.asset('assets/hudi/cheer.png', height: 70),
          const SizedBox(height: 8),
          Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          const Text('mockfy.uz', style: TextStyle(color: Colors.white54, fontSize: 12)),
        ]),
      );
}
