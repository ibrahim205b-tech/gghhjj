import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../models.dart';

/// Error with a user-facing Arabic message.
class ApiException implements Exception {
  final String code;
  final String message;
  final int? statusCode;

  const ApiException(this.code, this.message, {this.statusCode});

  /// Errors where simply retrying later can help.
  bool get retryable => const {
        'offline',
        'timeout',
        'server_waking',
        'engine_not_ready',
        'queue_full',
        'rate_limited',
        'server_error',
      }.contains(code);

  @override
  String toString() => 'ApiException($code, $statusCode): $message';
}

/// Maps any Dio failure to an [ApiException] with a clear Arabic message.
ApiException mapDioError(Object e) {
  if (e is ApiException) return e;
  if (e is DioException) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const ApiException('timeout', 'انتهت مهلة الاتصال بالخادم. تحقق من الإنترنت وأعد المحاولة.');
      case DioExceptionType.connectionError:
        return const ApiException('offline', 'تعذر الوصول إلى الخادم. تحقق من اتصال الإنترنت أو من عنوان الخادم.');
      case DioExceptionType.badCertificate:
        return const ApiException('bad_certificate', 'شهادة أمان الخادم غير صالحة. لن يتم الاتصال لحماية بياناتك.');
      case DioExceptionType.cancel:
        return const ApiException('cancelled', 'تم إلغاء العملية.');
      case DioExceptionType.badResponse:
        return _fromResponse(e.response);
      case DioExceptionType.unknown:
        if (e.error is SocketException || e.error is HttpException) {
          return const ApiException('offline', 'تعذر الوصول إلى الخادم. تحقق من اتصال الإنترنت.');
        }
        if (e.error is HandshakeException) {
          return const ApiException('bad_certificate', 'فشل الاتصال الآمن بالخادم.');
        }
        return ApiException('network', 'خطأ في الشبكة: ${e.message ?? ''}'.trim());
    }
  }
  if (e is SocketException) {
    return const ApiException('offline', 'لا يوجد اتصال بالإنترنت.');
  }
  if (e is TimeoutException) {
    return const ApiException('timeout', 'انتهت مهلة العملية.');
  }
  return ApiException('unknown', 'حدث خطأ غير متوقع.');
}

ApiException _fromResponse(Response? r) {
  final code = r?.statusCode ?? 0;
  final data = r?.data;
  if (data is Map && data['detail'] is Map) {
    final d = (data['detail'] as Map).cast<String, dynamic>();
    return ApiException(d['code'] as String? ?? 'error', d['message'] as String? ?? 'خطأ من الخادم.', statusCode: code);
  }
  if (code == 401) return ApiException('unauthorized', 'مفتاح الوصول غير صحيح.', statusCode: code);
  if (code == 404) return ApiException('not_found', 'المورد غير موجود على الخادم.', statusCode: code);
  // Free hosting (e.g. a sleeping Hugging Face Space) answers with an HTML
  // page or a gateway error while the container is starting.
  if (code == 502 || code == 503 || code == 504 || (data is String && data.contains('<html'))) {
    return ApiException('server_waking',
        'الخادم في وضع السكون ويجري تشغيله الآن. قد يستغرق ذلك عدة دقائق في الاستضافة المجانية.',
        statusCode: code);
  }
  if (code >= 500) return ApiException('server_error', 'حدث خطأ في الخادم ($code).', statusCode: code);
  return ApiException('http_$code', 'رد غير متوقع من الخادم ($code).', statusCode: code);
}

class ApiClient {
  ApiClient({required String baseUrl, required String apiKey, Dio? dio})
      : _dio = dio ?? Dio() {
    configure(baseUrl: baseUrl, apiKey: apiKey);
  }

  final Dio _dio;
  String _baseUrl = '';

  String get baseUrl => _baseUrl;
  bool get configured => _baseUrl.isNotEmpty;

  void configure({required String baseUrl, required String apiKey}) {
    _baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    _dio.options
      ..baseUrl = _baseUrl
      ..connectTimeout = const Duration(seconds: 25)
      ..sendTimeout = const Duration(minutes: 5)
      ..receiveTimeout = const Duration(minutes: 3)
      ..headers = {
        if (apiKey.isNotEmpty) 'Authorization': 'Bearer ${apiKey.trim()}',
        'Accept': 'application/json',
      };
  }

