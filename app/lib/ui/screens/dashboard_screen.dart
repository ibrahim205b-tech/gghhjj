import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:generator_core/generator_core.dart';

import '../../app_state.dart';
import '../../theme.dart';
import '../common.dart';

/// Validated categorical slots 1–2 (light / dark steps) for chart series.
Color seriesBlue(BuildContext c) =>
    Theme.of(c).brightness == Brightness.dark ? const Color(0xFF3987E5) : const Color(0xFF2A78D6);
Color seriesOrange(BuildContext c) =>
    Theme.of(c).brightness == Brightness.dark ? const Color(0xFFD95926) : const Color(0xFFEB6834);

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Granularity _g = Granularity.day;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final g = app.generatorId!;
    return Loader<(DashboardData, List<Map<String, Object?>>, FuelStock, List<SeriesPoint>?)>(
      load: () async => (
        await app.os.reports.dashboard(g),
        await app.os.operations.upcomingMaintenance(g),
        await app.os.fuel.stock(g),
        app.can(Perm.financeView)
            ? await app.os.reports.series(
                g,
                _g,
                count: _g == Granularity.day
                    ? 14
                    : _g == Granularity.month
                    ? 12
                    : 5,
              )
            : null,
      ),
      builder: (context, data, reload) {
        final (d, maint, fuel, series) = data;
        final c = d.subscriberCounts;
        return PageBody(
          onRefresh: () async => reload(),
          children: [
            Text('اليوم', style: Theme.of(context).textTheme.titleSmall),
            StatGrid(
              children: [
                StatCard(
                  label: 'مقبوضات اليوم',
                  value: money(d.collectionsToday),
                  icon: Icons.south_west,
                  color: Brand.success,
                  hint: 'تسديدات المشتركين',
                ),
                if (d.financeVisible) ...[
                  StatCard(
                    label: 'مصروفات اليوم',
                    value: money(d.expensesToday),
                    icon: Icons.north_east,
                    color: Brand.danger,
                  ),
                  StatCard(
                    label: 'صافي اليوم',
                    value: money(d.collectionsToday - d.expensesToday),
                    icon: Icons.account_balance,
                    color: Brand.primary,
                    hint: 'المقبوضات − المصروفات',
                  ),
                ],
                StatCard(
                  label: 'ساعات التشغيل اليوم',
                  value: d.runHoursToday.toStringAsFixed(1),
                  icon: Icons.timer,
                  color: Brand.info,
                ),
              ],
            ),
            if (d.financeVisible) ...[
              Text('هذا الشهر', style: Theme.of(context).textTheme.titleSmall),
              StatGrid(
                children: [
                  StatCard(
                    label: 'إيرادات الشهر',
                    value: money(d.month.revenue),
                    icon: Icons.trending_up,
                    color: Brand.success,
                    hint: 'الفواتير بعد الخصومات',
                  ),
                  StatCard(
                    label: 'مصروفات الشهر',
                    value: money(d.month.expenses),
                    icon: Icons.trending_down,
                    color: Brand.danger,
                    hint: 'تشمل كلفة الوقود المستهلك',
                  ),
                  StatCard(
                    label: 'صافي ربح الشهر',
                    value: money(d.month.profit),
                    icon: Icons.savings,
                    color: d.month.profit >= 0 ? Brand.primary : Brand.danger,
                  ),
                  StatCard(
                    label: 'مقبوضات الشهر',
                    value: money(d.collectionsMonth),
                    icon: Icons.payments,
                    color: Brand.info,
                  ),
                ],
              ),
            ],
            Text('المشتركون والتشغيل', style: Theme.of(context).textTheme.titleSmall),
            StatGrid(
              children: [
                StatCard(
                  label: 'إجمالي ديون المشتركين',
                  value: money(d.totalDebt),
                  icon: Icons.warning_amber,
                  color: Brand.warning,
                ),
                StatCard(
                  label: 'عدد المشتركين',
                  value: '${c['total']}',
                  icon: Icons.people,
                  color: Brand.primary,
                  hint: 'فعال ${c['active']} · متوقف ${c['stopped']}',
                ),
                StatCard(label: 'غير المسددين', value: '${c['debtors']}', icon: Icons.person_off, color: Brand.danger),
                StatCard(label: 'الأمبيرات المباعة', value: '${c['amps']} A', icon: Icons.bolt, color: Brand.accent),
                StatCard(
                  label: 'الكاز المتوفر (دفتري)',
                  value: liters(d.fuelBookMl),
                  icon: Icons.local_gas_station,
                  color: Brand.info,
                  hint: fuel.lastDipMl == null ? 'لا يوجد قياس فعلي' : 'آخر قياس: ${liters(fuel.lastDipMl!)}',
                ),
                StatCard(
                  label: 'ساعات تشغيل الشهر',
                  value: d.runHoursMonth.toStringAsFixed(1),
                  icon: Icons.av_timer,
                  color: Brand.primary,
                ),
                StatCard(
                  label: 'أعطال مفتوحة',
                  value: '${d.openFaults}',
                  icon: Icons.build,
                  color: d.openFaults > 0 ? Brand.danger : Brand.success,
                ),
                StatCard(
                  label: 'تنبيهات غير مقروءة',
                  value: '${d.unreadAlerts}',
                  icon: Icons.notifications,
                  color: Brand.warning,
                ),
              ],
            ),
            if (series != null)
              Section(
                title: 'المقبوضات والمصروفات',
                actions: [
                  SegmentedButton<Granularity>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: Granularity.day, label: Text('يومي')),
                      ButtonSegment(value: Granularity.month, label: Text('شهري')),
                      ButtonSegment(value: Granularity.year, label: Text('سنوي')),
                    ],
                    selected: {_g},
                    onSelectionChanged: (s) => setState(() => _g = s.first),
                  ),
                ],
                child: SeriesChart(points: series),
              ),
            LayoutBuilder(
              builder: (context, cons) {
                final wide = cons.maxWidth > 800;
                final a = Section(
                  title: 'آخر عمليات الجباية',
                  child: d.recentPayments.isEmpty
                      ? const EmptyState(icon: Icons.receipt, title: 'لا توجد عمليات جباية بعد')
                      : Column(
                          children: [
                            for (final p in d.recentPayments)
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  p['reversal_of'] != null ? Icons.undo : Icons.check_circle,
                                  color: p['reversal_of'] != null ? Brand.danger : Brand.success,
                                ),
                                title: Text('${p['full_name']}'),
                                subtitle: Text(
                                  '${(p['paid_at'] as String).substring(0, 16).replaceFirst('T', ' ')}'
                                  '${p['collector_name'] != null ? ' · ${p['collector_name']}' : ''}',
                                ),
                                trailing: Text(
                                  money((p['amount'] as int) * (p['reversal_of'] != null ? -1 : 1)),
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                          ],
                        ),
                );
                final b = Section(
                  title: 'أداء الجباة هذا الشهر',
                  child: d.collectors.isEmpty
                      ? const EmptyState(icon: Icons.badge, title: 'لا توجد جباية عن طريق الجباة هذا الشهر')
                      : Column(
                          children: [
                            for (final col in d.collectors)
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.badge_outlined),
                                title: Text('${col['full_name']}'),
                                subtitle: Text('${col['receipts']} وصل'),
                                trailing: Text(
                                  money(col['collected'] as int),
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                          ],
                        ),
                );
                final m = Section(
                  title: 'مواعيد الصيانة القادمة',
                  child: maint.isEmpty
                      ? const EmptyState(icon: Icons.event_available, title: 'لا توجد صيانة مستحقة خلال 14 يوماً')
                      : Column(
                          children: [
                            for (final x in maint)
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  Icons.build_circle,
                                  color: x['overdue'] == true ? Brand.danger : Brand.warning,
                                ),
                                title: Text('${MaintenanceKind.labels[x['kind']] ?? x['kind']}'),
                                subtitle: Text(
                                  [
                                    if (x['due_date'] != null) 'الموعد ${x['due_date']}',
                                    if (x['hours_left'] != null)
                                      'متبقي ${(x['hours_left'] as double).toStringAsFixed(0)} ساعة',
                                  ].join(' · '),
                                ),
                                trailing: x['overdue'] == true ? const StatusChip('متأخرة', Brand.danger) : null,
                              ),
                          ],
                        ),
                );
                if (!wide) return Column(children: [a, const SizedBox(height: 12), b, const SizedBox(height: 12), m]);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: a),
                    const SizedBox(width: 12),
                    Expanded(child: Column(children: [b, const SizedBox(height: 12), m])),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

