import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:uuid/uuid.dart';

import '../models.dart';
import '../services/api.dart';
import '../services/storage.dart';
import '../utils/format.dart';

enum TaskPhase { idle, uploading, preparing, queued, running, downloading, done, error }

/// Progress of a long server operation, observed by the UI.
class TaskState {
  final TaskPhase phase;
  final double progress; // 0..1 within the phase
  final String message;
  final ApiException? error;
  final int chunksDone;
  final int chunksTotal;
  final int? queuePosition;
  final bool connectionTrouble;

  const TaskState(this.phase,
      {this.progress = 0,
      this.message = '',
      this.error,
      this.chunksDone = 0,
      this.chunksTotal = 0,
      this.queuePosition,
      this.connectionTrouble = false});

  bool get busy => !(phase == TaskPhase.idle || phase == TaskPhase.done || phase == TaskPhase.error);
  static const idle = TaskState(TaskPhase.idle);
}

class AppState extends ChangeNotifier {
  AppState({
    required this.settingsStore,
    required this.voiceRepo,
    required this.libraryRepo,
    required this.dirs,
    ApiClient? api,
    this.pollInterval = const Duration(seconds: 2),
  }) : api = api ?? ApiClient(baseUrl: '', apiKey: '');

  final SettingsStore settingsStore;
  final VoiceRepository voiceRepo;
  final LibraryRepository libraryRepo;
  final AppDirs dirs;
  final ApiClient api;
  final Duration pollInterval;
  final _uuid = const Uuid();

  AppSettings settings = AppSettings();
  List<LocalVoice> voices = [];
  List<LibraryItem> library = [];
  String? activeVoiceId;
  ServerStatus server = ServerStatus(state: ConnectionState2.unknown);
  bool loaded = false;

  final ValueNotifier<TaskState> voiceTask = ValueNotifier(TaskState.idle);
  final ValueNotifier<TaskState> genTask = ValueNotifier(TaskState.idle);

