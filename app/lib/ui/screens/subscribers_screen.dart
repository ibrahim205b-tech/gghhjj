import 'package:flutter/material.dart';
import 'package:generator_core/generator_core.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app_state.dart';
import '../../services/export_service.dart';
import '../../services/pdf_service.dart';
import '../../theme.dart';
import '../common.dart';
import '../payment_flow.dart';

Color statusColor(String s) => switch (s) {
  SubscriberStatus.active => Brand.success,
  SubscriberStatus.stopped => Brand.danger,
  _ => Colors.grey,
};

class SubscribersScreen extends StatefulWidget {
  const SubscribersScreen({super.key});
  @override
  State<SubscribersScreen> createState() => _SubscribersScreenState();
}

class _SubscribersScreenState extends State<SubscribersScreen> {
  final _q = TextEditingController();
  String? _status;
  String? _area;
  String? _cabinet;
  bool _debt = false;
  int _rev = 0;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final g = app.generatorId!;
    return Scaffold(
      floatingActionButton: app.can(Perm.subscribersEdit)
          ? FloatingActionButton.extended(
              onPressed: () async {
                final changed = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(builder: (_) => const SubscriberFormScreen()),
                );
                if (changed == true) setState(() => _rev++);
              },
              icon: const Icon(Icons.person_add),
              label: const Text('مشترك جديد'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _q,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'بحث بالاسم، الهاتف، رقم الجوزة، رقم الاشتراك، المنطقة أو الكابينة',
                suffixIcon: _q.text.isEmpty
                    ? null
                    : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _q.clear())),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Loader<(List<Map<String, Object?>>, List<Map<String, Object?>>)>(
            load: () async => (await app.os.network.listAreas(g), await app.os.network.listCabinets(g)),
            builder: (context, d, _) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('عليهم ديون'),
                    selected: _debt,
                    onSelected: (v) => setState(() => _debt = v),
                  ),
                  const SizedBox(width: 6),
                  for (final s in [SubscriberStatus.active, SubscriberStatus.stopped]) ...[
                    ChoiceChip(
                      label: Text(SubscriberStatus.labels[s]!),
                      selected: _status == s,
                      onSelected: (v) => setState(() => _status = v ? s : null),
                    ),
                    const SizedBox(width: 6),
                  ],
                  _drop('المنطقة', _area, {
                    for (final a in d.$1) a['id'] as String: a['name'] as String,
                  }, (v) => setState(() => _area = v)),
                  const SizedBox(width: 6),
                  _drop('الكابينة', _cabinet, {
                    for (final c in d.$2) c['id'] as String: c['code'] as String,
                  }, (v) => setState(() => _cabinet = v)),
                ],
              ),
            ),
          ),
          Expanded(
            child: Loader<List<Map<String, Object?>>>(
              key: ValueKey('${_q.text}|$_status|$_area|$_cabinet|$_debt|$_rev'),
              load: () => app.os.subscribers.search(
                g,
                SubscriberFilter(
                  query: _q.text,
                  status: _status,
                  areaId: _area,
                  cabinetId: _cabinet,
                  onlyWithDebt: _debt,
                ),
                limit: 300,
              ),
              builder: (context, rows, reload) {
                if (rows.isEmpty) {
                  return const EmptyState(
                    icon: Icons.people_outline,
                    title: 'لا يوجد مشتركون مطابقون',
                    subtitle: 'أضف مشتركاً جديداً أو غيّر معايير البحث.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final s = rows[i];
                    final bal = s['balance'] as int;
                    return Card(
                      child: ListTile(
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => SubscriberDetailScreen(id: s['id'] as String)),
                          );
                          reload();
                        },
                        leading: CircleAvatar(
                          backgroundColor: statusColor(s['status'] as String).withValues(alpha: 0.15),
                          child: Text(
                            '${s['account_no']}',
                            style: TextStyle(fontSize: 12, color: statusColor(s['status'] as String)),
                          ),
                        ),
                        title: Text('${s['full_name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          [
                            '${s['amps']} أمبير',
                            if (s['area_name'] != null) '${s['area_name']}',
                            if (s['cabinet_code'] != null) 'كابينة ${s['cabinet_code']}',
                            if (s['connected'] == 0) 'مفصول',
                          ].join(' · '),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              money(bal),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: bal > 0 ? Brand.danger : Brand.success,
                              ),
                            ),
                            Text(
                              bal > 0
                                  ? 'دين'
                                  : bal < 0
                                  ? 'رصيد مقدم'
                                  : 'مسدد',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _drop(String label, String? value, Map<String, String> opts, ValueChanged<String?> onChanged) {
    return PopupMenuButton<String>(
      onSelected: (v) => onChanged(v == '' ? null : v),
      itemBuilder: (_) => [
        const PopupMenuItem(value: '', child: Text('الكل')),
        for (final e in opts.entries) PopupMenuItem(value: e.key, child: Text(e.value)),
      ],
      child: Chip(
        avatar: const Icon(Icons.filter_list, size: 18),
        label: Text(value == null ? label : '$label: ${opts[value] ?? ''}'),
      ),
    );
  }
}

// ------------------------------------------------------------------ form

class SubscriberFormScreen extends StatefulWidget {
  final Map<String, Object?>? existing;
  const SubscriberFormScreen({super.key, this.existing});
  @override
  State<SubscriberFormScreen> createState() => _SubscriberFormScreenState();
}

class _SubscriberFormScreenState extends State<SubscriberFormScreen> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> c;
  String? area, cabinet, line, type;
  bool _busy = false;

  static const textFields = [
    ('full_name', 'الاسم الكامل *'),
    ('phone', 'رقم الهاتف'),
    ('phone2', 'رقم احتياطي'),
    ('meter_no', 'رقم الجوزة'),
    ('account_no', 'رقم الاشتراك (تلقائي إن تُرك فارغاً)'),
    ('province', 'المحافظة'),
    ('mahalla', 'المحلة'),
    ('alley', 'الزقاق'),
    ('house', 'الدار'),
    ('landmark', 'أقرب نقطة دالة'),
    ('lat', 'خط العرض (اختياري)'),
    ('lng', 'خط الطول (اختياري)'),
    ('amps', 'عدد الأمبيرات *'),
    ('amp_price', 'سعر الأمبير *'),
    ('start_date', 'تاريخ الاشتراك'),
    ('notes', 'ملاحظات'),
    ('opening_debt', 'دين سابق (قبل استخدام النظام)'),
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing ?? const {};
    c = {for (final (k, _) in textFields) k: TextEditingController(text: e[k]?.toString() ?? '')};
    area = e['area_id'] as String?;
    cabinet = e['cabinet_id'] as String?;
    line = e['line_id'] as String?;
    type = (e['subscription_type'] as String?) ?? SubscriptionType.normal;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final app = AppScope.read(context);
    final data = <String, Object?>{
      for (final k in [
        'full_name',
        'phone',
        'phone2',
        'meter_no',
        'account_no',
        'province',
        'mahalla',
        'alley',
        'house',
        'landmark',
        'notes',
      ])
        k: emptyToNull(c[k]!.text),
      'lat': parseNum(c['lat']!.text),
      'lng': parseNum(c['lng']!.text),
      'amps': parseMoney(c['amps']!.text),
      'amp_price': parseMoney(c['amp_price']!.text),
      'area_id': area,
      'cabinet_id': cabinet,
      'line_id': line,
      'subscription_type': type,
    };
    setState(() => _busy = true);
    final ok = await guard(context, () async {
      if (widget.existing == null) {
        data['start_date'] = emptyToNull(c['start_date']!.text);
        await app.os.subscribers.create(app.generatorId!, data, openingDebt: parseMoney(c['opening_debt']!.text) ?? 0);
      } else {
        data.remove('account_no');
        if (c['account_no']!.text.trim().isNotEmpty && c['account_no']!.text.trim() != widget.existing!['account_no']) {
          data['account_no'] = c['account_no']!.text.trim();
        }
        await app.os.subscribers.update(widget.existing!['id'] as String, data);
      }
    }, success: 'تم الحفظ');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final g = app.generatorId!;
    final editing = widget.existing != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'تعديل مشترك' : 'مشترك جديد')),
      body:
          Loader<
            (List<Map<String, Object?>>, List<Map<String, Object?>>, List<Map<String, Object?>>, Map<String, Object?>)
          >(
            load: () async => (
              await app.os.network.listAreas(g),
              await app.os.network.listCabinets(g),
              await app.os.network.listLines(g),
              await app.os.network.getGenerator(g),
            ),
            builder: (context, d, _) {
              if (!editing && c['amp_price']!.text.isEmpty) c['amp_price']!.text = '${d.$4['default_amp_price']}';
              final canPrice = app.can(Perm.subscribersEditPrice);
              Widget tf(String k, String label, {TextInputType? kb, bool enabled = true}) => TextFormField(
                controller: c[k],
                enabled: enabled,
                keyboardType: kb,
                maxLines: k == 'notes' ? 3 : 1,
                decoration: InputDecoration(labelText: label),
                validator: (v) {
                  final s = toLatinDigits(v?.trim() ?? '');
                  if (k == 'full_name' && s.length < 3) return 'الاسم مطلوب';
                  if ((k == 'amps' || k == 'amp_price') &&
                      (int.tryParse(s) == null || (k == 'amps' && int.parse(s) <= 0))) {
                    return 'أدخل رقماً صحيحاً';
                  }
                  return null;
                },
              );
              final fields = <Widget>[
                tf('full_name', 'الاسم الكامل *'),
                tf('phone', 'رقم الهاتف', kb: TextInputType.phone),
                tf('phone2', 'رقم احتياطي', kb: TextInputType.phone),
                tf('meter_no', 'رقم الجوزة'),
                tf('account_no', 'رقم الاشتراك (تلقائي إن تُرك فارغاً)'),
                tf('amps', 'عدد الأمبيرات *', kb: TextInputType.number),
                tf(
                  'amp_price',
                  canPrice ? 'سعر الأمبير *' : 'سعر الأمبير (لا تملك صلاحية تعديله)',
                  kb: TextInputType.number,
                  enabled: canPrice,
                ),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'نوع الاشتراك'),
                  items: [
                    for (final e in SubscriptionType.labels.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => type = v,
                ),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: area,
                  decoration: const InputDecoration(labelText: 'المنطقة'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('— بدون —')),
                    for (final a in d.$1) DropdownMenuItem(value: a['id'] as String, child: Text('${a['name']}')),
                  ],
                  onChanged: (v) => setState(() => area = v),
                ),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: cabinet,
                  decoration: const InputDecoration(labelText: 'الكابينة'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('— بدون —')),
                    for (final x in d.$2) DropdownMenuItem(value: x['id'] as String, child: Text('${x['code']}')),
                  ],
                  onChanged: (v) => setState(() => cabinet = v),
                ),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: line,
                  decoration: const InputDecoration(labelText: 'الخط'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('— بدون —')),
                    for (final x in d.$3) DropdownMenuItem(value: x['id'] as String, child: Text('${x['code']}')),
                  ],
                  onChanged: (v) => setState(() => line = v),
                ),
                tf('province', 'المحافظة'),
                tf('mahalla', 'المحلة'),
                tf('alley', 'الزقاق'),
                tf('house', 'الدار'),
                tf('landmark', 'أقرب نقطة دالة'),
                tf('lat', 'خط العرض (اختياري)', kb: const TextInputType.numberWithOptions(decimal: true, signed: true)),
                tf('lng', 'خط الطول (اختياري)', kb: const TextInputType.numberWithOptions(decimal: true, signed: true)),
                if (!editing) tf('start_date', 'تاريخ الاشتراك YYYY-MM-DD (افتراضياً اليوم)'),
                if (!editing) tf('opening_debt', 'دين سابق (قبل استخدام النظام)', kb: TextInputType.number),
                tf('notes', 'ملاحظات'),
              ];
              return Form(
                key: _form,
                child: LayoutBuilder(
                  builder: (context, cons) {
                    final cols = cons.maxWidth > 900
                        ? 3
                        : cons.maxWidth > 600
                        ? 2
                        : 1;
                    final w = (cons.maxWidth - 24 - (cols - 1) * 12) / cols;
                    return ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [for (final f in fields) SizedBox(width: w, child: f)],
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: _busy ? null : _save,
                          icon: const Icon(Icons.save),
                          label: const Text('حفظ'),
                        ),
                        const SizedBox(height: 40),
                      ],
                    );
                  },
                ),
              );
            },
          ),
    );
  }
}

