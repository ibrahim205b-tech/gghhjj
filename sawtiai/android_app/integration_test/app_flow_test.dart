// End-to-end test on a real Android device/emulator against a REAL backend
// running the real voice engine. Nothing is mocked here.
//
// flutter test integration_test/app_flow_test.dart \
//   --dart-define=SAWTI_TEST_SERVER_URL=http://10.0.2.2:7860 \
//   --dart-define=SAWTI_TEST_API_KEY=... \
//   --dart-define=SAWTI_TEST_SAMPLE_B64=<base64 of an m4a/wav sample> \
//   --dart-define=SAWTI_TEST_TRANSCRIPT="..."
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sawti_ai/main.dart';
import 'package:sawti_ai/models.dart';
import 'package:sawti_ai/screens/create_voice.dart';
import 'package:sawti_ai/services/api.dart';
import 'package:sawti_ai/services/storage.dart';
import 'package:sawti_ai/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

const serverUrl = String.fromEnvironment('SAWTI_TEST_SERVER_URL');
const apiKey = String.fromEnvironment('SAWTI_TEST_API_KEY');
const sampleB64 = String.fromEnvironment('SAWTI_TEST_SAMPLE_B64');
const sampleExt = String.fromEnvironment('SAWTI_TEST_SAMPLE_EXT', defaultValue: 'm4a');
const transcript = String.fromEnvironment('SAWTI_TEST_TRANSCRIPT');

Future<void> pumpUntil(WidgetTester t, Finder f, {Duration timeout = const Duration(minutes: 2), String? what}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 500));
    if (f.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out after $timeout waiting for ${what ?? f}');
}

Future<void> waitFor(WidgetTester t, bool Function() cond, {Duration timeout = const Duration(minutes: 2), String what = 'condition'}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 500));
    if (cond()) return;
  }
  throw TestFailure('Timed out waiting for $what');
}

Future<void> tapVisible(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump(const Duration(milliseconds: 300));
  await t.tap(f);
  await t.pump(const Duration(milliseconds: 300));
}

NavigatorState nav(WidgetTester t) => t.state<NavigatorState>(find.byType(Navigator).first);