  Timer? _statusTimer;
  bool _checking = false;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    settings = await settingsStore.load();
    api.configure(baseUrl: settings.serverUrl, apiKey: settings.apiKey);
    voices = await voiceRepo.load();
    library = await libraryRepo.load();
    // A voice left "uploading/preparing" by a killed app is not ready.
    for (final v in voices) {
      if (v.status == VoiceStatus.uploading || v.status == VoiceStatus.preparing) {
        v.status = v.serverVoiceId == null ? VoiceStatus.local : VoiceStatus.failed;
      }
    }
    activeVoiceId = voices.where((v) => v.status == VoiceStatus.ready).map((v) => v.id).firstOrNull ??
        voices.map((v) => v.id).firstOrNull;
    loaded = true;
    notifyListeners();
    unawaited(refreshServerStatus());
    _scheduleStatus();
    await _cleanTemp();
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    voiceTask.dispose();
    genTask.dispose();
    super.dispose();
  }

  void _scheduleStatus() {
    _statusTimer?.cancel();
    final fast = server.state == ConnectionState2.waking || server.engineState == 'loading';
    _statusTimer = Timer(Duration(seconds: fast ? 10 : 45), () async {
      await refreshServerStatus();
      _scheduleStatus();
    });
  }

  Future<void> _cleanTemp() async {
    try {
      final t = await dirs.temp();
      final cutoff = DateTime.now().subtract(const Duration(hours: 1));
      await for (final e in t.list()) {
        if (e is File && (await e.lastModified()).isBefore(cutoff)) await e.delete();
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Settings / server
  // ---------------------------------------------------------------------------

  Future<void> updateSettings(void Function(AppSettings s) change) async {
    change(settings);
    await settingsStore.save(settings);
    api.configure(baseUrl: settings.serverUrl, apiKey: settings.apiKey);
    notifyListeners();
  }

  ThemeMode get themeMode => settings.themeMode;

  /// Validates a server address. HTTPS is required except for local test hosts.
  static String? validateServerUrl(String url) {
    final u = Uri.tryParse(url.trim());
    if (url.trim().isEmpty) return 'أدخل عنوان الخادم';
    if (u == null || !u.hasScheme || u.host.isEmpty) return 'العنوان غير صالح. مثال: https://name-sawtiai.hf.space';
    const localHosts = {'10.0.2.2', '127.0.0.1', 'localhost'};
    if (u.scheme == 'http' && !localHosts.contains(u.host)) return 'يجب أن يبدأ العنوان بـ https:// لحماية بياناتك';
    if (u.scheme != 'https' && u.scheme != 'http') return 'العنوان يجب أن يبدأ بـ https://';
    return null;
  }

  Future<ServerStatus> refreshServerStatus() async {
    if (_checking) return server;
    if (!settings.serverConfigured) {
      server = ServerStatus(state: ConnectionState2.notConfigured, message: 'لم يتم ربط الخادم بعد');
      notifyListeners();
      return server;
    }
    _checking = true;
    if (server.state == ConnectionState2.unknown) {
      server = ServerStatus(state: ConnectionState2.checking);
      notifyListeners();
    }
    try {
      final st = await api.status();
      server = st;
      if (st.engineState == 'not_loaded') unawaited(api.requestEngineLoad().catchError((_) {}));
    } on ApiException catch (e) {
      server = ServerStatus(
        state: switch (e.code) {
          'unauthorized' || 'too_many_attempts' => ConnectionState2.unauthorized,
          'server_waking' => ConnectionState2.waking,
          'offline' || 'timeout' => ConnectionState2.offline,
          _ => ConnectionState2.error,
        },
        message: e.message,
      );
    } finally {
      _checking = false;
    }
    notifyListeners();
    return server;
  }

  /// Test a URL + key without saving them.
  Future<ServerStatus> testConnection(String url, String key) async {
    final probe = ApiClient(baseUrl: url, apiKey: key);
    try {
      return await probe.status();
    } on ApiException catch (e) {
      return ServerStatus(
          state: e.code == 'unauthorized' ? ConnectionState2.unauthorized : ConnectionState2.error, message: e.message);
    }
  }

  // ---------------------------------------------------------------------------
  // Voices
  // ---------------------------------------------------------------------------

  LocalVoice? get activeVoice => voices.where((v) => v.id == activeVoiceId).firstOrNull;
  List<LocalVoice> get readyVoices => voices.where((v) => v.status == VoiceStatus.ready).toList();

  void selectVoice(String id) {
    activeVoiceId = id;
    notifyListeners();
  }

  /// Registers a recorded or imported sample (copied into private storage).
  Future<LocalVoice> addVoice({required String sourcePath, required String name, required String transcript}) async {
    final id = _uuid.v4();
    final stored = await voiceRepo.storeSample(id, sourcePath);
    final v = LocalVoice(id: id, name: name.trim().isEmpty ? 'صوتي' : name.trim(), samplePath: stored, transcript: transcript.trim());
    voices.insert(0, v);
    activeVoiceId = v.id;
    await voiceRepo.save(voices);
    notifyListeners();
    return v;
  }

  Future<void> _saveVoices() async {
    await voiceRepo.save(voices);
    notifyListeners();
  }

  /// Upload + prepare a voice on the server. Reports progress via [voiceTask].
  /// Returns true only when the server confirmed the voice is ready.
  Future<bool> processVoice(LocalVoice v) async {
    if (voiceTask.value.busy) return false;
    try {
      await _uploadAndPrepare(v, voiceTask);
      voiceTask.value = const TaskState(TaskPhase.done, progress: 1, message: 'تم تجهيز نسختك الصوتية');
      return true;
    } on ApiException catch (e) {
      v.status = VoiceStatus.failed;
      v.error = e.message;
      await _saveVoices();
      voiceTask.value = TaskState(TaskPhase.error, error: e, message: e.message);
      return false;
    }
  }

  Future<void> _uploadAndPrepare(LocalVoice v, ValueNotifier<TaskState> task) async {
    if (!File(v.samplePath).existsSync()) {
      throw const ApiException('sample_missing', 'العينة المحلية غير موجودة. سجّل أو ارفع عينة جديدة.');
    }
    v.status = VoiceStatus.uploading;
    v.error = null;
    await _saveVoices();
    task.value = const TaskState(TaskPhase.uploading, message: 'جارٍ رفع العينة إلى الخادم...');
    final up = await api.uploadVoice(
      filePath: v.samplePath,
      name: v.name,
      transcript: v.transcript,
      onProgress: (p) => task.value = TaskState(TaskPhase.uploading, progress: p, message: 'جارٍ رفع العينة... ${(p * 100).round()}٪'),
    );
    v.serverVoiceId = up['voice_id'] as String;
    v.quality = (up['quality'] as Map?)?.cast<String, dynamic>();
    v.status = VoiceStatus.preparing;
    await _saveVoices();
    task.value = const TaskState(TaskPhase.preparing, message: 'يحلل الخادم العينة ويجهز نسختك الصوتية...');
    final jobId = await _withEngineWait(() => api.prepareVoice(v.serverVoiceId!), task);
    if (jobId != null) {
      final job = await _pollJob(jobId, task, preparing: true);
      v.referenceSeconds = (job.result?['reference_seconds'] as num?)?.toDouble();
    }
    v.status = VoiceStatus.ready;
    await _saveVoices();
  }

  /// Retries an action while the engine is still loading (cold start).
  Future<T> _withEngineWait<T>(Future<T> Function() f, ValueNotifier<TaskState> task) async {
    final deadline = DateTime.now().add(const Duration(minutes: 20));
    while (true) {
      try {
        return await f();
      } on ApiException catch (e) {
        final wait = e.code == 'engine_not_ready' || e.code == 'server_waking';
        if (!wait || DateTime.now().isAfter(deadline)) rethrow;
        task.value = TaskState(task.value.phase == TaskPhase.idle ? TaskPhase.queued : task.value.phase,
            message: e.code == 'server_waking'
                ? 'الخادم يستيقظ من السكون (الاستضافة المجانية). قد يستغرق ذلك بضع دقائق...'
                : 'محرك الصوت يُحمَّل على الخادم. يرجى الانتظار...');
        await Future.delayed(const Duration(seconds: 8));
      }
    }
  }

  Future<JobInfo> _pollJob(String jobId, ValueNotifier<TaskState> task, {bool preparing = false}) async {
    var failures = 0;
    final started = DateTime.now();
    while (true) {
      await Future.delayed(pollInterval);
      JobInfo j;
      try {
        j = await api.job(jobId);
        failures = 0;
      } on ApiException catch (e) {
        if (e.code == 'job_not_found') {
          throw const ApiException('job_lost', 'أعيد تشغيل الخادم أثناء المعالجة. أعد المحاولة.');
        }
        if (!e.retryable || ++failures > 30) rethrow;
        task.value = TaskState(task.value.phase,
            progress: task.value.progress,
            chunksDone: task.value.chunksDone,
            chunksTotal: task.value.chunksTotal,
            connectionTrouble: true,
            message: 'انقطع الاتصال مؤقتاً... نحاول مجدداً (${e.message})');
        await Future.delayed(const Duration(seconds: 3));
        continue;
      }
      if (j.status == 'failed') {
        throw ApiException(j.errorCode ?? 'job_failed', j.errorMessage ?? 'فشلت المعالجة على الخادم.');
      }
      if (j.status == 'done') return j;
      final secs = DateTime.now().difference(started).inSeconds;
      if (j.status == 'queued') {
        task.value = TaskState(TaskPhase.queued,
            queuePosition: j.queuePosition, message: 'بانتظار دورك على الخادم (${j.queuePosition ?? '-'})...');
      } else {
        task.value = TaskState(preparing ? TaskPhase.preparing : TaskPhase.running,
            progress: j.progress,
            chunksDone: j.chunksDone,
            chunksTotal: j.chunksTotal,
            message: preparing
                ? 'يجهز الخادم نسختك الصوتية... ($secs ث)'
                : j.chunksTotal > 1
                    ? 'جارٍ توليد الصوت: الجزء ${j.chunksDone + 1} من ${j.chunksTotal} ($secs ث)'
                    : 'جارٍ توليد الصوت... ($secs ث)');
      }
    }
  }

  Future<void> deleteVoice(LocalVoice v, {bool fromServer = true}) async {
    if (fromServer && v.serverVoiceId != null && settings.serverConfigured) {
      try {
        await api.deleteVoice(v.serverVoiceId!);
      } on ApiException catch (e) {
        // Already gone on the server is fine; anything else is reported.
        if (e.statusCode != 404 && e.code != 'voice_not_found') rethrow;
      }
    }
    await voiceRepo.deleteSample(v);
    voices.removeWhere((x) => x.id == v.id);
    if (activeVoiceId == v.id) activeVoiceId = voices.map((x) => x.id).firstOrNull;
    await _saveVoices();
  }

  Future<void> deleteVoiceOriginalOnServer(LocalVoice v) async {
    if (v.serverVoiceId == null) return;
    await api.deleteVoiceOriginal(v.serverVoiceId!);
  }

  Future<int> deleteAllServerData() async {
    final r = await api.deleteAllServerData();
    for (final v in voices) {
      v.serverVoiceId = null;
      v.status = VoiceStatus.local;
    }
    await _saveVoices();
    return (r['voices'] as num?)?.toInt() ?? 0;
  }

  // ---------------------------------------------------------------------------
  // Generation
  // ---------------------------------------------------------------------------

  /// Generates speech. Returns the saved library item only after a real audio
  /// file was received from the server and written to storage.
  Future<LibraryItem?> generate({
    required LocalVoice voice,
    required String text,
    String? language,
    double? speed,
    String? style,
    String? quality,
  }) async {
    if (genTask.value.busy) return null; // one generation at a time
    final clean = text.trim();
    if (clean.isEmpty) {
      genTask.value = const TaskState(TaskPhase.error,
          error: ApiException('empty_text', 'اكتب نصاً أولاً.'), message: 'اكتب نصاً أولاً.');
      return null;
    }
    final requestId = _uuid.v4();
    genTask.value = const TaskState(TaskPhase.queued, message: 'جارٍ إرسال الطلب...');
    try {
      if (voice.serverVoiceId == null || voice.status != VoiceStatus.ready) {
        await _uploadAndPrepare(voice, genTask);
      }
      String jobId;
      try {
        jobId = await _withEngineWait(() => _submit(voice, clean, language, speed, style, quality, requestId), genTask);
      } on ApiException catch (e) {
        if (e.code != 'voice_not_found' && e.code != 'voice_not_ready') rethrow;
        // Free hosting restarted and lost its temporary data: re-create the
        // voice from the private local sample, then retry once.
        genTask.value = const TaskState(TaskPhase.uploading, message: 'أعيد تشغيل الخادم؛ نعيد تجهيز صوتك تلقائياً...');
        voice.serverVoiceId = null;
        await _uploadAndPrepare(voice, genTask);
        jobId = await _withEngineWait(() => _submit(voice, clean, language, speed, style, quality, requestId), genTask);
      }
      final job = await _pollJob(jobId, genTask);
      final audioId = job.result!['audio_id'] as String;
      final serverSize = (job.result!['size_bytes'] as num?)?.toInt() ?? 0;
      final durationS = (job.result!['duration_seconds'] as num?)?.toDouble() ?? 0;
      final fmt = settings.downloadFormat;
      genTask.value = TaskState(TaskPhase.downloading,
          message: 'جارٍ تنزيل الملف${fmt == 'wav' ? ' (${formatBytes(serverSize)})' : ''}...');
      final id = _uuid.v4();
      final path = await libraryRepo.newFilePath(id, fmt);
      await api.downloadAudio(audioId, path,
          format: fmt,
          onProgress: (p) => genTask.value = TaskState(TaskPhase.downloading, progress: p,
              message: 'جارٍ تنزيل الملف... ${(p * 100).round()}٪'));
      final size = await File(path).length();
      final item = LibraryItem(
        id: id,
        title: titleFromText(clean),
        text: clean,
        voiceName: voice.name,
        voiceId: voice.id,
        createdAt: DateTime.now(),
        durationMs: (durationS * 1000).round(),
        sizeBytes: size,
        filePath: path,
        format: fmt,
        params: {'language': ?language, 'speed': ?speed, 'style': ?style, 'quality': ?quality},
      );
      library.insert(0, item);
      await libraryRepo.save(library);
      if (settings.deleteFromServerAfterDownload) {
        unawaited(api.deleteAudio(audioId).catchError((_) {}));
      }
      genTask.value = const TaskState(TaskPhase.done, progress: 1, message: 'تم توليد الصوت');
      notifyListeners();
      return item;
    } on ApiException catch (e) {
      genTask.value = TaskState(TaskPhase.error, error: e, message: e.message);
      return null;
    } catch (e) {
      final err = mapDioError(e);
      genTask.value = TaskState(TaskPhase.error, error: err, message: err.message);
      return null;
    }
  }

  Future<String> _submit(LocalVoice v, String text, String? language, double? speed, String? style, String? quality,
          String requestId) =>
      api.generate(
        voiceId: v.serverVoiceId!,
        text: text,
        language: language ?? settings.language,
        speed: speed ?? settings.speed,
        style: style,
        quality: quality,
        requestId: requestId,
      );

  void resetGenTask() {
    if (!genTask.value.busy) genTask.value = TaskState.idle;
  }

  void resetVoiceTask() {
    if (!voiceTask.value.busy) voiceTask.value = TaskState.idle;
  }

  // ---------------------------------------------------------------------------
  // Library
  // ---------------------------------------------------------------------------

  Future<void> deleteLibraryItem(LibraryItem i) async {
    await libraryRepo.deleteFile(i);
    library.removeWhere((x) => x.id == i.id);
    await libraryRepo.save(library);
    notifyListeners();
  }

  Future<void> renameLibraryItem(LibraryItem i, String title) async {
    i.title = title.trim().isEmpty ? i.title : title.trim();
    await libraryRepo.save(library);
    notifyListeners();
  }

  Future<void> deleteAllLocalAudio() async {
    await libraryRepo.deleteAll();
    library = [];
    await libraryRepo.save(library);
    notifyListeners();
  }

  Future<String> tempPath(String ext) async => '${(await dirs.temp()).path}/${_uuid.v4()}.$ext';
}
