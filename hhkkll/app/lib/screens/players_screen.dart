import 'package:flutter/material.dart';

import '../app.dart';
import '../theme.dart';

Future<String?> askName(BuildContext context, {String initial = '', String title = 'اسم اللاعب'}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        key: const Key('name-field'),
        controller: ctl,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (v) => Navigator.pop(ctx, v),
        decoration: const InputDecoration(hintText: 'مثال: أحمد'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(
          key: const Key('name-ok'),
          onPressed: () => Navigator.pop(ctx, ctl.text),
          child: const Text('حفظ'),
        ),
      ],
    ),
  );
}

class PlayersScreen extends StatelessWidget {
  const PlayersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة اللاعبين')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add-player'),
        backgroundColor: C.gold,
        foregroundColor: Colors.black,
        onPressed: () async {
          final n = await askName(context, title: 'إضافة لاعب');
          if (n != null) await c.addRosterPlayer(n);
        },
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('إضافة لاعب', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: c.roster.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('لا يوجد لاعبون بعد.\nأضف المتنافسين لتبدأ المنافسة.',
                    textAlign: TextAlign.center, style: TextStyle(color: C.muted, height: 1.8)),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              itemCount: c.roster.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final p = c.roster[i];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: C.player(i).withValues(alpha: .2),
                      child: Text(p.name.characters.first,
                          style: TextStyle(color: C.player(i), fontWeight: FontWeight.w700)),
                    ),
                    title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: 'تعديل الاسم',
                        icon: const Icon(Icons.edit_rounded, color: C.muted),
                        onPressed: () async {
                          final n = await askName(context, initial: p.name, title: 'تعديل الاسم');
                          if (n != null) await c.renameRosterPlayer(p.id, n);
                        },
                      ),
                      IconButton(
                        tooltip: 'حذف',
                        icon: const Icon(Icons.delete_outline_rounded, color: C.red),
                        onPressed: () => c.removeRosterPlayer(p.id),
                      ),
                    ]),
                  ),
                );
              },
            ),
    );
  }
}

/// Small helper used by several screens.
class EmptyHint extends StatelessWidget {
  const EmptyHint(this.text, {super.key, this.icon = Icons.info_outline_rounded});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: C.muted, size: 40),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: C.muted, height: 1.7)),
        ]),
      );
}

