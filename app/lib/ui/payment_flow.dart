import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:generator_core/generator_core.dart';
import 'package:printing/printing.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../app_state.dart';
import '../services/export_service.dart';
import '../services/pdf_service.dart';
import '../services/printer_service.dart';
import '../theme.dart';
import 'common.dart';

class PrintPrefs {
  final PrinterTarget target;
  final PaperSize paper;
  const PrintPrefs(this.target, this.paper);

  static Future<PrintPrefs> load(AppState app) async {
    final r = await app.os.ctx.db.query('settings', where: "key IN ('print.target','print.paper')");
    final m = {for (final x in r) x['key']: x['value'] as String?};
    final paper = PaperSize.values.firstWhere((p) => p.name == m['print.paper'], orElse: () => PaperSize.roll80);
    return PrintPrefs(PrinterService.fromSetting(m['print.target']), paper);
  }

  static Future<void> save(AppState app, {String? target, PaperSize? paper}) async {
    final now = app.os.ctx.nowIso;
    if (target != null) {
      await app.os.ctx.db.insert('settings', {
        'key': 'print.target',
        'value': target,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    if (paper != null) {
      await app.os.ctx.db.insert('settings', {
        'key': 'print.paper',
        'value': paper.name,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }
}

/// Prints with the configured printer; falls back to the share sheet.
Future<void> printOrShare(BuildContext context, Future<List<int>> Function(PaperSize) build, String name) async {
  final app = AppScope.read(context);
  final prefs = await PrintPrefs.load(app);
  if (!context.mounted) return;
  await guard(context, () async {
    final pdf = await build(prefs.paper);
    await prefs.target.printPdf(pdf, prefs.paper, name: name);
  });
}

Future<void> sharePdf(
  BuildContext context,
  Future<List<int>> Function(PaperSize) build,
  String fileName, {
  PaperSize paper = PaperSize.a4,
  String? text,
}) async {
  await guard(context, () async {
    final f = await ExportService.bytes(fileName, await build(paper));
    await ExportService.share(f, text: text);
  });
}

/// Opens the payment dialog. A request id is created when the dialog opens,
/// so a double tap or retry can never record the payment twice.
Future<void> showPayDialog(BuildContext context, Map<String, Object?> subscriber, {VoidCallback? onDone}) async {
  final app = AppScope.read(context);
  final requestId = newId();
  final balance = await app.os.subscribers.balance(subscriber['id'] as String);
  if (!context.mounted) return;
  final v = await showFormDialog(
    context,
    title: 'تسجيل دفعة — ${subscriber['full_name']}',
    note: 'المبلغ المستحق حالياً: ${money(balance)}',
    submit: 'تسجيل وإصدار وصل',
    fields: [
      FieldSpec(
        'amount',
        'المبلغ المستلم',
        type: FieldType.money,
        required: true,
        initial: balance > 0 ? '$balance' : '',
        validator: (s) => (parseMoney(s) ?? 0) <= 0 ? 'أدخل مبلغاً صحيحاً' : null,
      ),
      const FieldSpec(
        'method',
        'طريقة الدفع',
        type: FieldType.dropdown,
        required: true,
        initial: PaymentMethod.cash,
        options: PaymentMethod.labels,
      ),
      const FieldSpec('notes', 'ملاحظات', type: FieldType.multiline),
    ],
  );
  if (v == null || !context.mounted) return;
  Map<String, Object?>? payment;
  final ok = await guard(context, () async {
    payment = await app.os.collection.recordPayment(
      subscriberId: subscriber['id'] as String,
      amount: parseMoney(v['amount'])!,
      requestId: requestId,
      method: v['method']!,
      notes: emptyToNull(v['notes']),
    );
  });
  if (!ok || payment == null || !context.mounted) return;
  onDone?.call();
  await Navigator.push(context, MaterialPageRoute(builder: (_) => ReceiptScreen(paymentId: payment!['id'] as String)));
}

String receiptText(Map<String, Object?> r) => [
  '${r['generator_name']}',
  r['reversal_of'] != null ? 'إشعار إلغاء دفعة' : 'وصل استلام',
  'رقم الوصل: ${r['receipt_no']}',
  'المشترك: ${r['full_name']} (رقم ${r['account_no']})',
  'المبلغ: ${money(r['amount'] as int)}',
  'الرصيد المتبقي: ${money(r['balance_after'] as int)}',
  'التاريخ: ${(r['paid_at'] as String).substring(0, 16).replaceFirst('T', ' ')}',
].join('\n');

class ReceiptScreen extends StatelessWidget {
  final String paymentId;
  const ReceiptScreen({super.key, required this.paymentId});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('الوصل')),
      body: Loader<Map<String, Object?>>(
        load: () => app.os.collection.receipt(paymentId),
        builder: (context, r, _) => Column(
          children: [
            Expanded(
              child: PdfPreview(
                build: (_) async => u8(await PdfService.receipt(r, PaperSize.roll80)),
                canChangePageFormat: false,
                canChangeOrientation: false,
                canDebug: false,
                allowPrinting: false,
                allowSharing: false,
                pdfFileName: 'receipt-${r['receipt_no']}.pdf',
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.print),
                      label: const Text('طباعة'),
                      onPressed: () =>
                          printOrShare(context, (p) => PdfService.receipt(r, p), 'receipt-${r['receipt_no']}'),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.share),
                      label: const Text('مشاركة PDF'),
                      onPressed: () => sharePdf(
                        context,
                        (p) => PdfService.receipt(r, PaperSize.roll80),
                        'receipt-${r['receipt_no']}.pdf',
                      ),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.chat, color: Brand.success),
                      label: const Text('نص عبر واتساب'),
                      onPressed: () => ExportService.shareText(receiptText(r)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Uint8List u8(List<int> l) => l is Uint8List ? l : Uint8List.fromList(l);
