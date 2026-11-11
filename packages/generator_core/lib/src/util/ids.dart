import 'dart:math';

import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Random globally-unique id for records created on this device.
String newId() => _uuid.v4();

final _rand = Random.secure();

/// Short human-friendly random token (used for QR codes / receipt suffixes).
String randomToken([int length = 10]) {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  return List.generate(length, (_) => chars[_rand.nextInt(chars.length)]).join();
}
