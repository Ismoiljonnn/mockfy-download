// Keeps the installed APK up to date: on start it asks GitHub for the newest release; when that is newer
// than this app, it downloads Mockfy.apk in the background and opens Android's installer (Android always
// asks the user to tap Install once for apps that are not from a store).
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

const _latest = 'https://api.github.com/repos/Ismoiljonnn/mockfy-download/releases/latest';
const _apk = 'https://github.com/Ismoiljonnn/mockfy-download/releases/latest/download/Mockfy.apk';

List<int> _parse(String v) =>
    v.replaceFirst(RegExp(r'^v'), '').split(RegExp(r'[.+]')).take(3).map((p) => int.tryParse(p) ?? 0).toList();

bool _newer(String remote, String local) {
  final a = _parse(remote), b = _parse(local);
  for (var i = 0; i < 3; i++) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

bool _running = false;

Future<void> checkForUpdate(BuildContext context) async {
  if (!Platform.isAndroid || _running) return;
  _running = true;
  try {
    final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(minutes: 5)));
    final info = await PackageInfo.fromPlatform();
    final r = await dio.get(_latest, options: Options(headers: {'Accept': 'application/vnd.github+json'}));
    final tag = (r.data is Map ? r.data['tag_name'] : null)?.toString() ?? '';
    if (tag.isEmpty || !_newer(tag, info.version)) return;

    final messenger = context.mounted ? ScaffoldMessenger.of(context) : null;
    messenger?.showSnackBar(SnackBar(content: Text('Downloading Mockfy ${tag.replaceFirst('v', '')}…'), behavior: SnackBarBehavior.floating));
    final dir = await getTemporaryDirectory();
    final file = '${dir.path}${Platform.pathSeparator}Mockfy-$tag.apk';
    if (!File(file).existsSync()) {
      await dio.download(_apk, '$file.part');
      await File('$file.part').rename(file);
    }
    messenger?.hideCurrentSnackBar();
    await OpenFilex.open(file, type: 'application/vnd.android.package-archive');
  } catch (_) {
    // no connection, or GitHub busy: next start tries again
  } finally {
    _running = false;
  }
}
