import 'package:flutter/material.dart';

/// ENJAZ design tokens - dark glassmorphism productivity dashboard.
class EnjazColors {
  // Backgrounds
  static const navy = Color(0xFF0A1628);
  static const navyDeep = Color(0xFF060E1C);
  static const navySurface = Color(0xFF13233B);

  // Ambient lights
  static const blueGlow = Color(0xFF1C6DD0);
  static const cyanGlow = Color(0xFF22B8CF);
  static const warmGlow = Color(0xFFB4474F);

  // Brand
  static const primary = Color(0xFF4F8CFF);
  static const cyan = Color(0xFF38D6E8);
  static const violet = Color(0xFF6C63FF);

  // Semantic
  static const success = Color(0xFF7BE07A);
  static const successDeep = Color(0xFF3FBF6B);
  static const warning = Color(0xFFFFB547);
  static const danger = Color(0xFFFF5A6E);
  static const streak = Color(0xFFFF8A3D);

  // Text
  static const textPrimary = Color(0xFFF2F6FF);
  static const textSecondary = Color(0xFF9AA8C3);

  // Glass
  static Color glassFill(bool dark) => dark ? Colors.white.withValues(alpha: 0.07) : Colors.white.withValues(alpha: 0.72);
  static Color glassBorder(bool dark) => dark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFF0A1628).withValues(alpha: 0.08);

  static const progressGradient = LinearGradient(colors: [Color(0xFFC6F57E), Color(0xFF6FD66B)]);
  static const planGradient = LinearGradient(
    begin: Alignment.centerRight, end: Alignment.centerLeft,
    colors: [Color(0xFF8ED9A6), Color(0xFF3B8FB8), Color(0xFF2C5DA0)]);
  static const studyGradient = LinearGradient(
    begin: Alignment.centerRight, end: Alignment.centerLeft,
    colors: [Color(0xFFFF6A5A), Color(0xFFE0457B), Color(0xFFB4306C)]);
  static const brandGradient = LinearGradient(
    begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [cyan, primary, violet]);
  static const violetChip = LinearGradient(colors: [Color(0xFF6C63FF), Color(0xFF4F5BEA)]);
}

class EnjazRadii {
  static const card = 24.0;
  static const tile = 20.0;
  static const button = 28.0;
  static const chip = 14.0;
}

ThemeData buildEnjazTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: EnjazColors.primary,
    brightness: brightness,
    primary: EnjazColors.primary,
    secondary: EnjazColors.cyan,
    error: EnjazColors.danger,
    surface: dark ? EnjazColors.navySurface : const Color(0xFFF4F7FC),
  );
  final text = dark ? EnjazColors.textPrimary : const Color(0xFF0E1B30);
  final muted = dark ? EnjazColors.textSecondary : const Color(0xFF5A6B85);
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: brightness);
  return base.copyWith(
    scaffoldBackgroundColor: dark ? EnjazColors.navy : const Color(0xFFEFF3FA),
    textTheme: base.textTheme.apply(bodyColor: text, displayColor: text).copyWith(
          bodySmall: base.textTheme.bodySmall?.copyWith(color: muted),
          labelSmall: base.textTheme.labelSmall?.copyWith(color: muted),
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      foregroundColor: text,
      titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: text),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: EnjazColors.glassBorder(dark))),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: EnjazColors.cyan, width: 1.4)),
      labelStyle: TextStyle(color: muted),
      hintStyle: TextStyle(color: muted),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? EnjazColors.navySurface : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      showDragHandle: true,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? EnjazColors.navySurface : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(EnjazRadii.card)),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: dark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
      selectedColor: EnjazColors.primary.withValues(alpha: 0.35),
      side: BorderSide(color: EnjazColors.glassBorder(dark)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(EnjazRadii.chip)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? EnjazColors.navyDeep.withValues(alpha: 0.92) : Colors.white,
      indicatorColor: EnjazColors.primary.withValues(alpha: 0.25),
      labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11.5, color: muted, fontWeight: FontWeight.w600)),
      height: 68,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}

extension EnjazContext on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get mutedText => isDark ? EnjazColors.textSecondary : const Color(0xFF5A6B85);
}
