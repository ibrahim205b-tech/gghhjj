import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:generator_core/generator_core.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

/// Licence public key injected at build time:
/// `flutter build apk --dart-define=LICENSE_PUBKEY=BASE64_KEY`
const _licensePubKeyB64 = String.fromEnvironment('LICENSE_PUBKEY');

/// Application-wide state: the core engine, the logged-in session, the
/// selected generator and UI preferences.
class AppState extends ChangeNotifier {
  GeneratorOS os;
  final String dbPath;
  String? generatorId;
  ThemeMode themeMode = ThemeMode.system;
  bool initialized = false;
  int unreadAlerts = 0;
  Timer? _syncTimer;

  AppState._(this.os, this.dbPath);

  /// For widget tests: wraps an already-open engine.
  @visibleForTesting
  AppState.forTest(this.os) : dbPath = ':memory:' {
    initialized = true;
  }

  Session? get session => os.ctx.session;
  bool can(String perm) => os.ctx.can(perm);

  static Future<String> _deviceId(Directory dir) async {
    final f = File(p.join(dir.path, 'device_id'));
    if (await f.exists()) return (await f.readAsString()).trim();
    final id = newId();
    await f.writeAsString(id, flush: true);
    return id;
  }

  static List<int> _pubKey() {
    if (_licensePubKeyB64.isEmpty) return const [];
    try {
      return Uri.parse('data:;base64,$_licensePubKeyB64').data!.contentAsBytes();
    } catch (_) {
      return const [];
    }
  }

  static Future<AppState> boot() async {
    final docs = await getApplicationSupportDirectory();
    final dbDir = await sqflite.getDatabasesPath();
    final path = p.join(dbDir, 'generator_os.db');
    final db = await openGeneratorDatabase(sqflite.databaseFactory, path);
    final os = GeneratorOS(db, deviceId: await _deviceId(docs), licensePublicKey: _pubKey());
    final s = AppState._(os, path);
    s.initialized = await os.auth.isInitialized();
    final theme = await db.query('settings', where: "key = 'ui.theme'");
    if (theme.isNotEmpty) {
      s.themeMode = ThemeMode.values.firstWhere((m) => m.name == theme.first['value'], orElse: () => ThemeMode.system);
    }
    return s;
  }

  Future<void> setTheme(ThemeMode m) async {
    themeMode = m;
    await os.ctx.db.insert('settings', {
      'key': 'ui.theme',
      'value': m.name,
      'updated_at': os.ctx.nowIso,
    }, conflictAlgorithm: sqflite.ConflictAlgorithm.replace);
    notifyListeners();
  }

  Future<void> afterLogin() async {
    final gens = await os.network.listGenerators();
    final last = await os.ctx.db.query('settings', where: "key = 'ui.generator'");
    final lastId = last.isEmpty ? null : last.first['value'] as String?;
    generatorId = gens.any((g) => g['id'] == lastId) ? lastId : (gens.isEmpty ? null : gens.first['id'] as String);
    initialized = true;
    await refreshAlerts();
    _startAutoSync();
    notifyListeners();
  }

  Future<void> selectGenerator(String id) async {
    generatorId = id;
    await os.ctx.db.insert('settings', {
      'key': 'ui.generator',
      'value': id,
      'updated_at': os.ctx.nowIso,
    }, conflictAlgorithm: sqflite.ConflictAlgorithm.replace);
    await refreshAlerts();
    notifyListeners();
  }

  Future<void> refreshAlerts() async {
    final g = generatorId;
    if (g == null || session == null) return;
    try {
      unreadAlerts = await os.alerts.runChecks(g);
    } catch (_) {
      // Alerts must never block the app.
    }
    notifyListeners();
  }

  void _startAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      if (session == null) return;
      if (await os.sync.config() == null) return;
      await os.sync.syncNow();
      notifyListeners();
    });
  }

  Future<void> logout() async {
    _syncTimer?.cancel();
    await os.auth.logout();
    generatorId = null;
    notifyListeners();
  }

  /// Replaces the database with a restored backup (fresh file, then swap).
  Future<Map<String, int>> restoreBackup(List<int> bytes, String password) async {
    final snap = await BackupService.decrypt(bytes, password);
    final tmpPath = '$dbPath.restore';
    await sqflite.deleteDatabase(tmpPath);
    final fresh = await openGeneratorDatabase(sqflite.databaseFactory, tmpPath);
    final counts = await BackupService.restoreInto(fresh, snap);
    await fresh.close();
    _syncTimer?.cancel();
    final deviceId = os.ctx.deviceId;
    await os.ctx.db.close();
    final old = File(dbPath);
    final keep = File('$dbPath.before-restore');
    if (await keep.exists()) await keep.delete();
    await old.rename(keep.path);
    await File(tmpPath).rename(dbPath);
    final db = await openGeneratorDatabase(sqflite.databaseFactory, dbPath);
    os = GeneratorOS(db, deviceId: deviceId, licensePublicKey: _pubKey());
    generatorId = null;
    initialized = await os.auth.isInitialized();
    notifyListeners();
    return counts;
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }
}

/// Provides [AppState] to the widget tree.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