/// Two-series bar chart: collections vs expenses. Legend always shown,
/// values available on touch, one y-axis, recessive grid.
class SeriesChart extends StatelessWidget {
  final List<SeriesPoint> points;
  const SeriesChart({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurfaceVariant;
    final blue = seriesBlue(context), orange = seriesOrange(context);
    final maxY = points.fold<int>(0, (m, p) => [m, p.collections, p.expenses].reduce((a, b) => a > b ? a : b));
    if (maxY == 0) {
      return const SizedBox(
        height: 160,
        child: EmptyState(icon: Icons.bar_chart, title: 'لا توجد حركات مالية في هذه الفترة'),
      );
    }
    Widget legend(Color c, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: t.colorScheme.onSurface, fontSize: 12)),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 16, children: [legend(blue, 'المقبوضات'), legend(orange, 'المصروفات')]),
        const SizedBox(height: 12),
        SizedBox(
          height: 220,
          child: Directionality(
            // Time flows left-to-right on charts even in RTL apps.
            textDirection: TextDirection.ltr,
            child: BarChart(
              BarChartData(
                maxY: maxY * 1.15,
                alignment: BarChartAlignment.spaceAround,
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: maxY / 4,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: t.colorScheme.outlineVariant.withValues(alpha: 0.4), strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 48,
                      interval: maxY / 4,
                      getTitlesWidget: (v, _) => Text(_compact(v), style: TextStyle(fontSize: 10, color: muted)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= points.length) return const SizedBox.shrink();
                        if (points.length > 8 && i % 2 == 1) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(points[i].label, style: TextStyle(fontSize: 10, color: muted)),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => t.colorScheme.inverseSurface,
                    getTooltipItem: (group, _, rod, rodIndex) => BarTooltipItem(
                      '${points[group.x].label}\n${rodIndex == 0 ? 'المقبوضات' : 'المصروفات'}: ${money(rod.toY)}',
                      TextStyle(
                        color: t.colorScheme.onInverseSurface,
                        fontSize: 11,
                        fontFamily: 'NotoKufiArabic',
                        fontFamilyFallback: const ['NotoSans'],
                      ),
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < points.length; i++)
                    BarChartGroupData(
                      x: i,
                      barsSpace: 2,
                      barRods: [
                        BarChartRodData(
                          toY: points[i].collections.toDouble(),
                          color: blue,
                          width: points.length > 8 ? 6 : 10,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                        BarChartRodData(
                          toY: points[i].expenses.toDouble(),
                          color: orange,
                          width: points.length > 8 ? 6 : 10,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _compact(double v) {
    if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(1)}M';
    if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }
}
