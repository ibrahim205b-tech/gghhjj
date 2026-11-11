String _two(int v) => v.toString().padLeft(2, '0');

/// Business date in local time formatted as YYYY-MM-DD.
String ymd(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// Billing period YYYY-MM.
String periodOf(DateTime d) => '${d.year}-${_two(d.month)}';

/// ISO timestamp (local, second precision) used for created_at columns.
String isoTs(DateTime d) => d.toIso8601String();

DateTime parseYmd(String s) => DateTime.parse(s);

/// First and last day (inclusive, YYYY-MM-DD) of a period string YYYY-MM.
(String, String) periodRange(String period) {
  final y = int.parse(period.substring(0, 4));
  final m = int.parse(period.substring(5, 7));
  final first = DateTime(y, m, 1);
  final last = DateTime(y, m + 1, 0);
  return (ymd(first), ymd(last));
}

String previousPeriod(String period) {
  final y = int.parse(period.substring(0, 4));
  final m = int.parse(period.substring(5, 7));
  return periodOf(DateTime(y, m - 1, 1));
}

String nextPeriod(String period) {
  final y = int.parse(period.substring(0, 4));
  final m = int.parse(period.substring(5, 7));
  return periodOf(DateTime(y, m + 1, 1));
}

/// Inclusive date range helper.
class DateRange {
  final String from;
  final String to;
  const DateRange(this.from, this.to);

  factory DateRange.day(DateTime d) => DateRange(ymd(d), ymd(d));
  factory DateRange.month(DateTime d) {
    final r = periodRange(periodOf(d));
    return DateRange(r.$1, r.$2);
  }
  factory DateRange.year(DateTime d) => DateRange('${d.year}-01-01', '${d.year}-12-31');
  factory DateRange.lastDays(DateTime d, int days) =>
      DateRange(ymd(d.subtract(Duration(days: days - 1))), ymd(d));

  @override
  String toString() => '$from..$to';
}
