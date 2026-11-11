import 'package:flutter/material.dart';

/// Brand palette: deep petrol blue (trust, finance) with an amber accent
/// (energy, generators).
class Brand {
  static const primary = Color(0xFF0B5F73);
  static const accent = Color(0xFFF2A007);
  static const success = Color(0xFF1E8E5A);
  static const danger = Color(0xFFC0392B);
  static const warning = Color(0xFFE67E22);
  static const info = Color(0xFF2E7DD7);
}

ThemeData buildTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.primary,
    brightness: b,
    primary: b == Brightness.light ? Brand.primary : const Color(0xFF6FC6DA),
    secondary: Brand.accent,
  );
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: 'NotoKufiArabic',
    fontFamilyFallback: const ['NotoSans'],
  );
  final radius = BorderRadius.circular(14);
  return base.copyWith(
    scaffoldBackgroundColor: b == Brightness.light ? const Color(0xFFF4F6F8) : const Color(0xFF0F1417),
    appBarTheme: AppBarTheme(
      backgroundColor: b == Brightness.light ? Colors.white : const Color(0xFF151C20),
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        fontFamily: 'NotoKufiArabic',
        fontFamilyFallback: const ['NotoSans'],
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: b == Brightness.light ? Colors.white : const Color(0xFF182126),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: b == Brightness.light ? const Color(0xFFF7F9FA) : const Color(0xFF1C262B),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontFamily: 'NotoKufiArabic',
          fontFamilyFallback: ['NotoSans'],
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    listTileTheme: const ListTileThemeData(minVerticalPadding: 10),
    chipTheme: base.chipTheme.copyWith(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: b == Brightness.light ? Colors.white : const Color(0xFF151C20),
      indicatorColor: scheme.primaryContainer,
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.5), space: 1),
  );
}
