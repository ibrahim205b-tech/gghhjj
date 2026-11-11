import 'package:flutter/material.dart';
import 'package:generator_core/generator_core.dart';

import '../../app_state.dart';
import '../../theme.dart';
import '../common.dart';

class ComplaintsScreen extends StatefulWidget {
  const ComplaintsScreen({super.key});
  @override
  State<ComplaintsScreen> createState() => _ComplaintsScreenState();
}

class _ComplaintsScreenState extends State<ComplaintsScreen> {
  int _rev = 0;
  bool _archived = false;
  String? _status;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final g = app.generatorId!;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_comment),
        label: const Text('شكوى / طلب'),
        onPressed: () => _create(context, app, g),
      ),
      body: Loader<(List<Map<String, Object?>>, List<Map<String, Object?>>)>(
        key: ValueKey('$_rev$_archived$_status'),
        load: () async =>
            (await app.os.complaints.list(g, archived: _archived, status: _status), await app.os.complaints.byArea(g)),
        builder: (context, d, _) {
          final (rows, byArea) = d;
          return PageBody(
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in ComplaintService.statuses.entries)
                    ChoiceChip(
                      label: Text(e.value),
                      selected: _status == e.key,
                      onSelected: (v) => setState(() => _status = v ? e.key : null),
                    ),
                  FilterChip(
                    label: const Text('المؤرشفة'),
                    selected: _archived,
                    onSelected: (v) => setState(() => _archived = v),
                  ),
                ],
              ),
              if (byArea.isNotEmpty)
                Section(
                  title: 'المناطق الأكثر شكاوى',
                  child: Column(
                    children: [
                      for (final a in byArea.take(5))
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('${a['area']}'),
                          trailing: Text('${a['count']} (مفتوحة ${a['open']})'),
                        ),
                    ],
                  ),
                ),
              if (rows.isEmpty) const EmptyState(icon: Icons.mark_chat_read, title: 'لا توجد شكاوى'),
              for (final c in rows)
                Card(
                  child: ListTile(
                    leading: Icon(Icons.forum, color: c['status'] == 'resolved' ? Brand.success : Brand.warning),
                    title: Text('${c['ticket_no']} — ${c['title']}'),
                    subtitle: Text(
                      [
                        ComplaintService.categories[c['category']] ?? '',
                        'أولوية ${ComplaintService.priorities[c['priority']]}',
                        if (c['subscriber_name'] != null) '${c['subscriber_name']}',
                        (c['opened_at'] as String).substring(0, 10),
                      ].join(' · '),
                    ),
                    trailing: StatusChip(
                      ComplaintService.statuses[c['status']] ?? '',
                      c['status'] == 'resolved' ? Brand.success : Brand.warning,
                    ),
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => _ComplaintDetail(c)));
                      setState(() => _rev++);
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _create(BuildContext context, AppState app, String g) async {
    final subs = await app.os.subscribers.search(g, const SubscriberFilter(), limit: 1000);
    if (!context.mounted) return;
    final v = await showFormDialog(
      context,
      title: 'تسجيل شكوى أو طلب',
      fields: [
        const FieldSpec(
          'category',
          'التصنيف',
          type: FieldType.dropdown,
          required: true,
          options: ComplaintService.categories,
        ),
        const FieldSpec('title', 'العنوان', required: true),
        const FieldSpec('body', 'التفاصيل', type: FieldType.multiline),
        FieldSpec(
          'sub',
          'المشترك',
          type: FieldType.dropdown,
          options: {for (final s in subs) s['id'] as String: '${s['account_no']} — ${s['full_name']}'},
        ),
        const FieldSpec(
          'priority',
          'الأولوية',
          type: FieldType.dropdown,
          required: true,
          initial: 'normal',
          options: ComplaintService.priorities,
        ),
        const FieldSpec('assignee', 'المسؤول عن المعالجة'),
      ],
    );
    if (v == null || !context.mounted) return;
    await guard(
      context,
      () => app.os.complaints.create(
        generatorId: g,
        category: v['category']!,
        title: v['title']!,
        body: emptyToNull(v['body']),
        subscriberId: emptyToNull(v['sub']),
        priority: v['priority']!,
        assignee: emptyToNull(v['assignee']),
      ),
      success: 'تم تسجيل الشكوى',
    );
    setState(() => _rev++);
  }
}

class _ComplaintDetail extends StatefulWidget {
  final Map<String, Object?> c;
  const _ComplaintDetail(this.c);
  @override
  State<_ComplaintDetail> createState() => _ComplaintDetailState();
}

class _ComplaintDetailState extends State<_ComplaintDetail> {
  final _reply = TextEditingController();
  int _rev = 0;
  late String status = widget.c['status'] as String;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final id = widget.c['id'] as String;
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.c['ticket_no']}'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'archive') {
                await guard(context, () => app.os.complaints.archive(id));
                if (context.mounted) Navigator.pop(context);
                return;
              }
              await guard(context, () => app.os.complaints.setStatus(id, v));
              setState(() => status = v);
            },
            itemBuilder: (_) => [
              for (final e in ComplaintService.statuses.entries)
                PopupMenuItem(value: e.key, child: Text('تحويل إلى: ${e.value}')),
              const PopupMenuItem(value: 'archive', child: Text('أرشفة')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Loader<List<Map<String, Object?>>>(
              key: ValueKey(_rev),
              load: () => app.os.complaints.replies(id),
              builder: (context, rows, _) => ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Card(
                    child: ListTile(
                      title: Text('${widget.c['title']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        '${widget.c['body'] ?? ''}\n'
                        'الحالة: ${ComplaintService.statuses[status]} · المسؤول: ${widget.c['assignee'] ?? '—'}',
                      ),
                    ),
                  ),
                  for (final r in rows)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.reply),
                        title: Text('${r['body']}'),
                        subtitle: Text(
                          '${r['full_name'] ?? ''} · ${(r['at'] as String).substring(0, 16).replaceFirst('T', ' ')}',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _reply,
                      decoration: const InputDecoration(hintText: 'اكتب رداً أو إجراءً'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    icon: const Icon(Icons.send),
                    onPressed: () async {
                      if (_reply.text.trim().isEmpty) return;
                      final ok = await guard(context, () => app.os.complaints.reply(id, _reply.text));
                      if (ok) {
                        _reply.clear();
                        setState(() {
                          _rev++;
                          if (status == 'open') status = 'in_progress';
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
