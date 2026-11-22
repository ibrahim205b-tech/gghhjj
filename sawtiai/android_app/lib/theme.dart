import 'package:flutter/material.dart';

/// Sawti AI visual identity.
class SawtiColors {
  static const deepPurple = Color(0xFF6C2BD9);
  static const purpleDark = Color(0xFF3B1683);
  static const electricBlue = Color(0xFF3DA9FC);
  static const cyan = Color(0xFF5CE1E6);
  static const bgDark = Color(0xFF0B0B14);
  static const surfaceDark = Color(0xFF15152A);
  static const surfaceDark2 = Color(0xFF1E1E38);
  static const bgLight = Color(0xFFF5F4FB);
  static const textMuted = Color(0xFFA0A3B1);
  static const success = Color(0xFF2ECC9A);
  static const warning = Color(0xFFF5B547);
  static const danger = Color(0xFFFF5C7A);

  static const brandGradient = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [deepPurple, electricBlue],
  );

  static const bgGradientDark = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF14102A), bgDark],
  );

  static const bgGradientLight = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFECE6FB), bgLight],
  );
}

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: SawtiColors.deepPurple,
    brightness: b,
    primary: dark ? const Color(0xFF9D6BFF) : SawtiColors.deepPurple,
    secondary: SawtiColors.electricBlue,
    surface: dark ? SawtiColors.surfaceDark : Colors.white,
    error: SawtiColors.danger,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: b);
  final onBg = dark ? Colors.white : const Color(0xFF14142B);
  final muted = dark ? SawtiColors.textMuted : const Color(0xFF5E6175);
  return base.copyWith(
    scaffoldBackgroundColor: dark ? SawtiColors.bgDark : SawtiColors.bgLight,
    textTheme: base.textTheme.apply(bodyColor: onBg, displayColor: onBg).copyWith(
          bodySmall: base.textTheme.bodySmall?.copyWith(color: muted),
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      foregroundColor: onBg,
      titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: onBg),
    ),
    cardTheme: CardThemeData(
      color: dark ? SawtiColors.surfaceDark : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? SawtiColors.surfaceDark2 : const Color(0xFFF0EEF8),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: SawtiColors.electricBlue, width: 1.4),
      ),
      hintStyle: TextStyle(color: muted),
      labelStyle: TextStyle(color: muted),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: SawtiColors.electricBlue,
      thumbColor: Colors.white,
      inactiveTrackColor: dark ? Colors.white24 : Colors.black12,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}

extension ThemeX on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get muted => isDark ? SawtiColors.textMuted : const Color(0xFF5E6175);
  Color get cardColor => isDark ? SawtiColors.surfaceDark : Colors.white;
}
