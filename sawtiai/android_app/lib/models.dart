/// Data models shared by services, state and UI.
library;

class EngineInfo {
  final String id;
  final String name;
  final String license;
  final String sourceUrl;
  final String modelUrl;
  final List<String> languages;
  final double minSampleSeconds;
  final double recommendedSampleSeconds;
  final double maxUsefulSampleSeconds;
  final bool needsTranscript;
  final bool supportsSpeed;
  final double speedMin;
  final double speedMax;
  final List<Option> styles;
  final List<Option> qualities;
  final String notes;

  const EngineInfo({
    required this.id,
    required this.name,
    this.license = '',
    this.sourceUrl = '',
    this.modelUrl = '',
    this.languages = const ['ar'],
    this.minSampleSeconds = 3,
    this.recommendedSampleSeconds = 7,
    this.maxUsefulSampleSeconds = 8,
    this.needsTranscript = true,
    this.supportsSpeed = false,
    this.speedMin = 1,
    this.speedMax = 1,
    this.styles = const [],
    this.qualities = const [],
    this.notes = '',
  });

  factory EngineInfo.fromJson(Map<String, dynamic> j) {
    final sr = (j['speed_range'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? [1.0, 1.0];
    List<Option> opts(String k) =>
        ((j[k] as List?) ?? []).map((e) => Option(e['id'] as String, e['label'] as String)).toList();
    return EngineInfo(
      id: j['id'] as String? ?? '',
      name: j['name'] as String? ?? (j['id'] as String? ?? ''),
      license: j['license'] as String? ?? '',
      sourceUrl: j['source_url'] as String? ?? '',
      modelUrl: j['model_url'] as String? ?? '',
      languages: ((j['languages'] as List?) ?? ['ar']).cast<String>(),
      minSampleSeconds: (j['min_sample_seconds'] as num?)?.toDouble() ?? 3,
      recommendedSampleSeconds: (j['recommended_sample_seconds'] as num?)?.toDouble() ?? 7,
      maxUsefulSampleSeconds: (j['max_useful_sample_seconds'] as num?)?.toDouble() ?? 8,
      needsTranscript: j['needs_transcript'] as bool? ?? true,
      supportsSpeed: j['supports_speed'] as bool? ?? false,
      speedMin: sr.first,
      speedMax: sr.last,
      styles: opts('styles'),
      qualities: opts('qualities'),
      notes: j['notes'] as String? ?? '',
    );
  }
}

class Option {
  final String id;
  final String label;
  const Option(this.id, this.label);
}

enum ConnectionState2 { unknown, notConfigured, checking, online, waking, offline, unauthorized, error }

class ServerStatus {
  final ConnectionState2 state;
  final String engineState; // not_loaded | loading | ready | failed
  final EngineInfo? engine;
  final int maxTextChars;
  final int maxUploadMb;
  final int audioTtlMinutes;
  final bool persistentStorage;
  final String? message;
  final DateTime checkedAt;

  ServerStatus({
    required this.state,
    this.engineState = 'unknown',
    this.engine,
    this.maxTextChars = 2000,
    this.maxUploadMb = 25,
    this.audioTtlMinutes = 60,
    this.persistentStorage = false,
    this.message,
    DateTime? checkedAt,
  }) : checkedAt = checkedAt ?? DateTime.now();

  bool get ready => state == ConnectionState2.online && engineState == 'ready';

  factory ServerStatus.fromJson(Map<String, dynamic> j) {
    final limits = (j['limits'] as Map?)?.cast<String, dynamic>() ?? {};
    final storage = (j['storage'] as Map?)?.cast<String, dynamic>() ?? {};
    final eng = j['engine'];
    return ServerStatus(
      state: ConnectionState2.online,
      engineState: j['engine_state'] as String? ?? 'unknown',
      engine: eng is Map ? EngineInfo.fromJson(eng.cast<String, dynamic>()) : null,
      maxTextChars: (limits['max_text_chars'] as num?)?.toInt() ?? 2000,
      maxUploadMb: (limits['max_upload_mb'] as num?)?.toInt() ?? 25,
      audioTtlMinutes: (limits['audio_ttl_minutes'] as num?)?.toInt() ?? 60,
      persistentStorage: storage['persistent'] as bool? ?? false,
    );
  }
}

enum VoiceStatus { local, uploading, preparing, ready, failed }

/// A voice the user created. The sample stays in the app's private storage so
/// the voice can be re-created automatically if the free server restarted
/// and lost its temporary data.
class LocalVoice {
  final String id;
  String name;
  String samplePath;
  String transcript;
  String? serverVoiceId;
  VoiceStatus status;
  Map<String, dynamic>? quality;
  double? referenceSeconds;
  final DateTime createdAt;
  String? error;

  LocalVoice({
    required this.id,
    required this.name,
    required this.samplePath,
    required this.transcript,
    this.serverVoiceId,
    this.status = VoiceStatus.local,
    this.quality,
    this.referenceSeconds,
    DateTime? createdAt,
    this.error,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sample_path': samplePath,
        'transcript': transcript,
        'server_voice_id': serverVoiceId,
        'status': status.name,
        'quality': quality,
        'reference_seconds': referenceSeconds,
        'created_at': createdAt.toIso8601String(),
        'error': error,
      };

  factory LocalVoice.fromJson(Map<String, dynamic> j) => LocalVoice(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'صوتي',
        samplePath: j['sample_path'] as String? ?? '',
        transcript: j['transcript'] as String? ?? '',
        serverVoiceId: j['server_voice_id'] as String?,
        status: VoiceStatus.values.firstWhere((s) => s.name == j['status'], orElse: () => VoiceStatus.local),
        quality: (j['quality'] as Map?)?.cast<String, dynamic>(),
        referenceSeconds: (j['reference_seconds'] as num?)?.toDouble(),
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? ''),
        error: j['error'] as String?,
      );
}

class LibraryItem {
  final String id;
  String title;
  final String text;
  final String voiceName;
  final String? voiceId;
  final DateTime createdAt;
  final int durationMs;
  final int sizeBytes;
  final String filePath;
  final String format;
  final Map<String, dynamic> params;

  LibraryItem({
    required this.id,
    required this.title,
    required this.text,
    required this.voiceName,
    this.voiceId,
    required this.createdAt,
    required this.durationMs,
    required this.sizeBytes,
    required this.filePath,
    this.format = 'wav',
    this.params = const {},
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'text': text,
        'voice_name': voiceName,
        'voice_id': voiceId,
        'created_at': createdAt.toIso8601String(),
        'duration_ms': durationMs,
        'size_bytes': sizeBytes,
        'file_path': filePath,
        'format': format,
        'params': params,
      };

  factory LibraryItem.fromJson(Map<String, dynamic> j) => LibraryItem(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        text: j['text'] as String? ?? '',
        voiceName: j['voice_name'] as String? ?? '',
        voiceId: j['voice_id'] as String?,
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
        durationMs: (j['duration_ms'] as num?)?.toInt() ?? 0,
        sizeBytes: (j['size_bytes'] as num?)?.toInt() ?? 0,
        filePath: j['file_path'] as String,
        format: j['format'] as String? ?? 'wav',
        params: (j['params'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
}

class JobInfo {
  final String id;
  final String status; // queued | running | done | failed
  final double progress;
  final int chunksTotal;
  final int chunksDone;
  final int? queuePosition;
  final String? errorCode;
  final String? errorMessage;
  final Map<String, dynamic>? result;

  JobInfo({
    required this.id,
    required this.status,
    this.progress = 0,
    this.chunksTotal = 0,
    this.chunksDone = 0,
    this.queuePosition,
    this.errorCode,
    this.errorMessage,
    this.result,
  });

  bool get finished => status == 'done' || status == 'failed';

  factory JobInfo.fromJson(Map<String, dynamic> j) => JobInfo(
        id: j['job_id'] as String,
        status: j['status'] as String,
        progress: (j['progress'] as num?)?.toDouble() ?? 0,
        chunksTotal: (j['chunks_total'] as num?)?.toInt() ?? 0,
        chunksDone: (j['chunks_done'] as num?)?.toInt() ?? 0,
        queuePosition: (j['queue_position'] as num?)?.toInt(),
        errorCode: j['error_code'] as String?,
        errorMessage: j['error_message'] as String?,
        result: (j['result'] as Map?)?.cast<String, dynamic>(),
      );
}