// ---------------------------------------------------------------- detail

class SubscriberDetailScreen extends StatefulWidget {
  final String id;
  const SubscriberDetailScreen({super.key, required this.id});
  @override
  State<SubscriberDetailScreen> createState() => _SubscriberDetailScreenState();
}

class _SubscriberDetailScreenState extends State<SubscriberDetailScreen> {
  int _rev = 0;
  void _refresh() => setState(() => _rev++);

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Loader<(Map<String, Object?>, int)>(
      key: ValueKey(_rev),
      load: () async => (await app.os.subscribers.get(widget.id), await app.os.subscribers.balance(widget.id)),
      builder: (context, d, _) {
        final (s, bal) = d;
        return DefaultTabController(
          length: 5,
          child: Scaffold(
            appBar: AppBar(
              title: Text('${s['full_name']}'),
              actions: [_actions(context, app, s)],
              bottom: const TabBar(
                isScrollable: true,
                tabs: [
                  Tab(text: 'البيانات'),
                  Tab(text: 'الفواتير'),
                  Tab(text: 'المدفوعات'),
                  Tab(text: 'كشف الحساب'),
                  Tab(text: 'السجل'),
                ],
              ),
            ),
            floatingActionButton: app.can(Perm.paymentsCollect) && s['status'] != SubscriberStatus.transferred
                ? FloatingActionButton.extended(
                    onPressed: () => showPayDialog(context, s, onDone: _refresh),
                    icon: const Icon(Icons.payments),
                    label: const Text('تسجيل دفعة'),
                  )
                : null,
            body: TabBarView(
              children: [
                _info(context, s, bal),
                _InvoicesTab(subscriber: s, onChange: _refresh),
                _PaymentsTab(subscriberId: widget.id, onChange: _refresh),
                _StatementTab(subscriber: s),
                _HistoryTab(subscriberId: widget.id),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _actions(BuildContext context, AppState app, Map<String, Object?> s) {
    final id = s['id'] as String;
    return PopupMenuButton<String>(
      onSelected: (v) async {
        switch (v) {
          case 'edit':
            final ok = await Navigator.push<bool>(
              context,
              MaterialPageRoute(builder: (_) => SubscriberFormScreen(existing: s)),
            );
            if (ok == true) _refresh();
          case 'stop':
          case 'activate':
            final r = await showFormDialog(
              context,
              title: v == 'stop' ? 'إيقاف الاشتراك' : 'إعادة التفعيل',
              fields: const [FieldSpec('reason', 'السبب', required: true)],
            );
            if (r == null || !context.mounted) return;
            await guard(
              context,
              () => app.os.subscribers.setStatus(
                id,
                v == 'stop' ? SubscriberStatus.stopped : SubscriberStatus.active,
                reason: r['reason']!,
              ),
            );
            _refresh();
          case 'disconnect':
          case 'reconnect':
            final r = await showFormDialog(
              context,
              title: v == 'disconnect' ? 'فصل التيار عن المشترك' : 'إعادة الوصل',
              fields: const [FieldSpec('reason', 'السبب', required: true)],
            );
            if (r == null || !context.mounted) return;
            await guard(context, () => app.os.subscribers.setConnected(id, v == 'reconnect', reason: r['reason']!));
            _refresh();
          case 'transfer_gen':
            final gens = (await app.os.network.listGenerators()).where((g) => g['id'] != s['generator_id']).toList();
            final debt = await app.os.subscribers.balance(id);
            if (!context.mounted) return;
            if (gens.isEmpty) {
              showError(context, const DomainException('X', 'لا توجد مولدة أخرى للنقل إليها.'));
              return;
            }
            final r = await showFormDialog(
              context,
              title: 'نقل إلى مولدة أخرى',
              note:
                  'يبقى السجل المالي والدين الحالي (${money(debt)}) على المولدة الحالية، '
                  'ويُفتح سجل جديد في المولدة المختارة.',
              fields: [
                FieldSpec(
                  'gen',
                  'المولدة',
                  type: FieldType.dropdown,
                  required: true,
                  options: {for (final g in gens) g['id'] as String: g['name'] as String},
                ),
                const FieldSpec('reason', 'السبب', required: true),
              ],
            );
            if (r == null || !context.mounted) return;
            final ok = await guard(
              context,
              () => app.os.subscribers.transferToGenerator(id, r['gen']!, reason: r['reason']!),
              success: 'تم النقل',
            );
            if (ok) _refresh();
          case 'qr':
            await showDialog(
              context: context,
              builder: (c) => AlertDialog(
                title: Text('رمز QR — ${s['full_name']}'),
                content: SizedBox(
                  width: 240,
                  height: 260,
                  child: Column(
                    children: [
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.all(8),
                        child: QrImageView(data: 'GOS-S:${s['qr_token']}', size: 200),
                      ),
                      const SizedBox(height: 8),
                      Text('رقم الاشتراك ${s['account_no']}'),
                    ],
                  ),
                ),
                actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('إغلاق'))],
              ),
            );
        }
      },
      itemBuilder: (_) => [
        if (app.can(Perm.subscribersEdit)) const PopupMenuItem(value: 'edit', child: Text('تعديل البيانات')),
        if (app.can(Perm.subscribersStatus) && s['status'] == SubscriberStatus.active)
          const PopupMenuItem(value: 'stop', child: Text('إيقاف الاشتراك')),
        if (app.can(Perm.subscribersStatus) && s['status'] == SubscriberStatus.stopped)
          const PopupMenuItem(value: 'activate', child: Text('إعادة التفعيل')),
        if (app.can(Perm.subscribersStatus) && s['connected'] == 1)
          const PopupMenuItem(value: 'disconnect', child: Text('فصل التيار')),
        if (app.can(Perm.subscribersStatus) && s['connected'] == 0 && s['status'] == SubscriberStatus.active)
          const PopupMenuItem(value: 'reconnect', child: Text('إعادة الوصل')),
        if (app.can(Perm.subscribersTransfer) && s['status'] != SubscriberStatus.transferred)
          const PopupMenuItem(value: 'transfer_gen', child: Text('نقل إلى مولدة أخرى')),
        const PopupMenuItem(value: 'qr', child: Text('رمز QR للمشترك')),
      ],
    );
  }

  Widget _info(BuildContext context, Map<String, Object?> s, int bal) {
    String v(String k) => s[k] == null || '${s[k]}'.isEmpty ? '—' : '${s[k]}';
    final rows = <(String, String)>[
      ('رقم الاشتراك', v('account_no')),
      ('الحالة', SubscriberStatus.labels[s['status']] ?? v('status')),
      ('التيار', s['connected'] == 1 ? 'موصول' : 'مفصول'),
      ('الأمبيرات', v('amps')),
      ('سعر الأمبير', money(s['amp_price'] as int)),
      ('الاشتراك الشهري', money((s['amps'] as int) * (s['amp_price'] as int))),
      ('نوع الاشتراك', SubscriptionType.labels[s['subscription_type']] ?? v('subscription_type')),
      ('الهاتف', v('phone')),
      ('رقم احتياطي', v('phone2')),
      ('رقم الجوزة', v('meter_no')),
      ('المنطقة', v('area_name')),
      ('الكابينة', v('cabinet_code')),
      ('الخط', v('line_code')),
      (
        'العنوان',
        [s['province'], s['mahalla'], s['alley'], s['house']].where((x) => x != null && '$x'.isNotEmpty).join(' / '),
      ),
      ('أقرب نقطة دالة', v('landmark')),
      ('الموقع', s['lat'] == null ? '—' : '${s['lat']}, ${s['lng']}'),
      ('تاريخ الاشتراك', v('start_date')),
      ('ملاحظات', v('notes')),
    ];
    return PageBody(
      children: [
        StatGrid(
          children: [
            StatCard(
              label: bal >= 0 ? 'الدين الحالي' : 'رصيد مقدم',
              value: money(bal.abs()),
              icon: Icons.account_balance_wallet,
              color: bal > 0 ? Brand.danger : Brand.success,
            ),
            StatCard(
              label: 'الاشتراك الشهري',
              value: money((s['amps'] as int) * (s['amp_price'] as int)),
              icon: Icons.bolt,
              color: Brand.accent,
            ),
          ],
        ),
        Card(
          child: Column(
            children: [
              for (final (k, val) in rows)
                ListTile(
                  dense: true,
                  title: Text(k),
                  trailing: Text(val.isEmpty ? '—' : val, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InvoicesTab extends StatelessWidget {
  final Map<String, Object?> subscriber;
  final VoidCallback onChange;
  const _InvoicesTab({required this.subscriber, required this.onChange});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final id = subscriber['id'] as String;
    return Loader<List<Map<String, Object?>>>(
      load: () => app.os.billing.subscriberInvoices(id),
      builder: (context, rows, reload) {
        if (rows.isEmpty) return const EmptyState(icon: Icons.receipt_long, title: 'لا توجد فواتير بعد');
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            for (final i in rows)
              Card(
                child: ListTile(
                  title: Text('فاتورة ${i['period']}'),
                  subtitle: Text(
                    '${i['amps']} × ${money(i['amp_price'] as int)}'
                    '${(i['discount'] as int) > 0 ? ' · خصم ${money(i['discount'] as int)}' : ''}'
                    '${i['current_net'] != i['net'] ? ' · معدلة' : ''}',
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(money(i['current_net'] as int), style: const TextStyle(fontWeight: FontWeight.w700)),
                      StatusChip(InvoiceStatus.labels[i['status']]!, switch (i['status']) {
                        InvoiceStatus.paid => Brand.success,
                        InvoiceStatus.partial => Brand.warning,
                        _ => Brand.danger,
                      }),
                    ],
                  ),
                  onTap: () => _invoiceActions(context, app, i, reload),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _invoiceActions(BuildContext context, AppState app, Map<String, Object?> i, VoidCallback reload) async {
    final full = await app.os.billing.getInvoice(i['id'] as String);
    final gen = await app.os.network.getGenerator(full['generator_id'] as String);
    final debt = await app.os.subscribers.balance(subscriber['id'] as String);
    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.print),
              title: const Text('طباعة الفاتورة'),
              onTap: () {
                Navigator.pop(c);
                printOrShare(
                  context,
                  (p) => PdfService.invoice(full, '${gen['name']}', debt, p),
                  'invoice-${i['period']}',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: const Text('مشاركة PDF'),
              onTap: () {
                Navigator.pop(c);
                sharePdf(
                  context,
                  (p) => PdfService.invoice(full, '${gen['name']}', debt, PaperSize.a5),
                  'invoice-${subscriber['account_no']}-${i['period']}.pdf',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.chat, color: Brand.success),
              title: const Text('إرسال نص الفاتورة (واتساب)'),
              onTap: () {
                Navigator.pop(c);
                ExportService.shareText(
                  '${gen['name']}\nفاتورة شهر ${i['period']}\nالمشترك: ${subscriber['full_name']}\n'
                  'المبلغ: ${money(i['current_net'] as int)}\nالمتبقي من الفاتورة: ${money(i['unpaid'] as int)}\n'
                  'إجمالي الدين: ${money(debt)}',
                );
              },
            ),
            if (app.can(Perm.billingAdjust))
              ListTile(
                leading: const Icon(Icons.edit_note),
                title: const Text('تعديل / إعادة احتساب (بسبب موثق)'),
                onTap: () async {
                  Navigator.pop(c);
                  final v = await showFormDialog(
                    context,
                    title: 'تعديل فاتورة ${i['period']}',
                    fields: [
                      FieldSpec(
                        'net',
                        'المبلغ الجديد',
                        type: FieldType.money,
                        required: true,
                        initial: '${i['current_net']}',
                      ),
                      const FieldSpec('reason', 'سبب التعديل', required: true),
                    ],
                  );
                  if (v == null || !context.mounted) return;
                  await guard(
                    context,
                    () => app.os.billing.adjustInvoice(
                      i['id'] as String,
                      newNet: parseMoney(v['net'])!,
                      reason: v['reason']!,
                    ),
                    success: 'تم تسجيل التعديل',
                  );
                  reload();
                  onChange();
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _PaymentsTab extends StatelessWidget {
  final String subscriberId;
  final VoidCallback onChange;
  const _PaymentsTab({required this.subscriberId, required this.onChange});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Loader<List<Map<String, Object?>>>(
      load: () => app.os.collection.subscriberPayments(subscriberId),
      builder: (context, rows, reload) {
        if (rows.isEmpty) return const EmptyState(icon: Icons.payments_outlined, title: 'لا توجد مدفوعات');
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            for (final p in rows)
              Card(
                child: ListTile(
                  leading: Icon(
                    p['reversal_of'] != null ? Icons.undo : Icons.receipt,
                    color: p['reversal_of'] != null ? Brand.danger : (p['reversed'] == 1 ? Colors.grey : Brand.success),
                  ),
                  title: Text('${p['reversal_of'] != null ? 'إلغاء ' : ''}وصل ${p['receipt_no']}'),
                  subtitle: Text(
                    '${(p['paid_at'] as String).substring(0, 16).replaceFirst('T', ' ')}'
                    '${p['collector_name'] != null ? ' · ${p['collector_name']}' : ''}'
                    '${p['reversed'] == 1 ? ' · ملغاة' : ''}${p['notes'] != null ? '\n${p['notes']}' : ''}',
                  ),
                  trailing: Text(
                    money((p['amount'] as int) * (p['reversal_of'] != null ? -1 : 1)),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      decoration: p['reversed'] == 1 ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ReceiptScreen(paymentId: p['id'] as String)),
                  ),
                  onLongPress: p['reversal_of'] == null && p['reversed'] != 1 && app.can(Perm.paymentsReverse)
                      ? () async {
                          final v = await showFormDialog(
                            context,
                            title: 'إلغاء الدفعة بقيد عكسي',
                            note: 'لا تُحذف الدفعة؛ يُسجل قيد عكسي موثق ويبقى الأصل في السجل.',
                            fields: const [FieldSpec('reason', 'سبب الإلغاء', required: true)],
                            submit: 'إلغاء الدفعة',
                          );
                          if (v == null || !context.mounted) return;
                          await guard(
                            context,
                            () => app.os.collection.reversePayment(p['id'] as String, reason: v['reason']!),
                            success: 'تم إلغاء الدفعة',
                          );
                          reload();
                          onChange();
                        }
                      : null,
                ),
              ),
            if (app.can(Perm.paymentsReverse))
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('اضغط مطولاً على دفعة لإلغائها بقيد عكسي.', textAlign: TextAlign.center),
              ),
          ],
        );
      },
    );
  }
}

class _StatementTab extends StatefulWidget {
  final Map<String, Object?> subscriber;
  const _StatementTab({required this.subscriber});
  @override
  State<_StatementTab> createState() => _StatementTabState();
}

class _StatementTabState extends State<_StatementTab> {
  late String period = periodOf(DateTime.now());
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final id = widget.subscriber['id'] as String;
    return Loader<(Statement, List<Map<String, Object?>>)>(
      key: ValueKey(period),
      load: () async => (await app.os.billing.statement(id, period), await app.os.billing.subscriberInvoices(id)),
      builder: (context, d, _) {
        final (st, invs) = d;
        Widget row(String k, int v, {bool bold = false}) => ListTile(
          dense: true,
          title: Text(k, style: TextStyle(fontWeight: bold ? FontWeight.w700 : null)),
          trailing: Text(money(v), style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
        );
        return PageBody(
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => setState(() => period = previousPeriod(period)),
                  icon: const Icon(Icons.chevron_right),
                ),
                Expanded(
                  child: Center(child: Text('شهر $period', style: Theme.of(context).textTheme.titleMedium)),
                ),
                IconButton(
                  onPressed: () => setState(() => period = nextPeriod(period)),
                  icon: const Icon(Icons.chevron_left),
                ),
              ],
            ),
            Card(
              child: Column(
                children: [
                  row('الرصيد السابق', st.previousBalance),
                  row('فاتورة الشهر', st.invoiced),
                  row('الخصومات والإعفاءات', st.discounts),
                  if (st.adjustments != 0) row('تسويات', st.adjustments),
                  row('المدفوعات', st.payments),
                  const Divider(),
                  row('الرصيد المتبقي للشهر', st.closingBalance, bold: true),
                  row('إجمالي الدين الحالي', st.totalDebt, bold: true),
                ],
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.print),
                  label: const Text('طباعة الكشف'),
                  onPressed: () => printOrShare(
                    context,
                    (p) => PdfService.statement(subscriber: widget.subscriber, st: st, invoices: invs, paper: p),
                    'statement',
                  ),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('مشاركة PDF'),
                  onPressed: () => sharePdf(
                    context,
                    (p) => PdfService.statement(subscriber: widget.subscriber, st: st, invoices: invs),
                    'statement-${widget.subscriber['account_no']}-$period.pdf',
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _HistoryTab extends StatelessWidget {
  final String subscriberId;
  const _HistoryTab({required this.subscriberId});
  static const kinds = {
    'created': 'إنشاء الاشتراك',
    'status': 'تغيير الحالة',
    'disconnect': 'فصل التيار',
    'reconnect': 'إعادة الوصل',
    'transfer_out': 'نقل إلى مولدة أخرى',
    'transfer_in': 'نقل من مولدة أخرى',
    'change:amps': 'تغيير الأمبيرات',
    'change:amp_price': 'تغيير سعر الأمبير',
    'change:area_id': 'نقل منطقة',
    'change:cabinet_id': 'نقل كابينة',
    'change:line_id': 'نقل خط',
    'change:subscription_type': 'تغيير نوع الاشتراك',
  };
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Loader<List<Map<String, Object?>>>(
      load: () => app.os.subscribers.history(subscriberId),
      builder: (context, rows, _) => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final e in rows)
            Card(
              child: ListTile(
                leading: const Icon(Icons.history),
                title: Text(kinds[e['kind']] ?? '${e['kind']}'),
                subtitle: Text(
                  [
                    (e['at'] as String).substring(0, 16).replaceFirst('T', ' '),
                    if (e['from_value'] != null || e['to_value'] != null)
                      '${e['from_value'] ?? ''} ← ${e['to_value'] ?? ''}',
                    if (e['reason'] != null) 'السبب: ${e['reason']}',
                    if (e['user_name'] != null) 'بواسطة ${e['user_name']}',
                  ].join('\n'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
