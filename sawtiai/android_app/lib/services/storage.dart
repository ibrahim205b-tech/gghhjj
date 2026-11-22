import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

/// Secret storage abstraction (Android Keystore-backed in the app,
/// in-memory in tests).
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureSecretStore implements SecretStore {
  final _s = const FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

class MemorySecretStore implements SecretStore {
  final Map<String, String> _m = {};
  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String value) async => _m[key] = value;
  @override
  Future<void> delete(String key) async => _m.remove(key);
}

/// Server URL can be pre-filled at build time (not a secret):
///   flutter build apk --dart-define=SAWTI_DEFAULT_SERVER_URL=https://...
const kDefaultServerUrl = String.fromEnvironment('SAWTI_DEFAULT_SERVER_URL');

class AppSettings {
  String serverUrl;
  String apiKey;
  ThemeMode themeMode;
  String language;
  double speed;
  String? style;
  String? quality;
  String downloadFormat; // wav | mp3
  bool deleteFromServerAfterDownload;

  AppSettings({
    this.serverUrl = kDefaultServerUrl,
    this.apiKey = '',
    this.themeMode = ThemeMode.dark,
    this.language = 'ar',
    this.speed = 1.0,
    this.style,
    this.quality,
    this.downloadFormat = 'wav',
    this.deleteFromServerAfterDownload = true,
  });

  bool get serverConfigured => serverUrl.trim().isNotEmpty && apiKey.trim().isNotEmpty;
}

class SettingsStore {
  SettingsStore({SecretStore? secrets}) : _secrets = secrets ?? SecureSecretStore();
  final SecretStore _secrets;
  static const _kApiKey = 'sawti_api_key';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    String? key;
    try {
      key = await _secrets.read(_kApiKey);
    } catch (_) {
      key = null; // corrupted keystore entry -> ask again
    }
    return AppSettings(
      serverUrl: prefs.getString('server_url') ?? kDefaultServerUrl,
      apiKey: key ?? '',
      themeMode: ThemeMode.values.firstWhere((m) => m.name == prefs.getString('theme_mode'),
          orElse: () => ThemeMode.dark),
      language: prefs.getString('language') ?? 'ar',
      speed: prefs.getDouble('speed') ?? 1.0,
      style: prefs.getString('style'),
      quality: prefs.getString('quality'),
      downloadFormat: prefs.getString('download_format') ?? 'wav',
      deleteFromServerAfterDownload: prefs.getBool('delete_after_download') ?? true,
    );
  }

  Future<void> save(AppSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', s.serverUrl.trim());
    await prefs.setString('theme_mode', s.themeMode.name);
    await prefs.setString('language', s.language);
    await prefs.setDouble('speed', s.speed);
    if (s.style == null) {
      await prefs.remove('style');
    } else {
      await prefs.setString('style', s.style!);
    }
    if (s.quality == null) {
      await prefs.remove('quality');
    } else {
      await prefs.setString('quality', s.quality!);
    }
    await prefs.setString('download_format', s.downloadFormat);
    await prefs.setBool('delete_after_download', s.deleteFromServerAfterDownload);
    if (s.apiKey.trim().isEmpty) {
      await _secrets.delete(_kApiKey);
    } else {
      await _secrets.write(_kApiKey, s.apiKey.trim());
    }
  }
}

/// Resolves private app directories (overridable in tests).
class AppDirs {
  // ignore: prefer_initializing_formals
  AppDirs({Directory? root}) : _root = root;
  Directory? _root;

  Future<Directory> root() async => _root ??= await getApplicationSupportDirectory();

  Future<Directory> sub(String name) async {
    final d = Directory(p.join((await root()).path, name));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<Directory> temp() async => sub('tmp');
}

/// Writes JSON atomically (write temp + rename) so a crash never corrupts data.
Future<void> writeJsonAtomic(File f, Object data) async {
  final tmp = File('${f.path}.tmp');
  await tmp.writeAsString(jsonEncode(data), flush: true);
  await tmp.rename(f.path);
}

class VoiceRepository {
  VoiceRepository(this.dirs);
  final AppDirs dirs;

  Future<File> _index() async => File(p.join((await dirs.sub('voices')).path, 'voices.json'));

  Future<List<LocalVoice>> load() async {
    final f = await _index();
    if (!await f.exists()) return [];
    try {
      final list = jsonDecode(await f.readAsString()) as List;
      return list.map((e) => LocalVoice.fromJson((e as Map).cast<String, dynamic>())).toList();
    } catch (e) {
      debugPrint('voices.json unreadable: $e');
      return [];
    }
  }

  Future<void> save(List<LocalVoice> voices) async => writeJsonAtomic(await _index(), voices.map((v) => v.toJson()).toList());

  /// Copies a sample into private storage and returns the new path.
  Future<String> storeSample(String id, String sourcePath) async {
    final ext = p.extension(sourcePath).isEmpty ? '.wav' : p.extension(sourcePath).toLowerCase();
    final dst = p.join((await dirs.sub('voices')).path, 'sample_$id$ext');
    await File(sourcePath).copy(dst);
    return dst;
  }

  Future<void> deleteSample(LocalVoice v) async {
    final f = File(v.samplePath);
    if (await f.exists()) await f.delete();
  }
}

class LibraryRepository {
  LibraryRepository(this.dirs);
  final AppDirs dirs;

  Future<Directory> audioDir() => dirs.sub('library');
  Future<File> _index() async => File(p.join((await audioDir()).path, 'library.json'));

  Future<List<LibraryItem>> load() async {
    final f = await _index();
    if (!await f.exists()) return [];
    try {
      final list = jsonDecode(await f.readAsString()) as List;
      final items = list.map((e) => LibraryItem.fromJson((e as Map).cast<String, dynamic>())).toList();
      // Drop entries whose file disappeared.
      return [for (final i in items) if (File(i.filePath).existsSync()) i]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e) {
      debugPrint('library.json unreadable: $e');
      return [];
    }
  }

  Future<void> save(List<LibraryItem> items) async => writeJsonAtomic(await _index(), items.map((i) => i.toJson()).toList());

  Future<String> newFilePath(String id, String ext) async => p.join((await audioDir()).path, '$id.$ext');

  Future<void> deleteFile(LibraryItem i) async {
    final f = File(i.filePath);
    if (await f.exists()) await f.delete();
  }

  Future<int> deleteAll() async {
    final d = await audioDir();
    var n = 0;
    await for (final e in d.list()) {
      await e.delete(recursive: true);
      n++;
    }
    return n;
  }
}
