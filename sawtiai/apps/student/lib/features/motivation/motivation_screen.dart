import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';

class MotivationScreen extends ConsumerWidget {
  const MotivationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final repo = ref.watch(repositoryProvider);
    final today = repo.todaysMotivation;
    final previous = repo.motivations.where((m) => m.id != today?.id).toList();
    return EnjazPage(
      title: l.motivation,
      body: today == null
          ? EmptyState(icon: Icons.wb_sunny_outlined, message: l.noMotivation)
          : ListView(padding: const EdgeInsets.all(16), children: [
              Text(l.dailyMotivation, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              _MotivationCard(m: today, big: true),
              if (previous.isNotEmpty) SectionHeader(title: l.previousMotivation),
              for (final m in previous) Padding(padding: const EdgeInsets.only(bottom: 10), child: _MotivationCard(m: m)),
            ]),
    );
  }
}

class _MotivationCard extends ConsumerWidget {
  const _MotivationCard({required this.m, this.big = false});
  final Motivation m;
  final bool big;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final img = ref.read(backendProvider).publicImageUrl(m.imagePath);
    return GlassCard(
      padding: EdgeInsets.zero,
      gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [
        EnjazColors.violet.withValues(alpha: big ? 0.6 : 0.35),
        EnjazColors.primary.withValues(alpha: big ? 0.45 : 0.25),
      ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (img != null)
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(EnjazRadii.card)),
            child: Image.network(img, height: big ? 200 : 120, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
          ),
        Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (m.title != null) Text(m.title!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 6),
            Text(m.body, style: TextStyle(color: Colors.white, fontSize: big ? 19 : 15, height: 1.7, fontWeight: FontWeight.w600)),
            if (m.author != null && m.authorVerified) ...[
              const SizedBox(height: 8),
              Text('— ${m.author}', style: const TextStyle(color: Colors.white70)),
            ],
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: IconButton(
                tooltip: l.share,
                icon: const Icon(Icons.share_rounded, color: Colors.white),
                onPressed: () => SharePlus.instance.share(ShareParams(
                    text: '${m.body}${m.author != null && m.authorVerified ? '\n— ${m.author}' : ''}\n\n${l.appName} • ${l.slogan}')),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
