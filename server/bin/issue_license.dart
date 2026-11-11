import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:cryptography/cryptography.dart';
import 'package:generator_os_server/server.dart';

/// Offline licence tool for the vendor.
///
///   dart run bin/issue_license.dart keygen
///     -> prints a new private seed (keep secret!) and the public key list to
///        paste into the app build (--dart-define=LICENSE_PUBKEY=...).
///
///   LICENSE_SEED_B64=... dart run bin/issue_license.dart issue \
///       --customer "اسم العميل" --generators 2 --device INSTALLATION_CODE
Future<void> main(List<String> args) async {
  final p = ArgParser()
    ..addCommand('keygen')
    ..addCommand(
        'issue',
        ArgParser()
          ..addOption('customer', mandatory: true)
          ..addOption('generators', defaultsTo: '1')
          ..addMultiOption('device')
          ..addMultiOption('service', help: 'name=YYYY-MM-DD for optional paid services'));
  final o = p.parse(args);
  switch (o.command?.name) {
    case 'keygen':
      final r = Random.secure();
      final seed = List<int>.generate(32, (_) => r.nextInt(256));
      final kp = await Ed25519().newKeyPairFromSeed(seed);
      final pub = await kp.extractPublicKey();
      stdout.writeln('PRIVATE SEED (store in a password manager, never commit):');
      stdout.writeln(base64Encode(seed));
      stdout.writeln('PUBLIC KEY (base64, for --dart-define=LICENSE_PUBKEY):');
      stdout.writeln(base64Encode(pub.bytes));
    case 'issue':
      final seed = Platform.environment['LICENSE_SEED_B64'];
      if (seed == null) {
        stderr.writeln('Set LICENSE_SEED_B64.');
        exit(64);
      }
      final c = o.command!;
      final services = <String, String>{};
      for (final s in c['service'] as List<String>) {
        final i = s.indexOf('=');
        if (i > 0) services[s.substring(0, i)] = s.substring(i + 1);
      }
      final payload = {
        'license_id': 'L-${DateTime.now().millisecondsSinceEpoch}',
        'customer': c['customer'],
        'edition': 'perpetual',
        'max_generators': int.parse(c['generators'] as String),
        'device_ids': c['device'],
        'issued_at': DateTime.now().toIso8601String().substring(0, 10),
        'services': services,
      };
      stdout.writeln(await signLicense(payload, base64Decode(seed)));
    default:
      stdout.writeln(p.usage);
      stdout.writeln('commands: keygen | issue');
  }
}
