import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hhkkll/services/sources.dart';
import 'package:hhkkll_core/hhkkll_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> q(String id, String created) => {
      'id': id,
      'category': 'buzzer',
      'difficulty': 'expert',
      'question': 'سؤال تجريبي رقم $id عن نهائي قديم',
      'answer': 'جواب $id',
      'accepted_answers': <String>[],
      'topic': '',
      'semantic_key': 'k-$id',
      'sources': [
        {'title': 't', 'url': 'https://example.org/$id'},
      ],
      'created_at': created,
      'verification': {'status': 'verified', 'method': 'ai-independent-web-verification'},
      'origin': 'feed',
    };

void main() {
  test('server source posts the section and the exclusion list', () async {
    late Map<String, dynamic> sent;
    final client = MockClient((req) async {
      expect(req.url.toString(), 'https://srv.example/v1/questions');
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response.bytes(
          utf8.encode(jsonEncode({'questions': [q('1', '2026-11-01T00:00:00Z')]})), 200);
    });
    final out = await ServerSource('https://srv.example/', client: client)
        .fetch(Category.buzzer, 4, excludeFingerprints: ['abc']);
    expect(sent, {'category': 'buzzer', 'count': 4, 'exclude': ['abc']});
    expect(out.single.text, contains('سؤال تجريبي'));
  });

  test('server errors surface as exceptions (supply then retries)', () async {
    final client = MockClient((_) async => http.Response('no', 503));
    expect(
      ServerSource('https://srv.example', client: client)
          .fetch(Category.buzzer, 4, excludeFingerprints: const []),
      throwsException,
    );
  });

  test('feed source: newest first, skips used, caches downloads', () async {
    var gets = 0;
    final client = MockClient((req) async {
      gets++;
      expect(req.url.path, endsWith('/buzzer.json'));
      return http.Response.bytes(
          utf8.encode(jsonEncode({
            'questions': [q('old', '2026-01-01T00:00:00Z'), q('new', '2026-11-01T00:00:00Z'), q('used', '2026-06-01T00:00:00Z')],
          })),
          200);
    });
    final used = Question.fromJson(q('used', '2026-06-01T00:00:00Z')).semanticFingerprint;
    final feed = FeedSource('https://feed.example/feed', client: client);
    final a = await feed.fetch(Category.buzzer, 5, excludeFingerprints: [used]);
    expect(a.map((e) => e.id), ['new', 'old']);
    await feed.fetch(Category.buzzer, 5, excludeFingerprints: const []);
    expect(gets, 1, reason: 'second call served from the 5-minute cache');
  });

  test('feed not published yet (404) is not an error', () async {
    final client = MockClient((_) async => http.Response('', 404));
    final out = await FeedSource('https://feed.example', client: client)
        .fetch(Category.auction, 5, excludeFingerprints: const []);
    expect(out, isEmpty);
  });
}
