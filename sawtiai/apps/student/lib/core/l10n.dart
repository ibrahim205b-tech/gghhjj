import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';

export '../l10n/app_localizations.dart';

extension L10nX on BuildContext {
  L10n get l10n => L10n.of(this);
}

/// Formats minutes as "2س 15د" (or "45 د").
String formatMinutes(L10n l, int minutes) {
  if (minutes < 60) return l.minutesShort(minutes);
  return l.hoursMinutes(minutes ~/ 60, minutes % 60);
}

List<String> weekdayNames(L10n l) => l.weekdays.split(',');


/// Iraqi month names (كانون الثاني ...), e.g. "الأحد 22 تشرين الثاني".
String formatDay(L10n l, DateTime d, {bool withWeekday = true, bool withYear = false}) {
  final wd = weekdayNames(l)[d.weekday - 1];
  final s = '${d.day} ${l.months.split(',')[d.month - 1]}${withYear ? ' ${d.year}' : ''}';
  return withWeekday ? '$wd $s' : s;
}

String formatBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
}
