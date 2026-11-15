import 'dart:convert';

import 'package:hhkkll_core/hhkkll_core.dart';
import 'package:http/http.dart' as http;

/// Live generation service (hhkkll/backend). The server holds the AI key;
/// the app only sends the section and the fingerprints it already used.
class ServerSource implements QuestionSource {
  ServerSource(this.baseUrl, {http.Client? client, this.timeout = const Duration(seconds: 20)})
      : _client = client ?? http.Client();
  final String baseUrl;
  final http.Client _client;
  final Duration timeout;

  @override
  String get name => 'الخادم';

  @override
  Future<List<Question>> fetch(Category category, int count,
      {required List<String> excludeFingerprints}) async {
    final uri = Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/v1/questions');
    final res = await _client
        .post(uri,
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'category': category.code,
              'count': count,
              'exclude': excludeFingerprints,
            }))
        .timeout(timeout);
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return [
      for (final e in body['questions'] as List) Question.fromJson((e as Map).cast()),
    ];
  }
}

/// Static feed published by the scheduled GitHub Actions job
/// (`<feed>/<category>.json`). Downloaded at most once every few minutes.
class FeedSource implements QuestionSource {
  FeedSource(this.baseUrl,
      {http.Client? client,
      this.timeout = const Duration(seconds: 20),
      this.minInterval = const Duration(minutes: 5),
      DateTime Function()? clock})
      : _client = client ?? http.Client(),
        _now = clock ?? DateTime.now;
  final String baseUrl;
  final http.Client _client;
  final Duration timeout;
  final Duration minInterval;
  final DateTime Function() _now;
  final Map<Category, (DateTime, List<Question>)> _cache = {};

  @override
  String get name => 'الموجز';

  @override
  Future<List<Question>> fetch(Category category, int count,
      {required List<String> excludeFingerprints}) async {
    final cached = _cache[category];
    List<Question> all;
    if (cached != null && _now().difference(cached.$1) < minInterval) {
      all = cached.$2;
    } else {
      final uri = Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/${category.code}.json');
      final res = await _client.get(uri).timeout(timeout);
      if (res.statusCode == 404) {
        // Reachable, but the scheduled job has not published this section yet.
        _cache[category] = (_now(), const []);
        return const [];
      }
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      all = [
        for (final e in body['questions'] as List) Question.fromJson((e as Map).cast()),
      ];
      _cache[category] = (_now(), all);
    }
    final ex = excludeFingerprints.toSet();
    final fresh = all.where((q) => !ex.contains(q.semanticFingerprint)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return fresh.take(count).toList();
  }
}
