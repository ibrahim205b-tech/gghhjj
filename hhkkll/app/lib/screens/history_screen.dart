import 'package:flutter/material.dart';

import '../app.dart';
import '../services/controller.dart';
import '../theme.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  static String _date(DateTime d) {
    final l = d.toLocal();
    return '${l.year}/${l.month.toString().padLeft(2, '0')}/${l.day.toString().padLeft(2, '0')} '
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final h = c.history;
    final wins = <String, int>{};
    for (final m in h) {
      if (m.players.isNotEmpty) wins.update(m.players.first.name, (v) => v + 1, ifAbsent: () => 1);
    }
    final champs = wins.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Scaffold(
      appBar: AppBar(
        title: const Text('إحصائيات المباريات'),
        actions: [
          if (h.isNotEmpty)
            IconButton(
              tooltip: 'مسح السجل',
              icon: const Icon(Icons.delete_sweep_rounded),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('مسح كل الإحصائيات؟'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('مسح')),
                    ],
                  ),
                );
                if (ok == true) await c.clearHistory();
              },
            ),
        ],
      ),
      body: h.isEmpty
          ? const Center(child: Text('لا توجد مباريات منتهية بعد', style: TextStyle(color: C.muted)))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${h.length} مباراة', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                      const SizedBox(height: 8),
                      for (final e in champs.take(5))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(children: [
                            const Icon(Icons.emoji_events_rounded, color: C.gold, size: 18),
                            const SizedBox(width: 6),
                            Expanded(child: Text(e.key)),
                            Text('${e.value} فوز', style: const TextStyle(color: C.muted)),
                          ]),
                        ),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                for (final m in h) _MatchTile(m: m, date: _date(m.finishedAt)),
              ],
            ),
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({required this.m, required this.date});
  final MatchRecord m;
  final String date;
  @override
  Widget build(BuildContext context) => Card(
        child: ExpansionTile(
          shape: const Border(),
          leading: const Icon(Icons.emoji_events_rounded, color: C.gold),
          title: Text(m.players.isEmpty ? '-' : 'الفائز: ${m.players.first.name}', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('$date · ${m.players.length} لاعبين · ${m.questions} سؤال', style: const TextStyle(color: C.muted, fontSize: 12)),
          children: [
            for (final (i, p) in m.players.indexed)
              ListTile(
                dense: true,
                leading: Text('${i + 1}', style: const TextStyle(fontFamily: 'Display', fontSize: 16)),
                title: Text(p.name),
                subtitle: Text('صحيحة ${p.correct} · خاطئة ${p.wrong} · مزاد ${p.auctionsWon} · جرس ${p.firstBuzzes}',
                    style: const TextStyle(fontSize: 11, color: C.muted)),
                trailing: Text('${p.score}', textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w700, color: C.gold)),
              ),
          ],
        ),
      );
}
