import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:generator_core/generator_core.dart';
import 'package:generator_os/app_state.dart';
import 'package:generator_os/main.dart';
import 'package:generator_os/services/export_service.dart';
import 'package:generator_os/services/pdf_service.dart';
import 'package:generator_os/services/printer_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'dart:convert';
import 'dart:typed_data';

/// Builds an engine on an in-memory database with test data only.
Future<(GeneratorOS, String)> engine({bool collector = false}) async {
  sqfliteFfiInit();
  final db = await openGeneratorDatabase(databaseFactoryFfi, inMemoryDatabasePath);
  final os = GeneratorOS(db, deviceId: 'widget-test-device', hasher: const PasswordHasher(iterations: 1000));
  await os.auth.createOwner(fullName: 'مالك تجريبي', username: 'owner', password: 'Owner12345');
  await os.auth.login('owner', 'Owner12345');
  final g = await os.network.createGenerator(name: 'مولدة الحي التجريبية', defaultAmpPrice: 3000);
  final area = await os.network.createArea(g, 'حي تجريبي');
  final s = await os.subscribers.create(g, {
    'full_name': 'مشترك للاختبار',
    'amps': 5,
    'amp_price': 3000,
    'area_id': area,
  });
  await os.billing.generateMonth(g, periodOf(DateTime.now()));
  await os.collection.recordPayment(subscriberId: s, amount: 5000);
  if (collector) {
    final uid = await os.auth.createUser(
      fullName: 'جابي تجريبي',
      username: 'col',
      password: 'Collect123',
      roleId: roleCollector,
      generatorIds: [g],
    );
    final c = await os.collection.createCollector(fullName: 'جابي تجريبي', userId: uid);
    await os.collection.assign(c, g, areaId: area);
    await os.auth.logout();
    await os.auth.login('col', 'Collect123');
  }
  return (os, g);
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<AppState> launch(WidgetTester tester, Size size, {bool collector = false}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final (os, _) = (await tester.runAsync(() => engine(collector: collector)))!;
  final state = AppState.forTest(os);
  await tester.runAsync(state.afterLogin);
  await tester.pumpWidget(GeneratorOsApp(state: state));
  await settle(tester);
  return state;
}

void main() {
  testWidgets('phone: dashboard renders real figures right-to-left', (tester) async {
    await launch(tester, const Size(400, 860));
    expect(find.text('لوحة التحكم'), findsWidgets);
    expect(find.text('مقبوضات اليوم'), findsOneWidget);
    expect(find.text('5,000 د.ع'), findsWidgets);
    expect(find.byType(NavigationBar), findsOneWidget);
    final dir = Directionality.of(tester.element(find.text('مقبوضات اليوم')));
    expect(dir, TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet landscape: navigation rail with all owner modules', (tester) async {
    await launch(tester, const Size(1280, 800));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('المستخدمون والصلاحيات'), findsOneWidget);
    expect(find.text('التقارير'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('collector sees collection only, no financial modules', (tester) async {
    await launch(tester, const Size(400, 860), collector: true);
    expect(find.text('الجباية'), findsWidgets);
    expect(find.text('تحصيلي اليوم'), findsOneWidget);
    expect(find.text('مشترك للاختبار'), findsOneWidget);
    expect(find.text('لوحة التحكم'), findsNothing);
    expect(find.text('الصندوق'), findsNothing);
    expect(find.text('التقارير'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every module screen opens without errors on a tablet', (tester) async {
    final state = await launch(tester, const Size(1280, 900));
    final titles = [
      'الجباية',
      'المشتركون',
      'الفواتير',
      'الجباة',
      'الصندوق',
      'المصروفات والمجهزون',
      'الوقود',
      'التشغيل والصيانة',
      'الكابينات والأحمال',
      'الشكاوى',
      'التقارير',
      'المساعد الذكي',
      'التنبيهات',
      'المستخدمون والصلاحيات',
      'الإعدادات',
    ];
    for (final t in titles) {
      await tester.tap(find.descendant(of: find.byType(NavigationRail), matching: find.text(t)));
      await settle(tester);
      expect(tester.takeException(), isNull, reason: t);
      expect(find.text('تعذر تحميل البيانات'), findsNothing, reason: t);
    }
    expect(state.session, isNotNull);
  });

  test('Arabic receipt and report PDFs are generated', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final r = {
      'id': 'p1',
      'receipt_no': 'ABCDEF-000001',
      'generator_name': 'مولدة الحي',
      'paid_at': '2026-03-01T10:00:00',
      'full_name': 'علي حسين',
      'account_no': '12',
      'amps': 5,
      'collector_name': 'أبو محمد',
      'amount': 15000,
      'balance_after': 0,
      'reversal_of': null,
    };
    for (final paper in PaperSize.values) {
      final pdf = await PdfService.receipt(r, paper);
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
      expect(pdf.length, greaterThan(1500));
    }
    final t = await PdfService.table(
      'تقرير',
      'فترة',
      ['أ', 'ب'],
      [
        ['١', '٢'],
      ],
    );
    expect(String.fromCharCodes(t.take(5)), '%PDF-');
  });

  test('Excel export contains Arabic headers and values in an RTL sheet', () {
    final bytes = ExportService.xlsxBytes(
      ['الاسم', 'المبلغ'],
      [
        ['علي', 15000],
      ],
    );
    final zip = ZipDecoder().decodeBytes(bytes);
    final names = zip.files.map((f) => f.name).toList();
    expect(names, contains('xl/workbook.xml'));
    final shared = zip.files.firstWhere((f) => f.name == 'xl/sharedStrings.xml');
    final xml = utf8.decode(shared.content as List<int>);
    expect(xml, contains('الاسم'));
    expect(xml, contains('علي'));
    final sheet = utf8.decode(
      zip.files.firstWhere((f) => f.name.startsWith('xl/worksheets/sheet')).content as List<int>,
    );
    expect(sheet, contains('rightToLeft="1"'));
  });

  test('ESC/POS raster encodes black pixels into GS v 0 bitmap', () {
    // 8×1 image: first pixel black, rest white.
    final rgba = Uint8List(8 * 4);
    for (var i = 0; i < 8; i++) {
      final v = i == 0 ? 0 : 255;
      rgba.setAll(i * 4, [v, v, v, 255]);
    }
    final cmd = NetworkEscPosPrinter.rasterCommand(rgba, 8, 1);
    expect(cmd.sublist(0, 4), [0x1D, 0x76, 0x30, 0x00]);
    expect(cmd[4], 1); // bytes per row
    expect(cmd[6], 1); // height
    expect(cmd.last, 0x80);
  });
}