Future<AppState> startApp(WidgetTester t) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('server_url', serverUrl);
  await SecureSecretStore().write('sawti_api_key', apiKey);
  final state = createAppState();
  await t.pumpWidget(SawtiApp(state: state, splashDuration: const Duration(milliseconds: 600)));
  await pumpUntil(t, find.text('الصوت الخاص بي'), what: 'home screen');
  return state;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final configured = serverUrl.isNotEmpty && apiKey.isNotEmpty && sampleB64.isNotEmpty;

  testWidgets('microphone: record, stop, re-record, cancel', (t) async {
    final state = await startApp(t);
    await tapVisible(t, find.text('إنشاء صوتي'));
    await pumpUntil(t, find.text('بدء التسجيل'));
    await tapVisible(t, find.text('بدء التسجيل'));
    await pumpUntil(t, find.text('إيقاف التسجيل'), what: 'recording to start (mic permission must be granted)');
    await t.pump(const Duration(seconds: 3));
    await tapVisible(t, find.text('إيقاف التسجيل'));
    await pumpUntil(t, find.text('استمع للعينة'), what: 'recorded sample');
    final timer = t.widget<Text>(find.byKey(const Key('rec_timer'))).data!;
    expect(timer, isNot('00:00'), reason: 'recording produced audio');
    await tapVisible(t, find.text('إعادة التسجيل'));
    await pumpUntil(t, find.text('بدء التسجيل'));
    await tapVisible(t, find.text('بدء التسجيل'));
    await pumpUntil(t, find.text('إلغاء'));
    await t.pump(const Duration(seconds: 1));
    await tapVisible(t, find.text('إلغاء'));
    await pumpUntil(t, find.text('بدء التسجيل'), what: 'cancel to reset');
    expect(state.voices, isEmpty, reason: 'cancelled/re-recorded samples are not saved as voices');
  });

  testWidgets('full flow against the real server: clone, generate, play, persist, delete', (t) async {
    if (!configured) {
      markTestSkipped('SAWTI_TEST_* defines not provided');
      return;
    }
    final state = await startApp(t);

    // 1) Server connection + engine ready (cold start may take minutes).
    await waitFor(t, () => state.server.ready, timeout: const Duration(minutes: 15), what: 'server engine ready');
    expect(find.text('الخادم متصل وجاهز'), findsOneWidget);

    // 2) Import a sample through the same code path the file picker uses.
    final tmp = await state.tempPath(sampleExt);
    await File(tmp).writeAsBytes(base64Decode(sampleB64));
    nav(t).push(MaterialPageRoute(builder: (_) => CreateVoiceScreen(initialSamplePath: tmp)));
    await pumpUntil(t, find.byKey(const Key('process_button')), what: 'imported sample');
    await t.enterText(find.byKey(const Key('transcript_field')), transcript);
    await tapVisible(t, find.byKey(const Key('process_button')));

    // 3) Processing screen: success only after the server prepared the voice.
    await pumpUntil(t, find.text('تم تجهيز نسختك الصوتية'), timeout: const Duration(minutes: 20), what: 'voice prepared');
    final voice = state.activeVoice!;
    expect(voice.status, VoiceStatus.ready);
    expect(voice.serverVoiceId, isNotNull);
    final st = await state.api.voiceStatus(voice.serverVoiceId!);
    expect(st['status'], 'ready');

    // 4) Generate speech from Arabic text via the UI.
    await tapVisible(t, find.byKey(const Key('try_voice_button')));
    await pumpUntil(t, find.byKey(const Key('tts_text_field')));
    await t.enterText(find.byKey(const Key('tts_text_field')), 'أهلاً وسهلاً، شلونكم؟ اليوم راح نجرب نظام استنساخ الصوت.');
    await tapVisible(t, find.byKey(const Key('generate_button')));
    await pumpUntil(t, find.text('مشغل الصوت'), timeout: const Duration(minutes: 25), what: 'player after generation');

    // 5) A real audio file exists locally and plays.
    final item = state.library.first;
    final f = File(item.filePath);
    expect(f.existsSync(), isTrue);
    expect(f.lengthSync(), greaterThan(10000));
    expect(String.fromCharCodes(f.readAsBytesSync().sublist(0, 4)), 'RIFF');
    expect(item.durationMs, greaterThan(1000));
    await t.pump(const Duration(seconds: 3)); // autoPlay
    final pos = t.widget<Text>(find.byKey(const Key('position_text'))).data!;
    expect(pos, isNot('00:00'), reason: 'player advanced while playing');
    await tapVisible(t, find.byKey(const Key('play_button'))); // pause

    // 6) Library shows it; a fresh app state (app reopened) still has it.
    nav(t).popUntil((r) => r.isFirst);
    await t.pump(const Duration(seconds: 1));
    await tapVisible(t, find.text('مكتبتي الصوتية'));
    await pumpUntil(t, find.byKey(ValueKey('lib_${item.id}')));
    final reopened = await LibraryRepository(AppDirs()).load();
    expect(reopened.map((i) => i.id), contains(item.id));
    final reopenedVoices = await VoiceRepository(AppDirs()).load();
    expect(reopenedVoices.map((v) => v.id), contains(voice.id));

    // 7) Delete the file from the library.
    await tapVisible(t, find.byKey(ValueKey('delete_${item.id}')));
    await pumpUntil(t, find.text('حذف').last);
    await t.tap(find.text('حذف').last);
    await pumpUntil(t, find.text('المكتبة فارغة'));
    expect(f.existsSync(), isFalse);

    // 8) Delete the voice from the server and the device.
    final serverVoiceId = voice.serverVoiceId!;
    await state.deleteVoice(voice);
    await expectLater(state.api.voiceStatus(serverVoiceId), throwsA(isA<ApiException>()));
    expect(state.voices, isEmpty);
  });
}
