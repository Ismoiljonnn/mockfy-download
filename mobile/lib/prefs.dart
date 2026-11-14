// The app's own settings, kept on the phone: day / night, sound effects, vibration.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Prefs {
  Prefs._();
  static final Prefs I = Prefs._();
  late SharedPreferences _p;

  final theme = ValueNotifier<ThemeMode>(ThemeMode.system);
  final sound = ValueNotifier<bool>(true);
  final haptics = ValueNotifier<bool>(true);

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    theme.value = switch (_p.getString('theme')) { 'light' => ThemeMode.light, 'dark' => ThemeMode.dark, _ => ThemeMode.system };
    sound.value = _p.getBool('sound') ?? true;
    haptics.value = _p.getBool('haptics') ?? true;
  }

  void setTheme(ThemeMode m) {
    theme.value = m;
    _p.setString('theme', m == ThemeMode.light ? 'light' : m == ThemeMode.dark ? 'dark' : 'system');
  }

  void setSound(bool on) { sound.value = on; _p.setBool('sound', on); }
  void setHaptics(bool on) { haptics.value = on; _p.setBool('haptics', on); }
}

/// Short sound effects, the same ones as on the website: tap, press, right, error, win, coin.
class Sfx {
  static final Map<String, AudioPlayer> _players = {};

  static Future<void> play(String name) async {
    if (Prefs.I.haptics.value) {
      if (name == 'error') { HapticFeedback.mediumImpact(); } else if (name == 'right' || name == 'win') { HapticFeedback.lightImpact(); }
    }
    if (!Prefs.I.sound.value) return;
    try {
      final p = _players.putIfAbsent(name, () => AudioPlayer());
      if (p.audioSource == null) await p.setAsset('assets/sfx/$name.wav');
      await p.seek(Duration.zero);
      p.play();
    } catch (_) { /* a missing sound never stops the app */ }
  }
}
