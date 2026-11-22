import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';

Future<void> _open(String? url) async {
  if (url == null) return;
  final uri = Uri.tryParse(url);
  if (uri == null || !(uri.scheme == 'https')) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Update prompt driven by app_versions (managed in the admin dashboard).
/// Never installs silently: it only opens the official download / store / Telegram link.
Future<void> maybeShowUpdatePrompt(BuildContext context, WidgetRef ref, int currentBuild) async {
  final repo = ref.read(repositoryProvider);
  final v = repo.latestVersion;
  if (v == null || currentBuild <= 0 || v.buildNumber <= currentBuild) return;
  final mandatory = v.isMandatory || currentBuild < v.minSupportedBuild;
  final dismissedKey = 'update_dismissed_${v.buildNumber}';
  if (!mandatory && repo.kv(dismissedKey) != null) return;
  final l = context.l10n;
  final backend = ref.read(backendProvider);
  final image = backend.publicImageUrl(v.imagePath);
  await showDialog<void>(
    context: context,
    barrierDismissible: !mandatory,
    builder: (c) => PopScope(
      canPop: !mandatory,
      child: AlertDialog(
        title: Text(l.newUpdate),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (image != null)
              ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.network(image, errorBuilder: (_, _, _) => const SizedBox())),
            const SizedBox(height: 12),
            Text(l.updateBody, style: const TextStyle(height: 1.6)),
            if (v.description != null) ...[const SizedBox(height: 8), Text(v.description!, style: TextStyle(color: c.mutedText, height: 1.6))],
            if (mandatory) ...[const SizedBox(height: 8), Text(l.updateMandatory, style: const TextStyle(color: EnjazColors.warning))],
            const SizedBox(height: 6),
            Text('v${v.versionName}', textDirection: TextDirection.ltr, style: TextStyle(color: c.mutedText, fontSize: 12)),
          ]),
        ),
        actions: [
          if (!mandatory)
            TextButton(
              onPressed: () {
                repo.setKv(dismissedKey, '1');
                Navigator.pop(c);
              },
              child: Text(l.later),
            ),
          if (v.telegramUrl != null) TextButton(onPressed: () => _open(v.telegramUrl), child: Text(l.openTelegram)),
          FilledButton(onPressed: () => _open(v.playStoreUrl ?? v.downloadUrl ?? v.telegramUrl), child: Text(l.updateNow)),
        ],
      ),
    ),
  );
}

/// Shows announcements according to their display frequency.
Future<void> showPendingAnnouncements(BuildContext context, WidgetRef ref) async {
  final repo = ref.read(repositoryProvider);
  final seen = ((jsonDecode(repo.kv('announcements_seen') ?? '{}') as Map)).cast<String, dynamic>();
  for (final a in repo.announcements.take(5)) {
    final state = seen[a.id] as String?; // null | seen | acked
    final show = switch (a.frequency) {
      DisplayFrequency.once => state == null,
      DisplayFrequency.untilAcknowledged => state != 'acked',
      DisplayFrequency.everyLaunch => true,
    };
    if (!show || !context.mounted) continue;
    final acked = await showAnnouncementDialog(context, ref, a);
    seen[a.id] = acked ? 'acked' : 'seen';
    await repo.setKv('announcements_seen', jsonEncode(seen));
    await ref.read(backendProvider).markAnnouncementSeen(a.id, acknowledged: acked);
  }
}

/// Returns true when the student acknowledged it.
Future<bool> showAnnouncementDialog(BuildContext context, WidgetRef ref, Announcement a) async {
  final l = context.l10n;
  final image = ref.read(backendProvider).publicImageUrl(a.imagePath);
  final mustAck = a.requiresAck || a.frequency == DisplayFrequency.untilAcknowledged;
  final r = await showDialog<bool>(
    context: context,
    barrierDismissible: !mustAck,
    builder: (c) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            if (image != null) Image.network(image, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                StatusChip(label: l.announcement, color: EnjazColors.cyan),
                const SizedBox(height: 10),
                Text(a.title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                if (a.description != null) ...[
                  const SizedBox(height: 8),
                  Text(a.description!, style: TextStyle(height: 1.7, color: c.mutedText)),
                ],
                const SizedBox(height: 18),
                if (a.actionUrl != null && a.actionUrl!.startsWith('https://'))
                  GlowButton(
                      label: a.actionLabel ?? l.open,
                      gradient: EnjazColors.planGradient,
                      onPressed: () => _open(a.actionUrl)),
                if (a.telegramUrl != null) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => _open(a.telegramUrl),
                    icon: const Icon(Icons.send_rounded),
                    label: Text(l.openTelegram),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  ),
                ],
                const SizedBox(height: 6),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  if (!mustAck) TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.dismiss)),
                  FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(l.gotIt)),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    ),
  );
  return r ?? false;
}
