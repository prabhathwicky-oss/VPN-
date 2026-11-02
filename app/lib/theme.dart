import 'package:flutter/material.dart';

class Palette {
  static const ink = Color(0xFF0B1020);
  static const surface = Color(0xFF141A2E);
  static const surfaceHigh = Color(0xFF1C2440);
  static const line = Color(0xFF2A3354);
  static const text = Color(0xFFE8ECF8);
  static const muted = Color(0xFF8C95B3);
  static const mint = Color(0xFF2EE6A8);   // connected
  static const amber = Color(0xFFFFB547);  // connecting
  static const coral = Color(0xFFFF6B6B);  // error / disconnected accent
  static const violet = Color(0xFF8B7CFF); // pro
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Palette.mint,
    brightness: Brightness.dark,
    surface: Palette.surface,
  ).copyWith(primary: Palette.mint, secondary: Palette.violet, error: Palette.coral);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.ink,
    appBarTheme: const AppBarTheme(
      backgroundColor: Palette.ink,
      foregroundColor: Palette.text,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: const CardThemeData(
      color: Palette.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
        side: BorderSide(color: Palette.line),
      ),
    ),
    dividerColor: Palette.line,
    textTheme: const TextTheme(
      headlineMedium: TextStyle(fontWeight: FontWeight.w700, color: Palette.text, letterSpacing: -0.5),
      titleLarge: TextStyle(fontWeight: FontWeight.w700, color: Palette.text),
      titleMedium: TextStyle(fontWeight: FontWeight.w600, color: Palette.text),
      bodyMedium: TextStyle(color: Palette.text),
      bodySmall: TextStyle(color: Palette.muted),
      labelLarge: TextStyle(fontWeight: FontWeight.w600),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Palette.mint,
        foregroundColor: Palette.ink,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Palette.text,
        side: const BorderSide(color: Palette.line),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Palette.ink : Palette.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Palette.mint : Palette.surfaceHigh),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Palette.surfaceHigh,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
