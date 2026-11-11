import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// PBKDF2-HMAC-SHA256 password hashing. Stored format:
/// `pbkdf2-sha256$<iterations>$<salt b64>$<hash b64>`
class PasswordHasher {
  final int iterations;
  const PasswordHasher({this.iterations = 60000});

  Future<String> hash(String password) async {
    final rnd = Random.secure();
    final salt = List<int>.generate(16, (_) => rnd.nextInt(256));
    final h = await _derive(password, salt, iterations);
    return ['pbkdf2-sha256', '$iterations', base64Encode(salt), base64Encode(h)].join(r'$');
  }

  Future<bool> verify(String password, String stored) async {
    final parts = stored.split(r'$');
    if (parts.length != 4 || parts[0] != 'pbkdf2-sha256') return false;
    final it = int.tryParse(parts[1]);
    if (it == null || it < 1) return false;
    final salt = base64Decode(parts[2]);
    final expected = base64Decode(parts[3]);
    final actual = await _derive(password, salt, it);
    if (actual.length != expected.length) return false;
    var diff = 0;
    for (var i = 0; i < actual.length; i++) {
      diff |= actual[i] ^ expected[i];
    }
    return diff == 0;
  }

  static Future<List<int>> _derive(String password, List<int> salt, int iterations) async {
    final algo = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);
    final key = await algo.deriveKeyFromPassword(password: password, nonce: salt);
    return key.extractBytes();
  }
}
