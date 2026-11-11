import 'package:sqflite_common/sqlite_api.dart';

import 'ai/assistant.dart';
import 'security/password.dart';
import 'services/alert_service.dart';
import 'services/auth_service.dart';
import 'services/backup_service.dart';
import 'services/billing_service.dart';
import 'services/collection_service.dart';
import 'services/context.dart';
import 'services/finance_service.dart';
import 'services/fuel_service.dart';
import 'services/integration_service.dart';
import 'services/ledger_service.dart';
import 'services/license_service.dart';
import 'services/network_service.dart';
import 'services/operations_service.dart';
import 'services/report_service.dart';
import 'services/subscriber_service.dart';
import 'sync/sync_service.dart';
import 'util/clock.dart';
import 'package:http/http.dart' as http;

/// Developer licence-signing public key (Ed25519, raw 32 bytes). The matching
/// private key is NOT in this repository; see docs/LICENSING.md.
const defaultLicensePublicKey = <int>[];

/// Wires every service around one database. The Flutter app creates one
/// instance; tests create one per scenario.
class GeneratorOS {
  final CoreContext ctx;
  late final Store store = Store(ctx);
  late final AuditService audit = AuditService(ctx, store);
  late final LedgerService ledger = LedgerService(ctx, store);
  late final AuthService auth;
  late final LicenseService license;
  late final NetworkService network =
      NetworkService(ctx, store, audit, ledger, maxGenerators: license.maxGenerators);
  late final SubscriberService subscribers = SubscriberService(ctx, store, audit, ledger);
  late final BillingService billing = BillingService(ctx, store, audit, ledger);
  late final CollectionService collection = CollectionService(ctx, store, audit, ledger, subscribers, network);
  late final FinanceService finance = FinanceService(ctx, store, audit, ledger, network);
  late final FuelService fuel = FuelService(ctx, store, audit, ledger, network);
  late final OperationsService operations = OperationsService(ctx, store, audit, finance);
  late final ComplaintService complaints = ComplaintService(ctx, store, audit);
  late final ReportService reports = ReportService(ctx, ledger, subscribers);
  late final AlertService alerts = AlertService(ctx, fuel, operations, network, reports);
  late final IntegrationService integration = IntegrationService(ctx, store, audit);
  late final BackupService backup;
  late final SyncService sync;
  late final GeneratorAssistant assistant =
      GeneratorAssistant(ctx, reports, fuel, collection, operations, subscribers);

  GeneratorOS(
    Database db, {
    required String deviceId,
    Clock clock = const SystemClock(),
    PasswordHasher hasher = const PasswordHasher(),
    List<int> licensePublicKey = defaultLicensePublicKey,
    int backupKdfIterations = 100000,
    http.Client? httpClient,
  }) : ctx = CoreContext(db: db, deviceId: deviceId, clock: clock) {
    auth = AuthService(ctx, store, audit, hasher: hasher);
    license = LicenseService(ctx, licensePublicKey);
    backup = BackupService(ctx, audit, kdfIterations: backupKdfIterations);
    sync = SyncService(ctx, client: httpClient);
  }
}
