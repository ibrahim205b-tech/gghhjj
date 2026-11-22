import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A scripted HTTP backend for client-side unit tests. It mirrors the real
/// Sawti API contract (status codes and JSON shapes) so the app's state
/// machine can be tested without a network. Real end-to-end behaviour is
/// covered by integration_test/ against the real server.
class FakeServer implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final voices = <String, Map<String, dynamic>>{};
  final jobs = <String, Map<String, dynamic>>{};
  int _n = 0;
  bool loseVoicesOnce = false;
  bool corruptAudio = false;
  String engineState = 'ready';
  int pollsUntilDone = 2;

  static Uint8List wavBytes({double seconds = 1}) {
    const sr = 16000;
    final n = (sr * seconds).round();
    final b = BytesBuilder();
    void u32(int v) => b.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
    void u16(int v) => b.add((ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List());
    b.add(ascii.encode('RIFF'));
    u32(36 + n * 2);
    b.add(ascii.encode('WAVEfmt '));
    u32(16);
    u16(1);
    u16(1);
    u32(sr);
    u32(sr * 2);
    u16(2);
    u16(16);
    b.add(ascii.encode('data'));
    u32(n * 2);
    b.add(Uint8List(n * 2));
    return b.toBytes();
  }

  ResponseBody _json(int code, Object body) => ResponseBody.fromString(jsonEncode(body), code, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  ResponseBody _err(int code, String c, String m) => _json(code, {
        'detail': {'code': c, 'message': m}
      });

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(o);
    if (requestStream != null) await requestStream.drain<void>();
    final path = o.uri.path;
    if (path == '/health') return _json(200, {'status': 'ok', 'engine_state': engineState});
    if (o.headers['Authorization'] != 'Bearer good-key') return _err(401, 'unauthorized', 'مفتاح الوصول غير صحيح.');
    if (path == '/api/status') {
      return _json(200, {
        'engine_state': engineState,
        'engine': {'id': 'silma', 'name': 'SILMA TTS v1', 'languages': ['ar', 'en'], 'supports_speed': true, 'speed_range': [0.7, 1.3]},
        'limits': {'max_text_chars': 2000, 'max_upload_mb': 25, 'audio_ttl_minutes': 60},
        'storage': {'persistent': false},
      });
    }
    if (path == '/api/voice/upload' && o.method == 'POST') {
      final id = 'voice_${++_n}';
      voices[id] = {'voice_id': id, 'status': 'uploaded', 'quality': {'score': 90, 'label': 'ممتازة', 'warnings': []}};
      return _json(201, voices[id]!);
    }
    if (path == '/api/voice/prepare') {
      final id = (o.data as Map)['voice_id'] as String;
      if (!voices.containsKey(id)) return _err(404, 'voice_not_found', 'غير موجود');
      final jid = 'job_${++_n}';
      jobs[jid] = {'kind': 'prepare', 'voice': id, 'polls': 0};
      return _json(202, {'job_id': jid});
    }
    if (path == '/api/tts/generate') {
      final id = (o.data as Map)['voice_id'] as String;
      if (loseVoicesOnce) {
        loseVoicesOnce = false;
        voices.clear();
      }
      if (!voices.containsKey(id)) return _err(404, 'voice_not_found', 'غير موجود');
      final jid = 'job_${++_n}';
      jobs[jid] = {'kind': 'tts', 'voice': id, 'polls': 0, 'request_id': (o.data as Map)['request_id']};
      return _json(202, {'job_id': jid});
    }
    if (path.startsWith('/api/tts/status/')) {
      final jid = path.split('/').last;
      final j = jobs[jid];
      if (j == null) return _err(404, 'job_not_found', 'غير موجودة');
      j['polls'] = (j['polls'] as int) + 1;
      final done = (j['polls'] as int) >= pollsUntilDone;
      if (done && j['kind'] == 'prepare') voices[j['voice']]!['status'] = 'ready';
      return _json(200, {
        'job_id': jid,
        'status': done ? 'done' : 'running',
        'progress': done ? 1.0 : 0.5,
        'chunks_total': 2,
        'chunks_done': done ? 2 : 1,
        'result': done
            ? (j['kind'] == 'tts'
                ? {'audio_id': 'audio_$jid', 'duration_seconds': 1.0, 'size_bytes': 32044}
                : {'voice_id': j['voice'], 'reference_seconds': 7.5})
            : null,
      });
    }
    if (path.startsWith('/api/audio/') && o.method == 'GET') {
      final bytes = corruptAudio ? Uint8List.fromList(utf8.encode('<html>sleeping</html>')) : wavBytes();
      return ResponseBody.fromBytes(bytes, 200, headers: {Headers.contentTypeHeader: ['audio/wav']});
    }
    if (path.startsWith('/api/audio/') && o.method == 'DELETE') return _json(200, {'deleted': true});
    if (path.startsWith('/api/voice/') && o.method == 'DELETE') {
      final id = path.split('/').last;
      return voices.remove(id) == null ? _err(404, 'voice_not_found', 'x') : _json(200, {'deleted': true});
    }
    if (path == '/api/data' && o.method == 'DELETE') {
      final n = voices.length;
      voices.clear();
      return _json(200, {'deleted': true, 'voices': n});
    }
    return _err(404, 'not_found', 'not found');
  }

  @override
  void close({bool force = false}) {}
}

Future<Directory> tempDir() => Directory.systemTemp.createTemp('sawti_test_');

Future<String> writeSample(Directory d) async {
  final f = File('${d.path}/sample.wav');
  await f.writeAsBytes(FakeServer.wavBytes(seconds: 6));
  return f.path;
}
