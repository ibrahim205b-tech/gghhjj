import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../util/errors.dart';
import 'context.dart';

/// Perpetual licence.
///
/// * A licence is a JSON payload signed with the developer's Ed25519 private
///   key (kept off the app, see `server/bin/issue_license.dart`). The app only
///   embeds the public key, so a licence cannot be forged.
/// * Usage rights have **no expiry date**. Optional services (cloud hosting,
///   AI, SMS, device integration, support) carry their own dates and never
///   affect access to local data or core features.
/// * Without a licence the app keeps working with one generator; data is
///   never locked.
class License {
  final String licenseId;
  final String customer;
  final String edition;
  final int maxGenerators;
  final List<String> deviceIds;
  final String issuedAt;
  final Map<String, String> services; // service -> valid-until (YYYY-MM-DD)
  const License({
    required this.licenseId,
    required this.customer,
    required this.edition,
    required this.maxGenerators,
    required this.deviceIds,
    required this.issuedAt,
    required this.services,
  });

  factory License.fromJson(Map<String, dynamic> j) => License(
        licenseId: j['license_id'] as String,
        customer: j['customer'] as String,
        edition: j['edition'] as String? ?? 'perpetual',
        maxGenerators: j['max_generators'] as int,
        deviceIds: (j['device_ids'] as List? ?? const []).cast<String>(),
        issuedAt: j['issued_at'] as String,
        services: (j['services'] as Map? ?? const {}).map((k, v) => MapEntry(k as String, v as String)),
      );

  bool serviceActive(String service, String today) {
    final until = services[service];
    return until != null && until.compareTo(today) >= 0;
  }
}

class LicenseStatus {
  final License? license;
  final String? problem;
  const LicenseStatus(this.license, this.problem);
  bool get licensed => license != null;
  int get maxGenerators => license?.maxGenerators ?? 1;
}

class LicenseService {
  final CoreContext ctx;
  final List<int> publicKey;
  LicenseService(this.ctx, this.publicKey);

  static const freeGenerators = 1;

  /// Licence key format: base64url(payloadJson) + '.' + base64url(signature)
  Future<License> verify(String key) async {
    final parts = key.trim().split('.');
    if (parts.length != 2) throw const DomainException('BAD_LICENSE', 'صيغة مفتاح الترخيص غير صحيحة.');
    final List<int> payload, sig;
    try {
      payload = base64Url.decode(base64Url.normalize(parts[0]));
      sig = base64Url.decode(base64Url.normalize(parts[1]));
    } catch (_) {
      throw const DomainException('BAD_LICENSE', 'صيغة مفتاح الترخيص غير صحيحة.');
    }
    final ok = await Ed25519().verify(payload,
        signature: Signature(sig, publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519)));
    if (!ok) throw const DomainException('BAD_LICENSE', 'توقيع الترخيص غير صالح.');
    final lic = License.fromJson(jsonDecode(utf8.decode(payload)) as Map<String, dynamic>);
    if (lic.deviceIds.isNotEmpty && !lic.deviceIds.contains(ctx.deviceId)) {
      throw const DomainException('LICENSE_DEVICE', 'هذا الترخيص صادر لجهاز آخر. لنقل الترخيص تواصل مع الدعم.');
    }
    return lic;
  }

  Future<License> activate(String key) async {
    final lic = await verify(key);
    await ctx.db.insert('settings', {'key': 'license.key', 'value': key.trim(), 'updated_at': ctx.nowIso},
        conflictAlgorithm: ConflictAlgorithm.replace);
    return lic;
  }

  Future<LicenseStatus> status() async {
    final r = await ctx.db.query('settings', where: "key = 'license.key'");
    if (r.isEmpty) return const LicenseStatus(null, null);
    try {
      return LicenseStatus(await verify(r.first['value'] as String), null);
    } on DomainException catch (e) {
      return LicenseStatus(null, e.message);
    }
  }

  Future<int> maxGenerators() async {
    final s = await status();
    return s.licensed ? s.maxGenerators : freeGenerators;
  }

  /// Installation code the customer sends to the vendor to get a
  /// device-bound licence.
  String installationCode() => ctx.deviceId;
}
