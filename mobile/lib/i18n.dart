// The app in the website's languages: English (the keys), Uzbek, Russian, Turkish, Arabic, Hindi,
// Tajik, Kyrgyz and Chinese. The texts are in assets/i18n/<code>.json (English -> translation, built
// from the website's own translations by tool/make_i18n.py). The language is the account's: changing it
// here changes it on the website too, so marking and feedback arrive in the same language.
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kLangs = [
  ('en', 'English'),
  ('uz', "O'zbekcha"),
  ('ru', 'Русский'),
  ('tr', 'Türkçe'),
  ('ar', 'العربية'),
  ('hi', 'हिन्दी'),
  ('tg', 'Тоҷикӣ'),
  ('ky', 'Кыргызча'),
  ('zh', '中文'),
];

class I18n {
  I18n._();
  static final I18n I = I18n._();
  final lang = ValueNotifier<String>('en');
  Map<String, String> _t = const {};

  bool get rtl => lang.value == 'ar';

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    var code = p.getString('lang');
    if (code == null) {
      final phone = ui.PlatformDispatcher.instance.locale.languageCode;
      code = kLangs.any((l) => l.$1 == phone) ? phone : 'en';
    }
    await _load(code);
  }

  Future<void> _load(String code) async {
    if (code == 'en') {
      _t = const {};
    } else {
      try {
        _t = (jsonDecode(await rootBundle.loadString('assets/i18n/$code.json')) as Map).cast<String, String>();
      } catch (_) {
        _t = const {};
        code = 'en';
      }
    }
    lang.value = code;
  }

  /// From the account (the server's choice wins once signed in) or from Settings.
  Future<void> set(String code) async {
    if (!kLangs.any((l) => l.$1 == code) || code == lang.value) return;
    (await SharedPreferences.getInstance()).setString('lang', code);
    await _load(code);
  }

  String t(String en, [Map<String, Object?>? vars]) {
    var s = _t[en] ?? en;
    if (vars != null) {
      vars.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    }
    return s;
  }
}

/// The text in the app's language: tr('Settings'), tr('{n} words', {'n': 5}).
String tr(String en, [Map<String, Object?>? vars]) => I18n.I.t(en, vars);
