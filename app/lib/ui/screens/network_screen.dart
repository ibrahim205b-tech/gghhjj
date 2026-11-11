import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../theme.dart';
import '../common.dart';

/// Areas, cabinets, lines and contracted load per cabinet/line.
class NetworkScreen extends StatefulWidget {
  const NetworkScreen({super.key});
  @override
  State<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen> {
  int _rev = 0;
  void _r() => setState(() => _rev++);

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final g = app.generatorId!;
    return Loader<(List<Map<String, Object?>>, List<Map<String, Object?>>, List<Map<String, Object?>>)>(
      key: ValueKey(_rev),
      load: () async =>
          (await app.os.network.listAreas(g), await app.os.network.cabinetLoads(g), await app.os.network.lineLoads(g)),
      builder: (context, d, _) {
        final (areas, cabs, lines) = d;
        return PageBody(
          children: [
            const Card(
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('الأحمال المعروضة نظرية'),
                subtitle: Text(
                  'مجموع الأمبيرات المشترَك بها للمشتركين الموصولين، وليست قياساً كهربائياً فعلياً. '
                  'القياس الفعلي يتطلب جهاز مراقبة مربوطاً.',
                ),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.add_location_alt),
                  label: const Text('منطقة'),
                  onPressed: () async {
                    final v = await showFormDialog(
                      context,
                      title: 'منطقة جديدة',
                      fields: const [
                        FieldSpec('name', 'اسم المنطقة / الحي', required: true),
                        FieldSpec('province', 'المحافظة'),
                        FieldSpec('district', 'القضاء / الناحية'),
                      ],
                    );
                    if (v == null || !context.mounted) return;
                    await guard(
                      context,
                      () => app.os.network.createArea(
                        g,
                        v['name']!,
                        province: emptyToNull(v['province']),
                        district: emptyToNull(v['district']),
                      ),
                    );
                    _r();
                  },
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.electrical_services),
                  label: const Text('كابينة'),
                  onPressed: () async {
                    final v = await showFormDialog(
                      context,
                      title: 'كابينة جديدة',
                      fields: [
                        const FieldSpec('code', 'رقم/رمز الكابينة', required: true),
                        FieldSpec(
                          'area',
                          'المنطقة',
                          type: FieldType.dropdown,
                          options: {for (final a in areas) a['id'] as String: a['name'] as String},
                        ),
                        const FieldSpec('max', 'السعة القصوى (أمبير)', type: FieldType.number),
                        const FieldSpec('loc', 'الموقع'),
                      ],
                    );
                    if (v == null || !context.mounted) return;
                    await guard(
                      context,
                      () => app.os.network.createCabinet(
                        g,
                        v['code']!,
                        areaId: emptyToNull(v['area']),
                        maxAmps: parseMoney(v['max']) ?? 0,
                        location: emptyToNull(v['loc']),
                      ),
                    );
                    _r();
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.linear_scale),
                  label: const Text('خط'),
                  onPressed: () async {
                    final v = await showFormDialog(
                      context,
                      title: 'خط جديد',
                      fields: [
                        const FieldSpec('code', 'رقم الخط', required: true),
                        FieldSpec(
                          'cab',
                          'الكابينة',
                          type: FieldType.dropdown,
                          options: {for (final c in cabs) c['id'] as String: c['code'] as String},
                        ),
                        const FieldSpec('max', 'السعة القصوى (أمبير)', type: FieldType.number),
                      ],
                    );
                    if (v == null || !context.mounted) return;
                    await guard(
                      context,
                      () => app.os.network.createLine(
                        g,
                        v['code']!,
                        cabinetId: emptyToNull(v['cab']),
                        maxAmps: parseMoney(v['max']) ?? 0,
                      ),
                    );
                    _r();
                  },
                ),
              ],
            ),
            Section(
              title: 'المناطق (${areas.length})',
              child: areas.isEmpty
                  ? const Text('لا توجد مناطق.')
                  : Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final a in areas)
                          Chip(avatar: const Icon(Icons.place, size: 16), label: Text('${a['name']}')),
                      ],
                    ),
            ),
            Section(
              title: 'الكابينات والأحمال',
              child: cabs.isEmpty
                  ? const Text('لا توجد كابينات.')
                  : Column(children: [for (final c in cabs) _LoadRow(c, isLine: false)]),
            ),
            Section(
              title: 'الخطوط والأحمال',
              child: lines.isEmpty
                  ? const Text('لا توجد خطوط.')
                  : Column(children: [for (final l in lines) _LoadRow(l, isLine: true)]),
            ),
          ],
        );
      },
    );
  }
}

class _LoadRow extends StatelessWidget {
  final Map<String, Object?> r;
  final bool isLine;
  const _LoadRow(this.r, {required this.isLine});
  @override
  Widget build(BuildContext context) {
    final max = r['max_amps'] as int;
    final load = r['contracted_amps'] as int;
    final ratio = max <= 0 ? 0.0 : load / max;
    final color = ratio > 1
        ? Brand.danger
        : ratio > 0.85
        ? Brand.warning
        : Brand.success;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${isLine ? 'خط' : 'كابينة'} ${r['code']}'
                  '${isLine ? (r['cabinet_code'] != null ? ' · كابينة ${r['cabinet_code']}' : '') : (r['area_name'] != null ? ' · ${r['area_name']}' : '')}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text('$load / ${max > 0 ? max : '—'} أمبير · ${r['subscribers']} مشترك'),
              if (ratio > 1) ...[const SizedBox(width: 6), const StatusChip('تجاوز', Brand.danger)],
            ],
          ),
          const SizedBox(height: 6),
          if (max > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio.clamp(0, 1),
                minHeight: 8,
                color: color,
                backgroundColor: color.withValues(alpha: 0.15),
              ),
            )
          else
            const Text('لم تُحدد سعة قصوى', style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
