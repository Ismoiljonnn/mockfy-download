import 'package:flutter/material.dart';

class C {
  static const accent = Color(0xFFD97757);
  static const gold = Color(0xFFE8A52A);
  static const green = Color(0xFF4CB782);
  static const red = Color(0xFFE5534B);
  static const blue = Color(0xFF5B8DEF);
}

ThemeData mockfyTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final bg = dark ? const Color(0xFF1A1A1A) : const Color(0xFFFAF9F5);
  final surface = dark ? const Color(0xFF282828) : Colors.white;
  final ink = dark ? const Color(0xFFECECEC) : const Color(0xFF141413);
  final scheme = ColorScheme.fromSeed(seedColor: C.accent, brightness: b).copyWith(
    primary: C.accent,
    surface: surface,
    onSurface: ink,
    surfaceContainerLowest: bg,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    appBarTheme: AppBarTheme(backgroundColor: bg, foregroundColor: ink, elevation: 0, scrolledUnderElevation: 0, centerTitle: false,
        titleTextStyle: TextStyle(color: ink, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -.3)),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16), side: BorderSide(color: dark ? const Color(0xFF333333) : const Color(0xFFE5E2D8))),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: C.accent.withValues(alpha: .18),
      labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12, color: ink, fontWeight: FontWeight.w500)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
          backgroundColor: C.accent, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48), foregroundColor: ink,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    ),
  );
}
