import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config.dart';
import '../data/repository.dart';

enum SyncState { idle, syncing, done, failed, offline }

class SyncReport {
  SyncReport({this.pushed = 0, this.pulled = 0, this.error});
  final int pushed;
  final int pulled;
  final String? error;
}

/// Supabase access: authentication, two-way sync, storage. Every method is a
/// no-op returning false/null when the backend is not configured, so the app
/// keeps working fully offline.
class Backend extends ChangeNotifier {
  // ignore: prefer_initializing_formals
  Backend(this.repo, {SupabaseClient? client}) : _client = client;

  final Repository repo;
  SupabaseClient? _client;
  StreamSubscription<AuthState>? _authSub;

  SyncState syncState = SyncState.idle;
  DateTime? lastSyncAt;
  String? lastError;
  bool suspended = false;

  static Future<void> initialize() async {
    if (!AppConfig.backendConfigured) return;
    await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseAnonKey);
  }

  bool get configured => _client != null || AppConfig.backendConfigured;
  SupabaseClient? get client {
    if (_client != null) return _client;
    if (!AppConfig.backendConfigured) return null;
    try {
      return _client = Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  User? get user => client?.auth.currentUser;
  bool get signedIn => user != null;
  bool get isAnonymous => user?.isAnonymous ?? false;

  void start() {
    final c = client;
    if (c == null) return;
    repo.userId = c.auth.currentUser?.id;
    final last = repo.kv('last_sync_at');
    lastSyncAt = last == null ? null : DateTime.tryParse(last);
    _authSub = c.auth.onAuthStateChange.listen((s) async {
      repo.userId = s.session?.user.id;
      if (s.event == AuthChangeEvent.signedIn) {
        await _adoptCloudUser(s.session!.user);
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _adoptCloudUser(User u) async {
    await repo.setKv('auth_mode', u.isAnonymous ? 'anonymous' : 'cloud');
    final prof = repo.profile;
    final meta = u.userMetadata ?? {};
    if (prof.displayName.trim().isEmpty) {
      prof.displayName = (meta['full_name'] ?? meta['name'] ?? '').toString();
    }
    prof.avatarUrl ??= meta['avatar_url']?.toString();
    await repo.saveProfile(prof);
    // Restore an existing cloud profile (reinstall / new phone).
    try {
      final sap = await client!.from('student_academic_profiles').select().eq('user_id', u.id).maybeSingle();
      if (sap != null && !repo.profile.complete) {
        final p = repo.profile
          ..stageId = sap['stage_id'] as String?
          ..gradeId = sap['grade_id'] as String?
          ..branchId = sap['branch_id'] as String?
          ..yearId = sap['year_id'] as String?
          ..governorate = sap['governorate'] as String?;
        await repo.saveProfile(p);
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Authentication
  // ---------------------------------------------------------------------------

  /// Opens Google sign-in in the browser; completion arrives via the
  /// com.enjaz.student://login-callback deep link and onAuthStateChange.
  Future<bool> signInWithGoogle() async {
    final c = client;
    if (c == null) return false;
    return c.auth.signInWithOAuth(OAuthProvider.google, redirectTo: AppConfig.oauthRedirect);
  }

  /// "Continue without an account": an anonymous Supabase session gives access
  /// to published content; data stays tied to this device. Falls back to a
  /// purely local mode when anonymous sign-in is disabled or offline.
  Future<bool> continueWithoutAccount() async {
    final c = client;
    if (c != null) {
      try {
        await c.auth.signInAnonymously();
        return true;
      } catch (_) {/* fall through to local mode */}
    }
    await repo.setKv('auth_mode', 'local');
    return false;
  }

  Future<void> signOut() async {
    if (signedIn) {
      await sync(); // don't lose unsynced work
      await client!.auth.signOut();
    }
    await repo.wipeAll();
    notifyListeners();
  }

  /// Marks the account for deletion and asks the server to delete it.
  Future<void> deleteAccount() async {
    final c = client;
    if (c != null && signedIn) {
      await c.rpc('request_account_deletion');
      await c.functions.invoke('delete-account');
      try {
        await c.auth.signOut();
      } catch (_) {}
    }
    await repo.wipeAll();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Sync
  // ---------------------------------------------------------------------------
  Future<SyncReport> sync({bool force = false}) async {
    final c = client;
    if (c == null || !signedIn) return SyncReport(error: 'not_signed_in');
    if (syncState == SyncState.syncing) return SyncReport(error: 'busy');
    final cloudEnabled = repo.preferences['cloud_sync_enabled'] != false;
    syncState = SyncState.syncing;
    lastError = null;
    notifyListeners();
    var pushed = 0, pulled = 0;
    try {
      final uid = user!.id;
      repo.userId = uid;
      await _checkSuspended(uid);
      if (cloudEnabled) {
        await _pushProfile(uid);
        pushed = await _push(uid);
        pulled += await _pullOwned(uid);
      }
      pulled += await _pullContent();
      await repo.reconcileProfileIds();
      try {
        await c.rpc('touch_last_seen');
      } catch (_) {}
      lastSyncAt = DateTime.now();
      await repo.setKv('last_sync_at', lastSyncAt!.toIso8601String());
      syncState = SyncState.done;
      return SyncReport(pushed: pushed, pulled: pulled);
    } on SocketException catch (e) {
      syncState = SyncState.offline;
      lastError = e.message;
      return SyncReport(error: 'offline');
    } catch (e) {
      final s = e.toString();
      syncState = s.contains('SocketException') || s.contains('Failed host lookup') ? SyncState.offline : SyncState.failed;
      lastError = s;
      return SyncReport(error: s);
    } finally {
      repo.notify();
      notifyListeners();
    }
  }

  Future<void> _checkSuspended(String uid) async {
    final p = await client!.from('profiles').select('status').eq('id', uid).maybeSingle();
    suspended = p?['status'] == 'suspended';
  }

  Future<void> _pushProfile(String uid) async {
    final p = repo.profile;
    if (!p.complete || p.gradeId!.startsWith('local-')) return;
    await client!.from('profiles').update({'display_name': p.displayName.trim(), 'avatar_url': p.avatarUrl}).eq('id', uid);
    await client!.from('student_academic_profiles').upsert({
      'user_id': uid, 'stage_id': p.stageId, 'grade_id': p.gradeId, 'branch_id': p.branchId,
      'year_id': (p.yearId?.startsWith('local-') ?? false) ? null : p.yearId, 'governorate': p.governorate,
    });
  }

  Future<int> _push(String uid) async {
    final dirty = await repo.db.dirtyRecords();
    final byTable = <String, List<Map<String, Object?>>>{};
    for (final r in dirty) {
      byTable.putIfAbsent(r['tbl'] as String, () => []).add(r);
    }
    var n = 0;
    for (final tbl in ownedTables) {
      final rows = byTable[tbl];
      if (rows == null) continue;
      final payload = <Map<String, dynamic>>[];
      for (final r in rows) {
        final m = Map<String, dynamic>.from(repo.record(tbl, r['id'] as String) ?? _decode(r['json'] as String));
        m['user_id'] = uid;
        if (tbl == 'user_preferences') m.remove('id');
        if (tbl == 'exams') m['is_official'] = false;
        payload.add(m);
      }
      await client!.from(tbl).upsert(payload, onConflict: tbl == 'user_preferences' ? 'user_id' : 'id');
      for (final r in rows) {
        await repo.db.markClean(tbl, r['id'] as String, r['client_modified_at'] as String);
      }
      n += rows.length;
    }
    return n;
  }

  Future<int> _pullOwned(String uid) async {
    final dirtyKeys = {for (final r in await repo.db.dirtyRecords()) '${r['tbl']}/${r['id']}'};
    var n = 0;
    for (final tbl in ownedTables) {
      final cursorKey = 'pull:$tbl';
      var cursor = repo.kv(cursorKey) ?? '1970-01-01T00:00:00Z';
      while (true) {
        final rows = await client!.from(tbl).select().eq('user_id', uid).gt('updated_at', cursor).order('updated_at').limit(500);
        for (final row in rows) {
          final m = Map<String, dynamic>.from(row);
          if (tbl == 'user_preferences') m['id'] = 'prefs';
          await repo.applyRemote(tbl, m, dirtyKeys: dirtyKeys);
          cursor = m['updated_at'] as String;
        }
        n += rows.length;
        if (rows.length < 500) break;
      }
      await repo.setKv(cursorKey, cursor);
    }
    return n;
  }

  /// Published content is refreshed completely (RLS already limits it to the
  /// student's grade/branch), so unpublished or deleted items disappear too.
  Future<int> _pullContent() async {
    var n = 0;
    for (final tbl in contentTables) {
      final rows = <Map<String, dynamic>>[];
      var from = 0;
      const page = 1000;
      while (true) {
        final List<Map<String, dynamic>> chunk = tbl == 'official_exams'
            ? await client!.from('exams').select().eq('is_official', true).range(from, from + page - 1)
            : await client!.from(tbl).select().range(from, from + page - 1);
        for (final r in chunk) {
          final m = Map<String, dynamic>.from(r);
          if (tbl == 'app_settings') m['id'] = m['key'];
          if (m['deleted_at'] == null) rows.add(m);
        }
        if (chunk.length < page) break;
        from += page;
      }
      await repo.replaceContent(tbl, rows);
      n += rows.length;
    }
    return n;
  }

  // ---------------------------------------------------------------------------
  // Storage
  // ---------------------------------------------------------------------------
  String? publicImageUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('https://')) return path;
    return client?.storage.from('content').getPublicUrl(path);
  }

  /// Downloads a library file for offline use; returns the local path.
  Future<String> downloadLibraryFile({required String fileId, required String storagePath, required String title,
      void Function(double)? onProgress}) async {
    final c = client;
    if (c == null || !signedIn) throw StateError('offline');
    final url = await c.storage.from('library').createSignedUrl(storagePath, 600);
    final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'library'));
    await dir.create(recursive: true);
    final ext = p.extension(storagePath).isEmpty ? '.pdf' : p.extension(storagePath);
    final dest = File(p.join(dir.path, '$fileId$ext'));
    final tmp = File('${dest.path}.part');
    final http = HttpClient();
    try {
      final req = await http.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) throw HttpException('status ${res.statusCode}');
      final total = res.contentLength;
      var got = 0;
      final sink = tmp.openWrite();
      await for (final chunk in res) {
        got += chunk.length;
        sink.add(chunk);
        if (total > 0) onProgress?.call(got / total);
      }
      await sink.close();
      await tmp.rename(dest.path);
    } finally {
      http.close(force: true);
    }
    await repo.putDownload({
      'file_id': fileId, 'local_path': dest.path, 'title': title,
      'downloaded_at': DateTime.now().toIso8601String(), 'favorite': 0,
    });
    try {
      await c.from('file_downloads').insert({'file_id': fileId, 'user_id': user!.id});
    } catch (_) {}
    return dest.path;
  }

  Future<void> markAnnouncementSeen(String id, {bool acknowledged = false}) async {
    final c = client;
    if (c == null || !signedIn) return;
    try {
      await c.rpc('mark_announcement_seen', params: {'p_id': id, 'p_ack': acknowledged});
    } catch (_) {}
  }

  Future<void> registerDeviceToken(String token, String appVersion) async {
    final c = client;
    if (c == null || !signedIn) return;
    try {
      await c.from('device_tokens').upsert(
          {'user_id': user!.id, 'token': token, 'platform': 'android', 'app_version': appVersion,
           'last_seen_at': DateTime.now().toUtc().toIso8601String()},
          onConflict: 'token');
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> exportCloudData() async {
    final c = client;
    if (c == null || !signedIn) return null;
    final r = await c.rpc('export_my_data');
    return (r as Map).cast<String, dynamic>();
  }
}

Map<String, dynamic> _decode(String s) => (jsonDecode(s) as Map).cast<String, dynamic>();
