import 'dart:convert';
import 'dart:io';

import 'package:hhkkll_core/hhkkll_core.dart';

/// Key → JSON value persistence used by the whole app.
abstract class KeyValueStore {
  Future<Object?> read(String name);
  Future<void> write(String name, Object? value);
  Future<void> delete(String name);
}

/// In-memory store (tests). Values go through JSON so they behave exactly
/// like the file store; reusing the same [data] map simulates an app restart.
class MemoryStore implements KeyValueStore {
  MemoryStore([Map<String, String>? data]) : data = data ?? {};
  final Map<String, String> data;
  @override
  Future<Object?> read(String name) async => data[name] == null ? null : jsonDecode(data[name]!);
  @override
  Future<void> write(String name, Object? value) async => data[name] = jsonEncode(value);
  @override
  Future<void> delete(String name) async => data.remove(name);
}

/// Small JSON-file store in the app's private documents folder. Writes are
/// atomic (temp file + rename) so a crash never leaves a half-written match.
class JsonFiles implements KeyValueStore {
  JsonFiles(this.dir);
  final Directory dir;

  File _f(String name) => File('${dir.path}/$name.json');

  @override
  Future<Object?> read(String name) async {
    final f = _f(name);
    if (!await f.exists()) return null;
    try {
      return jsonDecode(await f.readAsString());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String name, Object? value) async {
    await dir.create(recursive: true);
    final tmp = File('${dir.path}/$name.json.tmp');
    await tmp.writeAsString(jsonEncode(value), flush: true);
    await tmp.rename(_f(name).path);
  }

  @override
  Future<void> delete(String name) async {
    final f = _f(name);
    if (await f.exists()) await f.delete();
  }
}

class FileQuestionCache implements QuestionCache {
  FileQuestionCache(this.files);
  final KeyValueStore files;

  @override
  Future<List<Question>> loadAll() async {
    final raw = await files.read('question_cache');
    if (raw is! List) return [];
    final out = <Question>[];
    for (final e in raw) {
      try {
        out.add(Question.fromJson((e as Map).cast()));
      } catch (_) {/* skip corrupt entry */}
    }
    return out;
  }

  @override
  Future<void> saveAll(List<Question> questions) =>
      files.write('question_cache', questions.map((q) => q.toJson()).toList());
}

class FileHistoryStore implements HistoryStore {
  FileHistoryStore(this.files);
  final KeyValueStore files;

  @override
  Future<List<DedupEntry>> load() async {
    final raw = await files.read('question_history');
    if (raw is! List) return [];
    return [
      for (final e in raw) DedupEntry.fromJson((e as Map).cast()),
    ];
  }

  @override
  Future<void> save(List<DedupEntry> entries) =>
      files.write('question_history', entries.map((e) => e.toJson()).toList());
}