  void _requireConfigured() {
    if (!configured) {
      throw const ApiException('not_configured', 'لم يتم ضبط عنوان الخادم بعد. افتح الإعدادات وأدخل العنوان ومفتاح الوصول.');
    }
  }

  Future<T> _call<T>(Future<T> Function() f) async {
    _requireConfigured();
    try {
      return await f();
    } catch (e) {
      throw mapDioError(e);
    }
  }

  Map<String, dynamic> _json(Response r) {
    final d = r.data;
    if (d is Map) return d.cast<String, dynamic>();
    throw const ApiException('server_waking',
        'الخادم يستيقظ من وضع السكون. انتظر قليلاً ثم أعد المحاولة.');
  }

  /// Public liveness check (no key needed).
  Future<Map<String, dynamic>> health() => _call(() async => _json(await _dio.get('/health')));

  Future<ServerStatus> status() => _call(() async => ServerStatus.fromJson(_json(await _dio.get('/api/status'))));

  Future<void> requestEngineLoad() => _call(() => _dio.post('/api/engine/load'));

  Future<Map<String, dynamic>> uploadVoice({
    required String filePath,
    required String name,
    required String transcript,
    void Function(double)? onProgress,
    CancelToken? cancelToken,
  }) =>
      _call(() async {
        final form = FormData.fromMap({
          'file': await MultipartFile.fromFile(filePath, filename: filePath.split(Platform.pathSeparator).last),
          'name': name,
          'transcript': transcript,
        });
        final r = await _dio.post('/api/voice/upload',
            data: form,
            cancelToken: cancelToken,
            onSendProgress: (s, t) => onProgress?.call(t > 0 ? s / t : 0));
        return _json(r);
      });

  /// Returns the job id, or null if the voice is already prepared.
  Future<String?> prepareVoice(String voiceId) => _call(() async {
        final r = _json(await _dio.post('/api/voice/prepare', data: {'voice_id': voiceId}));
        return r['job_id'] as String?;
      });

  Future<Map<String, dynamic>> voiceStatus(String voiceId) =>
      _call(() async => _json(await _dio.get('/api/voice/status', queryParameters: {'voice_id': voiceId})));

  Future<void> deleteVoice(String voiceId) => _call(() => _dio.delete('/api/voice/$voiceId'));

  Future<void> deleteVoiceOriginal(String voiceId) => _call(() => _dio.delete('/api/voice/$voiceId/original'));

  Future<Map<String, dynamic>> deleteAllServerData() => _call(() async => _json(await _dio.delete('/api/data')));

  Future<String> generate({
    required String voiceId,
    required String text,
    required String language,
    double speed = 1.0,
    String? style,
    String? quality,
    required String requestId,
  }) =>
      _call(() async {
        final r = _json(await _dio.post('/api/tts/generate', data: {
          'voice_id': voiceId,
          'text': text,
          'language': language,
          'speed': speed,
          'style': ?style,
          'quality': ?quality,
          'request_id': requestId,
        }));
        return r['job_id'] as String;
      });

  Future<JobInfo> job(String jobId) => _call(() async => JobInfo.fromJson(_json(await _dio.get('/api/tts/status/$jobId'))));

  Future<Map<String, dynamic>> audioInfo(String audioId) =>
      _call(() async => _json(await _dio.get('/api/audio/$audioId/info')));

  Future<void> downloadAudio(String audioId, String savePath,
          {String format = 'wav', void Function(double)? onProgress, CancelToken? cancelToken}) =>
      _call(() async {
        final tmp = '$savePath.part';
        await _dio.download('/api/audio/$audioId', tmp,
            queryParameters: {'format': format},
            cancelToken: cancelToken,
            options: Options(receiveTimeout: const Duration(minutes: 5)),
            onReceiveProgress: (r, t) => onProgress?.call(t > 0 ? r / t : 0));
        final f = File(tmp);
        final head = await f.openRead(0, 4).fold<List<int>>([], (a, b) => a..addAll(b));
        final valid = format == 'wav' ? String.fromCharCodes(head) == 'RIFF' : head.length == 4;
        if (!valid) {
          await f.delete();
          throw const ApiException('bad_audio', 'الملف المستلم ليس ملفاً صوتياً صالحاً.');
        }
        await f.rename(savePath);
      });

  Future<void> deleteAudio(String audioId) => _call(() => _dio.delete('/api/audio/$audioId'));
}
