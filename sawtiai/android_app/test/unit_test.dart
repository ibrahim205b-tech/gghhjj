import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sawti_ai/models.dart';
import 'package:sawti_ai/services/api.dart';
import 'package:sawti_ai/services/storage.dart';
import 'package:sawti_ai/state/app_state.dart';
import 'package:sawti_ai/utils/format.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

AppState makeState(Directory root, FakeServer server, {String key = 'good-key'}) {
  final dio = Dio()..httpClientAdapter = server;
  final dirs = AppDirs(root: root);
  final s = AppState(
    settingsStore: SettingsStore(secrets: MemorySecretStore()),
    voiceRepo: VoiceRepository(dirs),
    libraryRepo: LibraryRepository(dirs),
    dirs: dirs,
    api: ApiClient(baseUrl: '', apiKey: '', dio: dio),
    pollInterval: const Duration(milliseconds: 1),
  );
  return s;
}

Future<AppState> readyState(Directory root, FakeServer server) async {
  final s = makeState(root, server);
  await s.init();
  await s.updateSettings((x) {
    x.serverUrl = 'https://example-sawtiai.hf.space';
    x.apiKey = 'good-key';
  });
  return s;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('format', () {
    test('duration', () {
      expect(formatDuration(const Duration(seconds: 65)), '01:05');
      expect(formatDuration(const Duration(hours: 1, seconds: 5)), '1:00:05');
    });
    test('bytes', () {
      expect(formatBytes(500), '500 بايت');
      expect(formatBytes(2048), '2 ك.ب');
      expect(formatBytes(3 * 1024 * 1024), '3.0 م.ب');
    });
    test('title never cuts inside a word', () {
      final t = titleFromText('هذا نص طويل جداً يحتوي على كلمات كثيرة لاختبار العنوان المختصر للملف');
      expect(t.endsWith('…'), isTrue);
      expect('هذا نص طويل جداً يحتوي على كلمات كثيرة لاختبار العنوان المختصر للملف'.contains(t.replaceAll('…', '')), isTrue);
    });
  });

  group('server url validation', () {
    test('requires https except local test hosts', () {
      expect(AppState.validateServerUrl(''), isNotNull);
      expect(AppState.validateServerUrl('http://example.com'), isNotNull);
      expect(AppState.validateServerUrl('example.com'), isNotNull);
      expect(AppState.validateServerUrl('https://user-sawtiai.hf.space'), isNull);
      expect(AppState.validateServerUrl('http://10.0.2.2:7860'), isNull);
    });
  });

  group('api error mapping', () {
    test('json error detail', () {
      final e = mapDioError(DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.badResponse,
        response: Response(requestOptions: RequestOptions(), statusCode: 413, data: {
          'detail': {'code': 'text_too_long', 'message': 'النص طويل'}
        }),
      ));
      expect(e.code, 'text_too_long');
      expect(e.message, 'النص طويل');
    });
    test('sleeping free host returns html', () {
      final e = mapDioError(DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.badResponse,
        response: Response(requestOptions: RequestOptions(), statusCode: 503, data: '<html>Starting</html>'),
      ));
      expect(e.code, 'server_waking');
      expect(e.retryable, isTrue);
    });
    test('offline and timeout', () {
      expect(mapDioError(DioException(requestOptions: RequestOptions(), type: DioExceptionType.connectionError)).code, 'offline');
      expect(mapDioError(DioException(requestOptions: RequestOptions(), type: DioExceptionType.receiveTimeout)).code, 'timeout');
      expect(mapDioError(const SocketException('x')).code, 'offline');
    });
    test('unconfigured client refuses to call', () async {
      final api = ApiClient(baseUrl: '', apiKey: '');
      expect(() => api.status(), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'not_configured')));
    });
  });

  group('storage', () {
    test('library persists across restarts and drops missing files', () async {
      final root = await tempDir();
      final repo = LibraryRepository(AppDirs(root: root));
      final p1 = await repo.newFilePath('a', 'wav');
      await File(p1).writeAsBytes(FakeServer.wavBytes());
      final items = [
        LibraryItem(id: 'a', title: 'أ', text: 'نص', voiceName: 'صوتي', createdAt: DateTime(2026), durationMs: 1000, sizeBytes: 10, filePath: p1),
        LibraryItem(id: 'b', title: 'ب', text: 'نص', voiceName: 'صوتي', createdAt: DateTime(2026), durationMs: 1000, sizeBytes: 10, filePath: '${root.path}/missing.wav'),
      ];
      await repo.save(items);
      final reopened = await LibraryRepository(AppDirs(root: root)).load();
      expect(reopened.map((i) => i.id), ['a']);
      expect(reopened.first.title, 'أ');
    });

    test('settings: api key goes to secret store, not prefs', () async {
      final secrets = MemorySecretStore();
      final store = SettingsStore(secrets: secrets);
      final s = AppSettings(serverUrl: 'https://x.hf.space', apiKey: 'secret-123');
      await store.save(s);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().any((k) => prefs.get(k).toString().contains('secret-123')), isFalse);
      expect(await secrets.read('sawti_api_key'), 'secret-123');
      final loaded = await store.load();
      expect(loaded.apiKey, 'secret-123');
      expect(loaded.serverUrl, 'https://x.hf.space');
    });
  });

  group('app state flows (scripted server)', () {
    test('status: unauthorized key is reported', () async {
      final root = await tempDir();
      final server = FakeServer();
      final s = makeState(root, server);
      await s.init();
      await s.updateSettings((x) {
        x.serverUrl = 'https://x.hf.space';
        x.apiKey = 'bad';
      });
      final st = await s.refreshServerStatus();
      expect(st.state, ConnectionState2.unauthorized);
    });

    test('voice: upload + prepare -> ready only after the server confirms', () async {
      final root = await tempDir();
      final server = FakeServer();
      final s = await readyState(root, server);
      final v = await s.addVoice(sourcePath: await writeSample(root), name: 'صوتي', transcript: 'نص');
      expect(File(v.samplePath).existsSync(), isTrue);
      expect(v.samplePath.startsWith(root.path), isTrue, reason: 'sample copied to private storage');
      final ok = await s.processVoice(v);
      expect(ok, isTrue);
      expect(v.status, VoiceStatus.ready);
      expect(v.serverVoiceId, isNotNull);
      expect(v.referenceSeconds, 7.5);
      expect(s.voiceTask.value.phase, TaskPhase.done);
    });

    test('generate: real file saved, library updated, server copy deleted', () async {
      final root = await tempDir();
      final server = FakeServer();
      final s = await readyState(root, server);
      final v = await s.addVoice(sourcePath: await writeSample(root), name: 'صوتي', transcript: 'نص');
      await s.processVoice(v);
      final item = await s.generate(voice: v, text: 'مرحباً بك، هذا اختبار.');
      expect(item, isNotNull);
      expect(File(item!.filePath).existsSync(), isTrue);
      expect(File(item.filePath).readAsBytesSync().sublist(0, 4), 'RIFF'.codeUnits);
      expect(s.library.first.id, item.id);
      expect(s.genTask.value.phase, TaskPhase.done);
      await Future<void>.delayed(const Duration(milliseconds: 50)); // delete is fire-and-forget
      expect(server.requests.any((r) => r.method == 'DELETE' && r.uri.path.startsWith('/api/audio/')), isTrue);
      // generate request carried a request id (double-submit protection)
      final gen = server.requests.firstWhere((r) => r.uri.path == '/api/tts/generate');
      expect((gen.data as Map)['request_id'], isNotEmpty);
    });

    test('generate: corrupt download is NOT reported as success', () async {
      final root = await tempDir();
      final server = FakeServer()..corruptAudio = true;
      final s = await readyState(root, server);
      final v = await s.addVoice(sourcePath: await writeSample(root), name: 'صوتي', transcript: 'نص');
      await s.processVoice(v);
      final item = await s.generate(voice: v, text: 'مرحبا');
      expect(item, isNull);
      expect(s.genTask.value.phase, TaskPhase.error);
      expect(s.library, isEmpty);
    });

    test('generate: server lost its data -> voice re-created from local sample', () async {
      final root = await tempDir();
      final server = FakeServer();
      final s = await readyState(root, server);
      final v = await s.addVoice(sourcePath: await writeSample(root), name: 'صوتي', transcript: 'نص');
      await s.processVoice(v);
      final firstId = v.serverVoiceId;
      server.loseVoicesOnce = true;
      final item = await s.generate(voice: v, text: 'مرحبا');
      expect(item, isNotNull);
      expect(v.serverVoiceId, isNot(firstId));
      expect(server.requests.where((r) => r.uri.path == '/api/voice/upload').length, 2);
    });

    test('generate: empty text rejected locally', () async {
      final root = await tempDir();
      final s = await readyState(root, FakeServer());
      final v = await s.addVoice(sourcePath: await writeSample(root), name: 'صوتي', transcript: 'نص');
      expect(await s.generate(voice: v, text: '   '), isNull);
      expect(s.genTask.value.error?.code, 'empty_text');
    });

    test('generate: a second request while busy is ignored', () async {
      final root = await tempDir();
      final server = FakeServer()..pollsUntilDone = 5;
      final s = await readyState(root, server);
      final v = await s.addVoice(sourcePath: await writeSample(root), name: 'صوتي', transcript: 'نص');
      await s.processVoice(v);
      final a = s.generate(voice: v, text: 'أولاً');
      final b = await s.generate(voice: v, text: 'ثانياً');
      expect(b, isNull);
      expect(await a, isNotNull);
      expect(server.requests.where((r) => r.uri.path == '/api/tts/generate').length, 1);
    });

    test('delete voice removes it from server and device', () async {
      final root = await tempDir();
      final server = FakeServer();
      final s = await readyState(root, server);
      final v = await s.addVoice(sourcePath: await writeSample(root), name: 'صوتي', transcript: 'نص');
      await s.processVoice(v);
      await s.deleteVoice(v);
      expect(server.voices, isEmpty);
      expect(File(v.samplePath).existsSync(), isFalse);
      expect(s.voices, isEmpty);
    });

    test('library delete and delete-all', () async {
      final root = await tempDir();
      final s = await readyState(root, FakeServer());
      final v = await s.addVoice(sourcePath: await writeSample(root), name: 'صوتي', transcript: 'نص');
      await s.processVoice(v);
      final a = await s.generate(voice: v, text: 'واحد');
      await s.generate(voice: v, text: 'اثنان');
      expect(s.library.length, 2);
      await s.deleteLibraryItem(a!);
      expect(File(a.filePath).existsSync(), isFalse);
      expect(s.library.length, 1);
      await s.deleteAllLocalAudio();
      expect(s.library, isEmpty);
      expect(await LibraryRepository(AppDirs(root: root)).load(), isEmpty);
    });
  });
}
