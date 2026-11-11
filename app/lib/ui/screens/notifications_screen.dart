import 'package:flutter/material.dart';
import 'package:generator_core/generator_core.dart';

import '../../app_state.dart';
import '../../theme.dart';
import '../common.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  int _rev = 0;

  IconData _icon(String kind) => switch (kind) {
    AlertKind.fuelLow || AlertKind.fuelAnomaly => Icons.local_gas_station,
    AlertKind.maintenance => Icons.build,
    AlertKind.overload => Icons.electric_bolt,
    AlertKind.syncStalled => Icons.sync_problem,
    AlertKind.cashDifference => Icons.account_balance_wallet,
    AlertKind.collectorLate => Icons.badge,
    AlertKind.security => Icons.shield,
    AlertKind.complaint => Icons.forum,
    _ => Icons.notifications,
  };

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final g = app.generatorId;
    return Loader<List<Map<String, Object?>>>(
      key: ValueKey(_rev),
      load: () async {
        await app.refreshAlerts();
        return app.os.alerts.list(g);
      },
      builder: (context, rows, _) => PageBody(
        children: [
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.done_all),
                label: const Text('تعليم الكل كمقروء'),
                onPressed: () async {
                  await app.os.alerts.markAllRead(g);
                  await app.refreshAlerts();
                  setState(() => _rev++);
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.tune),
                label: const Text('تخصيص التنبيهات'),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _AlertPrefs())),
              ),
            ],
          ),
          if (rows.isEmpty) const EmptyState(icon: Icons.notifications_off, title: 'لا توجد تنبيهات'),
          for (final n in rows)
            Card(
              child: ListTile(
                leading: Icon(
                  _icon(n['kind'] as String),
                  color: n['severity'] == 'high' ? Brand.danger : Brand.warning,
                ),
                title: Text(
                  '${n['title']}',
                  style: TextStyle(fontWeight: n['read'] == 0 ? FontWeight.w700 : FontWeight.normal),
                ),
                subtitle: Text(
                  '${n['body'] ?? ''}\n${(n['created_at'] as String).substring(0, 16).replaceFirst('T', ' ')}',
                ),
                isThreeLine: true,
                onTap: () async {
                  await app.os.alerts.markRead(n['id'] as String);
                  setState(() => _rev++);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _AlertPrefs extends StatefulWidget {
  const _AlertPrefs();
  @override
  State<_AlertPrefs> createState() => _AlertPrefsState();
}

class _AlertPrefsState extends State<_AlertPrefs> {
  int _rev = 0;
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('تخصيص التنبيهات')),
      body: Loader<(Map<String, bool>, int, int)>(
        key: ValueKey(_rev),
        load: () async => (
          {for (final k in AlertKind.labels.keys) k: await app.os.alerts.enabled(k)},
          await app.os.alerts.setting('alert.debt_limit', 100000),
          await app.os.alerts.setting('alert.handover_days', 2),
        ),
        builder: (context, d, _) => ListView(
          padding: const EdgeInsets.all(12),
          children: [
            for (final e in AlertKind.labels.entries)
              SwitchListTile(
                title: Text(e.value),
                value: d.$1[e.key]!,
                onChanged: (v) async {
                  await app.os.alerts.setEnabled(e.key, v);
                  setState(() => _rev++);
                },
              ),
            const Divider(),
            ListTile(
              title: const Text('حد الدين للتنبيه'),
              trailing: Text(money(d.$2)),
              onTap: () => _edit(context, app, 'alert.debt_limit', 'حد الدين', d.$2),
            ),
            ListTile(
              title: const Text('أيام تأخر تسليم الجابي'),
              trailing: Text('${d.$3} يوم'),
              onTap: () => _edit(context, app, 'alert.handover_days', 'عدد الأيام', d.$3),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, AppState app, String key, String label, int current) async {
    final v = await showFormDialog(
      context,
      title: label,
      fields: [FieldSpec('v', label, type: FieldType.money, required: true, initial: '$current')],
    );
    if (v == null) return;
    await app.os.ctx.db.rawInsert('INSERT OR REPLACE INTO settings(key, value, updated_at) VALUES(?,?,?)', [
      key,
      v['v'],
      app.os.ctx.nowIso,
    ]);
    setState(() => _rev++);
  }
}
