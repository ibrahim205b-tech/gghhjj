import 'dart:io';

import 'package:args/args.dart';
import 'package:generator_os_server/server.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:sqlite3/sqlite3.dart';

/// Usage:
///   ADMIN_TOKEN=... [LICENSE_SEED_B64=...] dart run bin/server.dart --port 8080 --db data/server.db
Future<void> main(List<String> args) async {
  final p = ArgParser()
    ..addOption('port', defaultsTo: Platform.environment['PORT'] ?? '8080')
    ..addOption('host', defaultsTo: '0.0.0.0')
    ..addOption('db', defaultsTo: 'data/server.db');
  final o = p.parse(args);
  final admin = Platform.environment['ADMIN_TOKEN'];
  if (admin == null || admin.length < 16) {
    stderr.writeln('ADMIN_TOKEN environment variable (16+ chars) is required.');
    exit(64);
  }
  final dbPath = o['db'] as String;
  File(dbPath).parent.createSync(recursive: true);
  final server = GeneratorOsServer(
      sqlite3.open(dbPath), ServerConfig(adminToken: admin, licenseSeedB64: Platform.environment['LICENSE_SEED_B64']));
  final s = await io.serve(server.handler, o['host'] as String, int.parse(o['port'] as String));
  stdout.writeln('Generator OS server listening on http://${s.address.host}:${s.port}');
}
