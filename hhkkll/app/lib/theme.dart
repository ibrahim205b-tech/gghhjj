import 'package:flutter/material.dart';
import 'package:hhkkll_core/hhkkll_core.dart';

/// Dark premium sports palette: charcoal surfaces lit by stadium-style
/// accents. Every colour used in the app comes from here.
abstract final class C {
  static const bg = Color(0xFF06070A);
  static const bg2 = Color(0xFF0B0D12);
  static const surface = Color(0xFF12151C);
  static const surface2 = Color(0xFF1A1E28);
  static const line = Color(0xFF262B38);
  static const text = Color(0xFFF3F5FA);
  static const muted = Color(0xFF8D94A8);
  static const gold = Color(0xFFF7C948);
  static const goldDeep = Color(0xFFC8921A);
  static const pitch = Color(0xFF22E58A);
  static const red = Color(0xFFFF3B55);
  static const cyan = Color(0xFF2EC8FF);
  static const violet = Color(0xFF9B6BFF);
  static const orange = Color(0xFFFF8A2B);

  /// Accent per section.
  static Color of(Category c) => switch (c) {
        Category.auction => gold,
        Category.whatDoYouKnow => cyan,
        Category.buzzer => red,
        Category.whoAmI => violet,
      };

  static IconData icon(Category c) => switch (c) {
        Category.auction => Icons.gavel_rounded,
        Category.whatDoYouKnow => Icons.psychology_alt_rounded,
        Category.buzzer => Icons.notifications_active_rounded,
        Category.whoAmI => Icons.person_search_rounded,
      };

  /// Distinct colours for player buzzers / avatars.
  static const players = [
    Color(0xFF2EC8FF),
    Color(0xFFFF3B55),
    Color(0xFF22E58A),
    Color(0xFFF7C948),
    Color(0xFF9B6BFF),
    Color(0xFFFF8A2B),
    Color(0xFFFF5FD2),
    Color(0xFF5BF0E6),
  ];
  static Color player(int i) => players[i % players.length];
}

ThemeData buildTheme() {
  const kufi = 'Kufi';
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: kufi,
    // Noto Kufi Arabic has no Latin punctuation (+ : . ( ) /): fall back to
    // Noto Sans for those glyphs.
    fontFamilyFallback: const ['Display'],
    scaffoldBackgroundColor: C.bg,
    colorScheme: const ColorScheme.dark(
      primary: C.gold,
      onPrimary: Colors.black,
      secondary: C.pitch,
      surface: C.surface,
      onSurface: C.text,
      error: C.red,
    ),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: kufi,
      fontFamilyFallback: const ['Display'],
      bodyColor: C.text,
      displayColor: C.text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: kufi,
        fontFamilyFallback: ['Display'],
        fontWeight: FontWeight.w700,
        fontSize: 19,
        color: C.text,
      ),
    ),
    cardTheme: CardThemeData(
      color: C.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: C.line),
      ),
    ),
    dividerTheme: const DividerThemeData(color: C.line),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.surface2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: C.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: C.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: C.gold, width: 1.6),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: C.surface2,
      contentTextStyle: TextStyle(fontFamily: kufi, fontFamilyFallback: ['Display'], color: C.text),
      behavior: SnackBarBehavior.floating,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? C.gold : C.muted),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? C.goldDeep.withValues(alpha: .5) : C.surface2),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: C.gold,
      thumbColor: C.gold,
      inactiveTrackColor: C.line,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: C.bg2,
      showDragHandle: true,
    ),
    dialogTheme: const DialogThemeData(backgroundColor: C.surface),
  );
}
