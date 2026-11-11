import '../security/permissions.dart';
import '../util/errors.dart';
import '../util/ids.dart';
import 'context.dart';

/// Metrics a generator controller may report.
class SensorMetric {
  static const voltage = 'voltage';
  static const frequency = 'frequency';
  static const engineTemp = 'engine_temp';
  static const oilPressure = 'oil_pressure';
  static const runHours = 'run_hours';
  static const fuelLevel = 'fuel_level_ml';
  static const running = 'running';
  static const faultCode = 'fault_code';
  static const labels = {
    voltage: 'الفولتية (V)',
    frequency: 'التردد (Hz)',
    engineTemp: 'حرارة المحرك (°C)',
    oilPressure: 'ضغط الزيت (bar)',
    runHours: 'ساعات التشغيل',
    fuelLevel: 'مستوى الوقود (مل)',
    running: 'حالة التشغيل',
    faultCode: 'رمز العطل',
  };
}

/// A transport that talks to real hardware (MQTT broker, Modbus TCP gateway,
/// vendor cloud...). Implementations live outside the core and are only
/// enabled after a successful connection test with a real device.
abstract class DeviceAdapter {
  String get protocol;
  Future<bool> testConnection(String endpoint);
  Stream<({String metric, double value, DateTime at})> readings(String endpoint);
}

/// Registry of monitoring devices and storage of their readings. The app never
/// creates readings by itself: they only come from an adapter or the server
/// telemetry API.
class IntegrationService {
  final CoreContext ctx;
  final Store store;
  final AuditService audit;
  IntegrationService(this.ctx, this.store, this.audit);

  static const protocols = {'mqtt': 'MQTT', 'modbus_tcp': 'Modbus TCP', 'http': 'HTTP API'};

  Future<String> registerDevice(String generatorId, String name, String protocol, {String? endpoint}) async {
    ctx.require(Perm.settingsManage);
    ctx.requireGenerator(generatorId);
    if (!protocols.containsKey(protocol)) throw validation('بروتوكول غير مدعوم.');
    final id = newId();
    await ctx.db.transaction((t) async {
      await store.insert(t, 'iot_devices',
          {'id': id, 'generator_id': generatorId, 'name': name.trim(), 'protocol': protocol, 'endpoint': endpoint});
      await audit.log(t, 'iot.register', entity: 'iot_devices', entityId: id, generatorId: generatorId);
    });
    return id;
  }

  Future<List<Map<String, Object?>>> devices(String generatorId) =>
      ctx.db.query('iot_devices', where: 'generator_id = ? AND active = 1', whereArgs: [generatorId]);

  /// Stores a reading delivered by a real adapter.
  Future<void> ingest(String deviceId, String metric, double value, DateTime at) async {
    final d = await ctx.db.query('iot_devices', where: 'id = ?', whereArgs: [deviceId]);
    if (d.isEmpty) throw const DomainException('NOT_FOUND', 'الجهاز غير مسجل.');
    if (!SensorMetric.labels.containsKey(metric)) throw validation('قياس غير معروف: $metric');
    await ctx.db.transaction((t) async {
      await store.insert(t, 'sensor_readings', {
        'id': newId(), 'generator_id': d.first['generator_id'], 'device_id': deviceId,
        'at': at.toIso8601String(), 'metric': metric, 'value': value,
      });
      await store.update(t, 'iot_devices', deviceId, {'last_seen': at.toIso8601String()});
    });
  }

  Future<List<Map<String, Object?>>> readings(String generatorId, {String? metric, int limit = 500}) =>
      ctx.db.query('sensor_readings',
          where: 'generator_id = ? ${metric != null ? 'AND metric = ?' : ''}',
          whereArgs: [generatorId, if (metric != null) metric],
          orderBy: 'at DESC',
          limit: limit);
}
