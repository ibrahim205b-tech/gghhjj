import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../services/file_actions.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'generate.dart';
import 'player.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final items = s.library;
    return SawtiScaffold(
      title: 'مكتبتي الصوتية',
      body: items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.library_music_outlined, size: 72, color: context.muted),
                  const SizedBox(height: 12),
                  const Text('المكتبة فارغة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text('الملفات التي تولدها تُحفظ هنا على جهازك.', style: TextStyle(color: context.muted)),
                  const SizedBox(height: 20),
                  GradientButton(
                    expanded: false,
                    label: 'ولّد أول ملف',
                    icon: Icons.graphic_eq_rounded,
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GenerateScreen())),
                  ),
                ]),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: items.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, idx) {
                if (idx == 0) {
                  final total = items.fold<int>(0, (a, i) => a + i.sizeBytes);
                  return Text('${items.length} ملف • ${formatBytes(total)} على الجهاز', style: TextStyle(color: context.muted));
                }
                return _LibraryTile(item: items[idx - 1]);
              },
            ),
    );
  }
}

class _LibraryTile extends StatelessWidget {
  const _LibraryTile({required this.item});
  final LibraryItem item;

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    void open() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerScreen(item: item)));
    return GlassCard(
      key: ValueKey('lib_${item.id}'),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
      onTap: open,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(gradient: SawtiColors.brandGradient, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.graphic_eq_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(formatDate(item.createdAt), style: TextStyle(color: context.muted, fontSize: 12)),
              Text('${formatDuration(Duration(milliseconds: item.durationMs))} • ${formatBytes(item.sizeBytes)} • ${item.voiceName}',
                  style: TextStyle(color: context.muted, fontSize: 12)),
            ]),
          ),
        ]),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          IconButton(tooltip: 'تشغيل', icon: const Icon(Icons.play_circle_fill_rounded), onPressed: open),
          IconButton(
            tooltip: 'مشاركة',
            icon: const Icon(Icons.share_rounded),
            onPressed: () async {
              try {
                await shareItem(item);
              } catch (_) {
                if (context.mounted) showSnack(context, 'تعذرت المشاركة', error: true);
              }
            },
          ),
          IconButton(
            tooltip: 'حفظ',
            icon: const Icon(Icons.download_rounded),
            onPressed: () async {
              try {
                if (await saveCopy(item) && context.mounted) showSnack(context, 'تم حفظ الملف');
              } catch (_) {
                if (context.mounted) showSnack(context, 'تعذر الحفظ', error: true);
              }
            },
          ),
          IconButton(
            key: ValueKey('delete_${item.id}'),
            tooltip: 'حذف',
            icon: const Icon(Icons.delete_outline_rounded, color: SawtiColors.danger),
            onPressed: () async {
              if (await confirmDialog(context, title: 'حذف التسجيل', body: 'سيُحذف «${item.title}» نهائياً من جهازك.')) {
                await s.deleteLibraryItem(item);
              }
            },
          ),
        ]),
      ]),
    );
  }
}
