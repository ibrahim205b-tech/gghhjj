import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sawti_ai/main.dart';
import 'package:sawti_ai/models.dart';
import 'package:sawti_ai/services/api.dart';
import 'package:sawti_ai/services/storage.dart';
import 'package:sawti_ai/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

Future<AppState> buildState(Directory root, {bool configured = false, List<LibraryItem> items = const []}) async {
  final dirs = AppDirs(root: root);
  if (items.isNotEmpty) await LibraryRepository(dirs).save(items);
  final secrets = MemorySecretStore();
  if (configured) {
    SharedPreferences.setMockInitialValues({'server_url': 'https://example-sawtiai.hf.space'});
    await secrets.write('sawti_api_key', 'good-key');
  }
  return AppState(
    settingsStore: SettingsStore(secrets: secrets),
    voiceRepo: VoiceRepository(dirs),
    libraryRepo: LibraryRepository(dirs),
    dirs: dirs,
    api: ApiClient(baseUrl: '', apiKey: '', dio: Dio()..httpClientAdapter = FakeServer()),
  );
}

/// Lets real file I/O started by the UI finish, pumping frames in between.
Future<void> settleIo(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await t.pump();
  }
  await t.pumpAndSettle();
}

Future<void> back(WidgetTester t) async {
  t.state<NavigatorState>(find.byType(Navigator).first).pop();
  await t.pumpAndSettle();
}

Finder get listScroll => find.descendant(of: find.byType(ListView).last, matching: find.byType(Scrollable)).first;

void phone(WidgetTester t) {
  t.view.physicalSize = const Size(1080, 2340);
  t.view.devicePixelRatio = 2.75;
  addTearDown(t.view.reset);
}

