import 'package:flutter/material.dart';
import 'package:generator_core/generator_core.dart';

import '../../app_state.dart';
import '../../theme.dart';
import '../common.dart';

class OperationsScreen extends StatefulWidget {
  const OperationsScreen({super.key});
  @override
  State<OperationsScreen> createState() => _OperationsScreenState();
}

class _OperationsScreenState extends State<OperationsScreen> {
  int _rev = 0;
  void _r() => setState(() => _rev++);

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final g = app.generatorId!;
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'التشغيل'),
              Tab(text: 'الصيانة'),
              Tab(text: 'الأعطال'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [_runs(context, app, g), _maintenance(context, app, g), _faults(context, app, g)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _runs(BuildContext context, AppState app, String g) {
    return Loader<(Map<String, Object?>?, List<Map<String, Object?>>, double, double)>(
      key: ValueKey('r$_rev'),
      load: () async => (
        await app.os.operations.openRun(g),
        await app.os.operations.runs(g, DateRange.lastDays(DateTime.now(), 30)),
        await app.os.operations.runHours(g, DateRange.day(DateTime.now())),
        await app.os.operations.totalHours(g),
      ),
      builder: (context, d, _) {
        final (open, runs, today, total) = d;
        return PageBody(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      open != null ? Icons.power : Icons.power_off,
                      size: 40,
                      color: open != null ? Brand.success : Colors.grey,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            open != null ? 'المولدة تعمل' : 'المولدة متوقفة',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          if (open != null)
                            Text('منذ ${(open['started_at'] as String).substring(0, 16).replaceFirst('T', ' ')}'),
                          const Text('حسب سجل التشغيل اليدوي', style: TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                    if (app.can(Perm.operationsManage))
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: open != null ? Brand.danger : Brand.success),
                        onPressed: () async {
                          if (open == null) {
                            final v = await showFormDialog(
                              context,
                              title: 'تشغيل المولدة',
                              fields: const [
                                FieldSpec('grid', 'بسبب انقطاع الكهرباء الوطنية', type: FieldType.toggle, initial: '1'),
                              ],
                            );
                            if (v == null || !context.mounted) return;
                            await guard(context, () => app.os.operations.startRun(g, gridOutage: v['grid'] == '1'));
                          } else {
                            final v = await showFormDialog(
                              context,
                              title: 'إطفاء المولدة',
                              fields: const [
                                FieldSpec(
                                  'reason',
                                  'سبب التوقف',
                                  type: FieldType.dropdown,
                                  required: true,
                                  initial: 'grid_back',
                                  options: {
                                    'grid_back': 'عودة الكهرباء الوطنية',
                                    'schedule': 'انتهاء الجدول',
                                    'maintenance': 'صيانة',
                                    'fault': 'عطل',
                                    'fuel': 'نفاد الوقود',
                                    'other': 'أخرى',
                                  },
                                ),
                              ],
                            );
                            if (v == null || !context.mounted) return;
                            await guard(context, () => app.os.operations.stopRun(g, reason: v['reason']));
                          }
                          _r();
                        },
                        child: Text(open != null ? 'إطفاء' : 'تشغيل'),
                      ),
                  ],
                ),
              ),
            ),
            StatGrid(
              children: [
                StatCard(label: 'ساعات اليوم', value: today.toStringAsFixed(1), icon: Icons.today, color: Brand.info),
                StatCard(
                  label: 'إجمالي ساعات السجل',
                  value: total.toStringAsFixed(0),
                  icon: Icons.av_timer,
                  color: Brand.primary,
                ),
              ],
            ),
            if (app.can(Perm.operationsManage))
              OutlinedButton.icon(
                icon: const Icon(Icons.edit_calendar),
                label: const Text('إدخال تشغيل سابق يدوياً'),
                onPressed: () async {
                  final v = await showFormDialog(
                    context,
                    title: 'تشغيل سابق',
                    fields: [
                      FieldSpec('date', 'التاريخ', type: FieldType.date, required: true, initial: ymd(DateTime.now())),
                      const FieldSpec('from', 'من الساعة (0-23)', type: FieldType.number, required: true),
                      const FieldSpec('to', 'إلى الساعة (1-24)', type: FieldType.number, required: true),
                    ],
                  );
                  if (v == null || !context.mounted) return;
                  final day = DateTime.parse(v['date']!);
                  await guard(
                    context,
                    () => app.os.operations.logRun(
                      g,
                      day.add(Duration(minutes: (parseNum(v['from'])! * 60).round())),
                      day.add(Duration(minutes: (parseNum(v['to'])! * 60).round())),
                    ),
                  );
                  _r();
                },
              ),
            Section(
              title: 'سجل آخر 30 يوماً',
              child: runs.isEmpty
                  ? const Text('لا يوجد تشغيل مسجل.')
                  : Column(
                      children: [
                        for (final r in runs)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(r['grid_outage'] == 1 ? Icons.flash_off : Icons.power_settings_new),
                            title: Text(
                              '${(r['started_at'] as String).substring(0, 16).replaceFirst('T', ' ')}'
                              ' ← ${r['stopped_at'] == null ? 'مستمر' : (r['stopped_at'] as String).substring(11, 16)}',
                            ),
                            subtitle: r['stop_reason'] == null ? null : Text('${r['stop_reason']}'),
                            trailing: Text(
                              r['stopped_at'] == null
                                  ? ''
                                  : '${(DateTime.parse(r['stopped_at'] as String).difference(DateTime.parse(r['started_at'] as String)).inMinutes / 60).toStringAsFixed(1)} س',
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _maintenance(BuildContext context, AppState app, String g) {
    return Loader<(List<Map<String, Object?>>, List<Map<String, Object?>>, List<Map<String, Object?>>)>(
      key: ValueKey('m$_rev'),
      load: () async => (
        await app.os.operations.upcomingMaintenance(g, withinDays: 30),
        await app.os.operations.plans(g),
        await app.os.operations.maintenanceRecords(g),
      ),
      builder: (context, d, _) {
        final (due, plans, recs) = d;
        return PageBody(
          children: [
            if (app.can(Perm.maintenanceManage))
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.build),
                    label: const Text('تسجيل صيانة'),
                    onPressed: () async {
                      final v = await showFormDialog(
                        context,
                        title: 'تسجيل صيانة',
                        fields: [
                          const FieldSpec(
                            'kind',
                            'النوع',
                            type: FieldType.dropdown,
                            required: true,
                            options: MaintenanceKind.labels,
                          ),
                          const FieldSpec('tech', 'الفني'),
                          const FieldSpec('parts', 'القطع المستبدلة'),
                          const FieldSpec('parts_cost', 'كلفة القطع', type: FieldType.money),
                          const FieldSpec('labor', 'أجور الفني', type: FieldType.money),
                          FieldSpec('next', 'موعد الصيانة القادمة', type: FieldType.date),
                          const FieldSpec('notes', 'ملاحظات', type: FieldType.multiline),
                        ],
                        note: 'الكلفة تُسجل تلقائياً كمصروف نقدي من الصندوق الرئيسي.',
                      );
                      if (v == null || !context.mounted) return;
                      await guard(
                        context,
                        () => app.os.operations.recordMaintenance(
                          generatorId: g,
                          kind: v['kind']!,
                          technician: emptyToNull(v['tech']),
                          parts: emptyToNull(v['parts']),
                          partsCost: parseMoney(v['parts_cost']) ?? 0,
                          laborCost: parseMoney(v['labor']) ?? 0,
                          nextDueDate: emptyToNull(v['next']),
                          notes: emptyToNull(v['notes']),
                        ),
                        success: 'تم تسجيل الصيانة',
                      );
                      _r();
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.event_repeat),
                    label: const Text('جدول صيانة دوري'),
                    onPressed: () async {
                      final v = await showFormDialog(
                        context,
                        title: 'صيانة دورية',
                        fields: const [
                          FieldSpec(
                            'kind',
                            'النوع',
                            type: FieldType.dropdown,
                            required: true,
                            options: MaintenanceKind.labels,
                          ),
                          FieldSpec('days', 'كل كم يوم', type: FieldType.number),
                          FieldSpec('hours', 'أو كل كم ساعة تشغيل', type: FieldType.number),
                        ],
                      );
                      if (v == null || !context.mounted) return;
                      await guard(
                        context,
                        () => app.os.operations.createPlan(
                          g,
                          v['kind']!,
                          intervalDays: parseMoney(v['days']),
                          intervalHours: parseMoney(v['hours']),
                        ),
                      );
                      _r();
                    },
                  ),
                ],
              ),
            Section(
              title: 'المستحق خلال 30 يوماً',
              child: due.isEmpty
                  ? const Text('لا توجد صيانة مستحقة.')
                  : Column(
                      children: [
                        for (final x in due)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.alarm, color: x['overdue'] == true ? Brand.danger : Brand.warning),
                            title: Text('${MaintenanceKind.labels[x['kind']] ?? x['kind']}'),
                            subtitle: Text(
                              [
                                if (x['due_date'] != null) 'الموعد ${x['due_date']}',
                                if (x['hours_left'] != null)
                                  'متبقي ${(x['hours_left'] as double).toStringAsFixed(0)} ساعة',
                              ].join(' · '),
                            ),
                          ),
                      ],
                    ),
            ),
            Section(
              title: 'الجداول الدورية',
              child: plans.isEmpty
                  ? const Text('لا توجد جداول.')
                  : Column(
                      children: [
                        for (final p in plans)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text('${MaintenanceKind.labels[p['kind']] ?? p['kind']}'),
                            subtitle: Text(
                              [
                                if (p['interval_days'] != null) 'كل ${p['interval_days']} يوم',
                                if (p['interval_hours'] != null) 'كل ${p['interval_hours']} ساعة',
                                'آخر تنفيذ ${p['last_done_date']}',
                              ].join(' · '),
                            ),
                          ),
                      ],
                    ),
            ),
            Section(
              title: 'سجل الصيانة',
              child: recs.isEmpty
                  ? const Text('لا يوجد سجل.')
                  : Column(
                      children: [
                        for (final r in recs)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.handyman),
                            title: Text('${MaintenanceKind.labels[r['kind']] ?? r['kind']} — ${r['done_date']}'),
                            subtitle: Text(
                              [
                                if (r['technician'] != null) 'الفني ${r['technician']}',
                                if (r['parts'] != null) '${r['parts']}',
                                if (r['next_due_date'] != null) 'القادمة ${r['next_due_date']}',
                              ].join(' · '),
                            ),
                            trailing: Text(money((r['parts_cost'] as int) + (r['labor_cost'] as int))),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _faults(BuildContext context, AppState app, String g) {
    Color sev(String s) => switch (s) {
      FaultSeverity.critical => Brand.danger,
      FaultSeverity.high => Brand.warning,
      FaultSeverity.medium => Brand.info,
      _ => Colors.grey,
    };
    return Scaffold(
      floatingActionButton: app.can(Perm.maintenanceManage)
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.report_problem),
              label: const Text('تسجيل عطل'),
              onPressed: () async {
                final v = await showFormDialog(
                  context,
                  title: 'تسجيل عطل',
                  fields: const [
                    FieldSpec('title', 'العطل', required: true),
                    FieldSpec('desc', 'الوصف', type: FieldType.multiline),
                    FieldSpec(
                      'sev',
                      'الخطورة',
                      type: FieldType.dropdown,
                      required: true,
                      initial: FaultSeverity.medium,
                      options: FaultSeverity.labels,
                    ),
                    FieldSpec('tech', 'الفني المسؤول'),
                  ],
                );
                if (v == null || !context.mounted) return;
                await guard(
                  context,
                  () => app.os.operations.reportFault(
                    generatorId: g,
                    title: v['title']!,
                    description: emptyToNull(v['desc']),
                    severity: v['sev']!,
                    technician: emptyToNull(v['tech']),
                  ),
                );
                _r();
              },
            )
          : null,
      body: Loader<List<Map<String, Object?>>>(
        key: ValueKey('f$_rev'),
        load: () => app.os.operations.faults(g),
        builder: (context, rows, _) => rows.isEmpty
            ? const EmptyState(icon: Icons.verified, title: 'لا توجد أعطال مسجلة')
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                children: [
                  for (final f in rows)
                    Card(
                      child: ListTile(
                        leading: Icon(Icons.report, color: sev(f['severity'] as String)),
                        title: Text('${f['title']}'),
                        subtitle: Text(
                          [
                            'وقع ${(f['occurred_at'] as String).substring(0, 16).replaceFirst('T', ' ')}',
                            if (f['fixed_at'] != null)
                              'أُصلح ${(f['fixed_at'] as String).substring(0, 16).replaceFirst('T', ' ')}',
                            if (f['technician'] != null) 'الفني ${f['technician']}',
                            if ((f['repair_cost'] as int) > 0) 'الكلفة ${money(f['repair_cost'] as int)}',
                            if (f['description'] != null) '${f['description']}',
                          ].join('\n'),
                        ),
                        isThreeLine: true,
                        trailing: f['status'] == 'open'
                            ? (app.can(Perm.maintenanceManage)
                                  ? TextButton(
                                      onPressed: () async {
                                        final v = await showFormDialog(
                                          context,
                                          title: 'إغلاق العطل',
                                          fields: const [
                                            FieldSpec('cost', 'كلفة الإصلاح', type: FieldType.money),
                                            FieldSpec('parts', 'القطع المستبدلة'),
                                            FieldSpec('tech', 'الفني'),
                                          ],
                                        );
                                        if (v == null || !context.mounted) return;
                                        await guard(
                                          context,
                                          () => app.os.operations.resolveFault(
                                            f['id'] as String,
                                            repairCost: parseMoney(v['cost']) ?? 0,
                                            parts: emptyToNull(v['parts']),
                                            technician: emptyToNull(v['tech']),
                                          ),
                                        );
                                        _r();
                                      },
                                      child: const Text('تم الإصلاح'),
                                    )
                                  : const StatusChip('مفتوح', Brand.danger))
                            : const StatusChip('مُصلح', Brand.success),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
