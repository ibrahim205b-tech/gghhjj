import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:generator_core/generator_core.dart';

import '../../app_state.dart';
import '../../services/export_service.dart';
import '../../services/pdf_service.dart';
import '../../theme.dart';
import '../common.dart';
import '../payment_flow.dart';
import 'auth_screens.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _rev = 0;
  void _r() => setState(() => _rev++);

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return PageBody(
      children: [
        Section(
          title: 'المظهر',
          child: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('تلقائي'), icon: Icon(Icons.brightness_auto)),
              ButtonSegment(value: ThemeMode.light, label: Text('نهاري'), icon: Icon(Icons.light_mode)),
              ButtonSegment(value: ThemeMode.dark, label: Text('ليلي'), icon: Icon(Icons.dark_mode)),
            ],
            selected: {app.themeMode},
            onSelectionChanged: (s) => app.setTheme(s.first),
          ),
        ),
        if (app.can(Perm.generatorsManage)) _generators(context, app),
        _sync(context, app),
        _printing(context, app),
        if (app.can(Perm.backupManage)) _backup(context, app),
        _license(context, app),
        if (app.can(Perm.settingsManage)) _iot(context, app),
        Section(
          title: 'الحساب والأمان',
          child: Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.password),
                title: const Text('تغيير كلمة المرور'),
                onTap: () async {
                  final v = await showFormDialog(
                    context,
                    title: 'تغيير كلمة المرور',
                    fields: const [
                      FieldSpec('old', 'كلمة المرور الحالية', type: FieldType.password, required: true),
                      FieldSpec('new', 'كلمة المرور الجديدة', type: FieldType.password, required: true),
                    ],
                  );
                  if (v == null || !context.mounted) return;
                  await guard(context, () => app.os.auth.changePassword(v['old']!, v['new']!), success: 'تم التغيير');
                },
              ),
              if (app.can(Perm.auditView))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.policy),
                  title: const Text('سجل التدقيق (Audit Log)'),
                  subtitle: const Text('للقراءة فقط — لا يمكن حذفه'),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AuditScreen())),
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.logout, color: Brand.danger),
                title: const Text('تسجيل الخروج'),
                onTap: app.logout,
              ),
            ],
          ),
        ),
        const Section(
          title: 'حول',
          child: Text(
            'Generator OS 1.0 — نظام إدارة وتشغيل المولدات الأهلية.\n'
            'يعمل دون إنترنت؛ المزامنة والخدمات السحابية اختيارية ولا تؤثر على الوصول للبيانات المحلية.\n'
            'الخطوط: Noto Kufi/Naskh Arabic (SIL Open Font License).',
          ),
        ),
      ],
    );
  }

  Widget _generators(BuildContext context, AppState app) {
    return Loader<List<Map<String, Object?>>>(
      key: ValueKey('g$_rev'),
      load: () => app.os.network.listGenerators(includeInactive: true),
      builder: (context, gens, _) => Section(
        title: 'المولدات',
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'مولدة جديدة',
            onPressed: () async {
              final v = await showFormDialog(context, title: 'مولدة جديدة', fields: _genFields(null));
              if (v == null || !context.mounted) return;
              await guard(
                context,
                () => app.os.network.createGenerator(
                  name: v['name']!,
                  code: emptyToNull(v['code']),
                  capacityKva: parseMoney(v['kva']),
                  province: emptyToNull(v['province']),
                  address: emptyToNull(v['address']),
                  defaultAmpPrice: parseMoney(v['price']) ?? 0,
                  fuelLowThresholdLiters: parseMoney(v['fuel']) ?? 200,
                ),
                success: 'تمت إضافة المولدة',
              );
              _r();
            },
          ),
        ],
        child: Column(
          children: [
            for (final g in gens)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.bolt, color: g['active'] == 1 ? Brand.accent : Colors.grey),
                title: Text('${g['name']}'),
                subtitle: Text(
                  'سعر الأمبير ${money(g['default_amp_price'] as int)} · تنبيه الكاز عند '
                  '${liters(g['fuel_low_threshold_ml'] as int)}${g['capacity_kva'] != null ? ' · ${g['capacity_kva']} KVA' : ''}',
                ),
                trailing: const Icon(Icons.edit),
                onTap: () async {
                  final v = await showFormDialog(context, title: 'تعديل المولدة', fields: _genFields(g));
                  if (v == null || !context.mounted) return;
                  await guard(
                    context,
                    () => app.os.network.updateGenerator(g['id'] as String, {
                      'name': v['name'],
                      'code': emptyToNull(v['code']),
                      'capacity_kva': parseMoney(v['kva']),
                      'province': emptyToNull(v['province']),
                      'address': emptyToNull(v['address']),
                      'default_amp_price': parseMoney(v['price']) ?? 0,
                      'fuel_low_threshold_ml': (parseMoney(v['fuel']) ?? 200) * 1000,
                    }),
                  );
                  _r();
                },
              ),
          ],
        ),
      ),
    );
  }

  List<FieldSpec> _genFields(Map<String, Object?>? g) => [
    FieldSpec('name', 'الاسم', required: true, initial: g?['name'] as String?),
    FieldSpec('code', 'الرمز', initial: g?['code'] as String?),
    FieldSpec('kva', 'القدرة KVA', type: FieldType.number, initial: g?['capacity_kva']?.toString()),
    FieldSpec('province', 'المحافظة', initial: g?['province'] as String?),
    FieldSpec('address', 'العنوان', initial: g?['address'] as String?),
    FieldSpec('price', 'سعر الأمبير الافتراضي', type: FieldType.money, initial: g?['default_amp_price']?.toString()),
    FieldSpec(
      'fuel',
      'تنبيه انخفاض الكاز (لتر)',
      type: FieldType.number,
      initial: g == null ? '200' : '${(g['fuel_low_threshold_ml'] as int) ~/ 1000}',
    ),
  ];

  Widget _sync(BuildContext context, AppState app) {
    return Loader<(SyncConfig?, int, String?, List<Map<String, Object?>>, List<Map<String, Object?>>)>(
      key: ValueKey('s$_rev'),
      load: () async => (
        await app.os.sync.config(),
        await app.os.sync.pendingCount(),
        await app.os.sync.lastSuccess(),
        await app.os.sync.log(limit: 5),
        await app.os.sync.conflicts(limit: 20),
      ),
      builder: (context, d, _) {
        final (cfg, pending, last, log, conflicts) = d;
        return Section(
          title: 'المزامنة مع الخادم',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                cfg == null
                    ? 'غير مفعلة. التطبيق يعمل بالكامل على هذا الجهاز. لمزامنة عدة أجهزة اربط الجهاز بخادم Generator OS.'
                    : 'الخادم: ${cfg.serverUrl}\nآخر مزامنة ناجحة: ${last == null ? 'لم تتم بعد' : last.substring(0, 16).replaceFirst('T', ' ')}\n'
                          'عمليات بانتظار الرفع: $pending',
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (cfg != null)
                    FilledButton.icon(
                      icon: const Icon(Icons.sync),
                      label: const Text('مزامنة الآن'),
                      onPressed: () async {
                        final r = await app.os.sync.syncNow();
                        if (!context.mounted) return;
                        r.ok
                            ? showOk(
                                context,
                                'تمت المزامنة: رفع ${r.pushed}، تنزيل ${r.pulled}${r.conflicts > 0 ? '، تعارضات ${r.conflicts}' : ''}',
                              )
                            : showError(context, DomainException('SYNC', r.error!));
                        _r();
                      },
                    ),
                  if (app.can(Perm.settingsManage))
                    OutlinedButton.icon(
                      icon: const Icon(Icons.link),
                      label: Text(cfg == null ? 'ربط بخادم' : 'إعادة الربط'),
                      onPressed: () async {
                        final v = await showFormDialog(
                          context,
                          title: 'ربط الجهاز بالخادم',
                          fields: [
                            FieldSpec('url', 'عنوان الخادم', required: true, initial: cfg?.serverUrl ?? 'https://'),
                            const FieldSpec('code', 'رمز المؤسسة (Tenant code)', required: true),
                            const FieldSpec('secret', 'رمز الربط', type: FieldType.password, required: true),
                          ],
                        );
                        if (v == null || !context.mounted) return;
                        await guard(
                          context,
                          () => app.os.sync.pair(
                            serverUrl: v['url']!,
                            tenantCode: v['code']!,
                            pairingSecret: v['secret']!,
                          ),
                          success: 'تم ربط الجهاز',
                        );
                        _r();
                      },
                    ),
                ],
              ),
              if (log.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final l in log)
                  Text(
                    '${l['ok'] == 1 ? '✔' : '✖'} ${(l['at'] as String).substring(0, 16).replaceFirst('T', ' ')} '
                    '${l['direction']} (${l['count']})${l['message'] != null ? ' — ${l['message']}' : ''}',
                    style: TextStyle(fontSize: 12, color: l['ok'] == 1 ? null : Brand.danger),
                  ),
              ],
              if (conflicts.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'تعارضات مسجلة: ${conflicts.length} (آخرها ${conflicts.first['table_name']} — ${conflicts.first['resolution']})',
                  style: const TextStyle(color: Brand.warning),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _printing(BuildContext context, AppState app) {
    return Loader<PrintPrefs>(
      key: ValueKey('p$_rev'),
      load: () => PrintPrefs.load(app),
      builder: (context, p, _) => Section(
        title: 'الطباعة',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<PaperSize>(
              isExpanded: true,
              initialValue: p.paper,
              decoration: const InputDecoration(labelText: 'مقاس الورق للوصولات والفواتير'),
              items: [for (final s in PaperSize.values) DropdownMenuItem(value: s, child: Text(s.label))],
              onChanged: (v) async {
                await PrintPrefs.save(app, paper: v);
                _r();
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.print),
              title: Text(p.target.label),
              subtitle: const Text(
                'خدمة الطباعة في أندرويد تدعم الطابعات التي لها إضافة طباعة. '
                'الطابعة الحرارية الشبكية تُرسل الوصل كصورة لضمان العربية (لم تُختبر بعد على طابعة فعلية).',
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () async {
                    await PrintPrefs.save(app, target: 'system');
                    _r();
                  },
                  child: const Text('خدمة أندرويد'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    final v = await showFormDialog(
                      context,
                      title: 'طابعة حرارية شبكية',
                      fields: const [
                        FieldSpec('host', 'عنوان IP', required: true, hint: '192.168.1.50'),
                        FieldSpec('port', 'المنفذ', type: FieldType.number, initial: '9100'),
                      ],
                    );
                    if (v == null) return;
                    await PrintPrefs.save(
                      app,
                      target: 'escpos:${v['host']}:${v['port']!.isEmpty ? '9100' : v['port']}',
                    );
                    _r();
                  },
                  child: const Text('طابعة حرارية شبكية'),
                ),
                OutlinedButton(
                  onPressed: () => printOrShare(
                    context,
                    (paper) => PdfService.table(
                      'اختبار الطباعة',
                      'Generator OS — طباعة عربية من اليمين لليسار',
                      ['البند', 'القيمة'],
                      [
                        ['الاسم', 'تجربة طباعة'],
                        ['المبلغ', money(25000)],
                      ],
                    ),
                    'test',
                  ),
                  child: const Text('صفحة اختبار'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _backup(BuildContext context, AppState app) {
    return Loader<List<Map<String, Object?>>>(
      key: ValueKey('b$_rev'),
      load: () => app.os.ctx.db.query('settings', where: "key = 'backup.last_at'"),
      builder: (context, r, _) => Section(
        title: 'النسخ الاحتياطي والاستعادة',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'نسخة مشفرة (AES-256) بكلمة مرور تحددها. احفظها خارج الهاتف (Drive أو واتساب أو حاسوب).\n'
              'آخر نسخة: ${r.isEmpty ? 'لم تُنشأ بعد' : (r.first['value'] as String).substring(0, 16).replaceFirst('T', ' ')}',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.backup),
                  label: const Text('إنشاء نسخة ومشاركتها'),
                  onPressed: () async {
                    final v = await showFormDialog(
                      context,
                      title: 'كلمة مرور النسخة',
                      note: 'لا يمكن استعادة النسخة بدون كلمة المرور هذه.',
                      fields: const [
                        FieldSpec('p', 'كلمة المرور', type: FieldType.password, required: true),
                        FieldSpec('p2', 'تأكيد كلمة المرور', type: FieldType.password, required: true),
                      ],
                    );
                    if (v == null || !context.mounted) return;
                    if (v['p'] != v['p2']) {
                      showError(context, const DomainException('X', 'كلمتا المرور غير متطابقتين.'));
                      return;
                    }
                    await guard(context, () async {
                      final bytes = await app.os.backup.createBackup(v['p']!);
                      final f = await ExportService.bytes(
                        'generator-os-${ymd(DateTime.now())}-${DateTime.now().millisecondsSinceEpoch % 100000}.gosbak',
                        bytes,
                      );
                      await ExportService.share(f, text: 'نسخة احتياطية مشفرة — Generator OS');
                    });
                    _r();
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.restore),
                  label: const Text('استعادة نسخة'),
                  onPressed: () => pickAndRestore(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _license(BuildContext context, AppState app) {
    return Loader<LicenseStatus>(
      key: ValueKey('l$_rev'),
      load: app.os.license.status,
      builder: (context, s, _) => Section(
        title: 'الترخيص',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (s.licensed)
              Text(
                'ترخيص دائم باسم: ${s.license!.customer}\nرقم الترخيص: ${s.license!.licenseId}\n'
                'عدد المولدات المسموح: ${s.license!.maxGenerators}\n'
                '${s.license!.services.isEmpty ? '' : 'الخدمات الاختيارية: ${s.license!.services.entries.map((e) => '${e.key} حتى ${e.value}').join('، ')}'}',
              )
            else
              Text(
                'نسخة غير مفعلة: تعمل كل الوظائف لمولدة واحدة، ولا تُقفل بياناتك أبداً.'
                '${s.problem != null ? '\nمشكلة الترخيص المحفوظ: ${s.problem}' : ''}',
              ),
            const SizedBox(height: 8),
            Text(
              'رمز التثبيت (أرسله للبائع للحصول على ترخيص): ${app.os.license.installationCode()}',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy),
                  label: const Text('نسخ رمز التثبيت'),
                  onPressed: () => Clipboard.setData(ClipboardData(text: app.os.license.installationCode())),
                ),
                if (app.can(Perm.settingsManage))
                  FilledButton.icon(
                    icon: const Icon(Icons.verified),
                    label: const Text('تفعيل ترخيص'),
                    onPressed: () async {
                      final v = await showFormDialog(
                        context,
                        title: 'مفتاح الترخيص',
                        fields: const [FieldSpec('k', 'المفتاح', type: FieldType.multiline, required: true)],
                      );
                      if (v == null || !context.mounted) return;
                      await guard(context, () => app.os.license.activate(v['k']!), success: 'تم تفعيل الترخيص');
                      _r();
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _iot(BuildContext context, AppState app) {
    final g = app.generatorId;
    if (g == null) return const SizedBox.shrink();
    return Loader<(List<Map<String, Object?>>, List<Map<String, Object?>>)>(
      key: ValueKey('i$_rev'),
      load: () async => (await app.os.integration.devices(g), await app.os.integration.readings(g, limit: 20)),
      builder: (context, d, _) => Section(
        title: 'أجهزة المراقبة والحساسات',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'تسجيل أجهزة مراقبة (MQTT / Modbus TCP / HTTP). لا تُعرض أي قراءة إلا إذا وصلت من جهاز فعلي '
              'عبر الخادم أو محوّل اتصال مختبر. لا توجد قراءات افتراضية.',
            ),
            const SizedBox(height: 8),
            for (final dv in d.$1)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.sensors),
                title: Text('${dv['name']} (${IntegrationService.protocols[dv['protocol']]})'),
                subtitle: Text('آخر اتصال: ${dv['last_seen'] ?? 'لم يتصل بعد'}'),
              ),
            if (d.$2.isNotEmpty) ...[
              const Divider(),
              for (final r in d.$2)
                Text(
                  '${(r['at'] as String).substring(0, 16)} — ${SensorMetric.labels[r['metric']] ?? r['metric']}: ${r['value']}',
                  style: const TextStyle(fontSize: 12),
                ),
            ],
            OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('تسجيل جهاز'),
              onPressed: () async {
                final v = await showFormDialog(
                  context,
                  title: 'جهاز مراقبة',
                  fields: const [
                    FieldSpec('name', 'الاسم', required: true),
                    FieldSpec(
                      'protocol',
                      'البروتوكول',
                      type: FieldType.dropdown,
                      required: true,
                      options: IntegrationService.protocols,
                    ),
                    FieldSpec('endpoint', 'العنوان (IP/Topic/URL)'),
                  ],
                );
                if (v == null || !context.mounted) return;
                await guard(
                  context,
                  () => app.os.integration.registerDevice(
                    g,
                    v['name']!,
                    v['protocol']!,
                    endpoint: emptyToNull(v['endpoint']),
                  ),
                );
                _r();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class AuditScreen extends StatelessWidget {
  const AuditScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('سجل التدقيق')),
      body: Loader<List<Map<String, Object?>>>(
        load: () => app.os.audit.list(generatorId: app.generatorId, limit: 500),
        builder: (context, rows, _) => ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: rows.length,
          itemBuilder: (context, i) {
            final a = rows[i];
            return ListTile(
              dense: true,
              leading: const Icon(Icons.history_edu),
              title: Text('${a['action']}${a['entity'] != null ? ' · ${a['entity']}' : ''}'),
              subtitle: Text(
                '${(a['at'] as String).substring(0, 19).replaceFirst('T', ' ')} · ${a['user_name'] ?? 'النظام'}'
                ' · جهاز ${(a['device_id'] as String? ?? '').padRight(8).substring(0, 8)}'
                '${a['details'] != null ? '\n${a['details']}' : ''}',
              ),
            );
          },
        ),
      ),
    );
  }
}