Future<void> boot(WidgetTester t, AppState s) async {
  if (t.view.physicalSize.width < 1500) phone(t);
  await t.runAsync(s.init); // real file I/O outside the fake clock
  await t.pumpWidget(SawtiApp(state: s, splashDuration: const Duration(milliseconds: 50)));
  await t.pump(const Duration(milliseconds: 100));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'صوتي AI', packageName: 'com.sawtiai.app', version: '1.0.0', buildNumber: '1', buildSignature: '');
  });

  testWidgets('splash shows brand then opens home (RTL Arabic)', (t) async {
    final root = await t.runAsync(tempDir);
    final s = await t.runAsync(() => buildState(root!));
    await t.runAsync(s!.init);
    await t.pumpWidget(SawtiApp(state: s, splashDuration: const Duration(milliseconds: 50)));
    expect(find.text('صوتي AI'), findsOneWidget);
    expect(find.text('حوّل كلماتك إلى صوتك'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 100));
    await t.pumpAndSettle();
    expect(find.text('صوتك... بكلماتك'), findsOneWidget);
    expect(find.text('الصوت الخاص بي'), findsOneWidget);
    expect(find.text('الخادم غير مربوط'), findsOneWidget);
    final dir = Directionality.of(t.element(find.text('الصوت الخاص بي')));
    expect(dir, TextDirection.rtl);
  });

  testWidgets('home buttons navigate to library, settings and generate', (t) async {
    final root = await t.runAsync(tempDir);
    final s = await t.runAsync(() => buildState(root!));
    await boot(t, s!);

    await t.tap(find.text('مكتبتي الصوتية'));
    await t.pumpAndSettle();
    expect(find.text('المكتبة فارغة'), findsOneWidget);
    await back(t);

    await t.tap(find.text('توليد كلام'));
    await t.pumpAndSettle();
    expect(find.text('توليد الكلام'), findsOneWidget);
    expect(find.text('ولّد بصوتي'), findsOneWidget);
    await back(t);

    await t.tap(find.byTooltip('الإعدادات'));
    await t.pumpAndSettle();
    expect(find.text('حالة الخادم'), findsOneWidget);
    await t.scrollUntilVisible(find.text('سياسة الخصوصية'), 300, scrollable: listScroll);
    await t.ensureVisible(find.text('سياسة الخصوصية'));
    await t.pumpAndSettle();
    await t.tap(find.text('سياسة الخصوصية'));
    await t.pumpAndSettle();
    expect(find.text('تطبيق شخصي'), findsOneWidget);
  });

  testWidgets('generate validates empty text and missing voice', (t) async {
    final root = await t.runAsync(tempDir);
    final s = await t.runAsync(() => buildState(root!, configured: true));
    await boot(t, s!);
    await t.tap(find.text('توليد كلام'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byKey(const Key('generate_button')), 200, scrollable: listScroll);
    await t.tap(find.byKey(const Key('generate_button')));
    await t.pumpAndSettle();
    expect(find.text('اكتب النص الذي تريد تحويله إلى كلام.'), findsOneWidget);
    await t.scrollUntilVisible(find.byKey(const Key('tts_text_field')), -200, scrollable: listScroll);
    await t.enterText(find.byKey(const Key('tts_text_field')), 'مرحباً بك');
    await t.pump();
    expect(find.textContaining('9 / 2000'), findsOneWidget);
    await t.scrollUntilVisible(find.byKey(const Key('generate_button')), 200, scrollable: listScroll);
    await t.ensureVisible(find.byKey(const Key('generate_button')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('generate_button')), warnIfMissed: true);
    await t.pumpAndSettle();
    expect(find.text('اختر صوتاً مستنسخاً أولاً.', skipOffstage: false), findsOneWidget);
  });

  testWidgets('settings: server sheet rejects plain http', (t) async {
    final root = await t.runAsync(tempDir);
    final s = await t.runAsync(() => buildState(root!));
    await boot(t, s!);
    await t.tap(find.byTooltip('الإعدادات'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('server_settings_tile')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('server_url_field')), 'http://example.com');
    await t.tap(find.byKey(const Key('save_server_button')));
    await t.pumpAndSettle();
    expect(find.text('يجب أن يبدأ العنوان بـ https:// لحماية بياناتك'), findsOneWidget);
  });

  testWidgets('settings: theme switch to light', (t) async {
    final root = await t.runAsync(tempDir);
    final s = await t.runAsync(() => buildState(root!));
    await boot(t, s!);
    await t.tap(find.byTooltip('الإعدادات'));
    await t.pumpAndSettle();
    await t.tap(find.text('فاتح'));
    await t.pumpAndSettle();
    expect(s.settings.themeMode, ThemeMode.light);
    final ctx = t.element(find.text('حالة الخادم'));
    expect(Theme.of(ctx).brightness, Brightness.light);
  });

  testWidgets('library lists saved items after restart and deletes them', (t) async {
    final root = await t.runAsync(tempDir);
    final path = '${root!.path}/library/x1.wav';
    await t.runAsync(() async {
      await Directory('${root.path}/library').create(recursive: true);
      await File(path).writeAsBytes(FakeServer.wavBytes());
    });
    final item = LibraryItem(
        id: 'x1', title: 'تسجيل تجريبي', text: 'نص', voiceName: 'صوتي', createdAt: DateTime(2026, 11, 22),
        durationMs: 3000, sizeBytes: 32044, filePath: path);
    final s = await t.runAsync(() => buildState(root, items: [item]));
    await boot(t, s!);
    await t.scrollUntilVisible(find.text('تسجيل تجريبي'), 200, scrollable: listScroll);
    expect(find.text('تسجيل تجريبي'), findsOneWidget); // recent files on home
    await t.scrollUntilVisible(find.text('مكتبتي الصوتية'), -200, scrollable: listScroll);
    await t.tap(find.text('مكتبتي الصوتية'));
    await t.pumpAndSettle();
    expect(find.text('تسجيل تجريبي'), findsOneWidget);
    expect(find.textContaining('22 نوفمبر 2026'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('delete_x1')));
    await t.pumpAndSettle();
    await t.tap(find.text('حذف').last);
    await settleIo(t);
    expect(find.text('المكتبة فارغة'), findsOneWidget);
    expect(File(path).existsSync(), isFalse);
  });

  testWidgets('tablet width uses 4-column action grid without overflow', (t) async {
    t.view.physicalSize = const Size(1600, 2400);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final root = await t.runAsync(tempDir);
    final s = await t.runAsync(() => buildState(root!));
    await boot(t, s!);
    expect(find.text('إنشاء صوتي'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
