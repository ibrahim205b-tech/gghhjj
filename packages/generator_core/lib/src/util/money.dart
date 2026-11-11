/// Formats an integer dinar amount with thousands separators: 1250000 -> 1,250,000
String formatMoney(int amount, {bool withCurrency = true}) {
  final neg = amount < 0;
  final s = amount.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  final v = '${neg ? '-' : ''}$buf';
  return withCurrency ? '$v د.ع' : v;
}

/// Millilitres -> litres string with up to 1 decimal.
String formatLiters(int ml) {
  final l = ml / 1000.0;
  final str = l == l.roundToDouble() ? l.toStringAsFixed(0) : l.toStringAsFixed(1);
  return '$str لتر';
}

int litersToMl(num liters) => (liters * 1000).round();

/// Rounded integer division used for money (half away from zero).
int divRound(int a, int b) {
  if (b == 0) return 0;
  final q = a / b;
  return q.isNegative ? -((-q) + 0.5).floor() : (q + 0.5).floor();
}
