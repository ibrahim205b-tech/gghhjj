import 'package:sqflite_common/sqlite_api.dart';

import 'schema.dart';

/// Applies pending migrations inside a transaction per version.
Future<void> migrate(Database db) async {
  await db.execute('PRAGMA foreign_keys = ON');
  final current = await db.getVersion();
  for (final m in migrations.where((m) => m.version > current)) {
    await db.transaction((txn) async {
      for (final s in m.statements) {
        await txn.execute(s);
      }
    });
    await db.setVersion(m.version);
  }
}

/// Opens (or creates) the database using the supplied factory. The Flutter
/// app passes `databaseFactory` from sqflite; tests pass the FFI factory.
Future<Database> openGeneratorDatabase(DatabaseFactory factory, String path) async {
  final db = await factory.openDatabase(path,
      options: OpenDatabaseOptions(
        singleInstance: false,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      ));
  await migrate(db);
  return db;
}
