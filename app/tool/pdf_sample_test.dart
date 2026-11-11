import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:generator_os/services/pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('write sample receipt', () async {
    final r = {
      'id': 'p1',
      'receipt_no': 'K7QX2M-000042',
      'generator_name': 'مولدة الحي التجريبية',
      'paid_at': '2026-11-11T10:30:00',
      'full_name': 'علي حسين كاظم',
      'account_no': '12',
      'amps': 5,
      'collector_name': 'أبو محمد',
      'amount': 15000,
      'balance_after': 2500,
      'reversal_of': null,
    };
    File(Platform.environment['OUT']!).writeAsBytesSync(await PdfService.receipt(r, PaperSize.roll80));
    File('${Platform.environment['OUT']!}.table.pdf').writeAsBytesSync(
      await PdfService.table(
        'تقرير الجباية',
        'تقرير الجباية 2026-11-01..2026-11-30',
        ['التاريخ', 'الوصل', 'المشترك', 'المبلغ'],
        [
          ['2026-11-11', 'K7QX2M-000042', 'تسديد اشتراك — علي حسين (وصل K7QX2M-000042)', '15,000'],
          ['2026-11-12', 'K7QX2M-000043', 'زينب جاسم', '7,500'],
        ],
      ),
    );
  });
}
