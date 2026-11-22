import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// On-device SQLite store. Three kinds of data:
///  * records  - the student's own rows (mirrors server tables, synced both ways)
///  * content  - admin-published content cached for offline use (pulled only)
///  * kv       - small settings / sync cursors / local profile
///  * downloads- library files saved on the device
class LocalDb {
  LocalDb(this.db);
  final Database db;

  static const _version = 1;

  static Future<LocalDb> open({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), 'enjaz.db');
    final db = await f.openDatabase(dbPath,
        options: OpenDatabaseOptions(version: _version, onCreate: (db, v) async {
          await db.execute('''create table records (
              tbl text not null, id text not null, json text not null,
              client_modified_at text not null, dirty integer not null default 0,
              deleted integer not null default 0, primary key (tbl, id))''');
          await db.execute('create index records_dirty on records (dirty)');
          await db.execute('''create table content (
              tbl text not null, id text not null, json text not null, primary key (tbl, id))''');
          await db.execute('create table kv (key text primary key, value text not null)');
          await db.execute('''create table downloads (
              file_id text primary key, local_path text not null, title text,
              downloaded_at text not null, favorite integer not null default 0, last_opened_at text)''');
        }));
    return LocalDb(db);
  }

  // -- records ---------------------------------------------------------------
  Future<List<Map<String, Object?>>> allRecords() => db.query('records');

  Future<void> putRecord(String tbl, Map<String, dynamic> json, {required bool dirty}) => db.insert(
      'records',
      {
        'tbl': tbl,
        'id': json['id'] as String,
        'json': jsonEncode(json),
        'client_modified_at': json['client_modified_at'] as String? ?? DateTime.now().toUtc().toIso8601String(),
        'dirty': dirty ? 1 : 0,
        'deleted': json['deleted_at'] != null ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> markClean(String tbl, String id, String clientModifiedAt) => db.update(
      'records', {'dirty': 0},
      where: 'tbl = ? and id = ? and client_modified_at = ?', whereArgs: [tbl, id, clientModifiedAt]);

  Future<List<Map<String, Object?>>> dirtyRecords() => db.query('records', where: 'dirty = 1');

  // -- content ---------------------------------------------------------------
  Future<List<Map<String, Object?>>> allContent() => db.query('content');

  Future<void> replaceContent(String tbl, List<Map<String, dynamic>> rows) => db.transaction((tx) async {
        await tx.delete('content', where: 'tbl = ?', whereArgs: [tbl]);
        final batch = tx.batch();
        for (final r in rows) {
          batch.insert('content', {'tbl': tbl, 'id': r['id'].toString(), 'json': jsonEncode(r)},
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
      });

  // -- kv --------------------------------------------------------------------
  Future<Map<String, String>> allKv() async =>
      {for (final r in await db.query('kv')) r['key'] as String: r['value'] as String};

  Future<void> setKv(String key, String? value) => value == null
      ? db.delete('kv', where: 'key = ?', whereArgs: [key])
      : db.insert('kv', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);

  // -- downloads -------------------------------------------------------------
  Future<List<Map<String, Object?>>> allDownloads() => db.query('downloads');

  Future<void> putDownload(Map<String, Object?> row) =>
      db.insert('downloads', row, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> updateDownload(String fileId, Map<String, Object?> values) =>
      db.update('downloads', values, where: 'file_id = ?', whereArgs: [fileId]);

  Future<void> deleteDownload(String fileId) => db.delete('downloads', where: 'file_id = ?', whereArgs: [fileId]);

  /// Wipes everything (sign out of a synced account / account deletion).
  Future<void> wipe() => db.transaction((tx) async {
        for (final t in ['records', 'content', 'kv', 'downloads']) {
          await tx.delete(t);
        }
      });
}
