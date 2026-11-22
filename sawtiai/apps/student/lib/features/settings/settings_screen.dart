import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../services/backend.dart';
import '../common/shared.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((p) => mounted ? setState(() => _version = '${p.version} (${p.buildNumber})') : null).catchError((_) => null);
  }

  Future<void> _editName() async {
    final l = context.l10n;
    final repo = ref.read(repositoryProvider);
    final ctl = TextEditingController(text: repo.profile.displayName);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l.editProfile),
        content: TextField(controller: ctl, maxLength: 40, decoration: InputDecoration(labelText: l.displayName)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(l.save)),
        ],
      ),
    );
    if (ok == true && ctl.text.trim().isNotEmpty) {
      await repo.saveProfile(repo.profile..displayName = ctl.text.trim());
      ref.read(backendProvider).sync();
    }
  }

  Future<void> _export() async {
    final l = context.l10n;
    final repo = ref.read(repositoryProvider);
    final backend = ref.read(backendProvider);
    Map<String, dynamic> data = repo.exportLocal();
    try {
      final cloud = await backend.exportCloudData();
      if (cloud != null) data = {'local': data, 'cloud': cloud};
    } catch (_) {}
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/enjaz-data-${DateTime.now().millisecondsSinceEpoch}.json');
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    if (!mounted) return;
    showEnjazSnack(context, l.exportReady);
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'application/json')], title: l.exportData));
  }

  Future<void> _deleteAccount() async {
    final l = context.l10n;
    final ok = await confirmDialog(context, title: l.deleteAccount, body: l.deleteAccountBody, ok: l.delete, cancel: l.cancel, danger: true);
    if (!ok) return;
    try {
      await ref.read(backendProvider).deleteAccount();
      if (!mounted) return;
      showEnjazSnack(context, l.accountDeleted);
      context.go('/onboarding');
    } catch (_) {
      if (mounted) showEnjazSnack(context, l.errorGeneric, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final repo = ref.watch(repositoryProvider);
    final backend = ref.watch(backendProvider);
    final p = repo.profile;
    final prefs = repo.preferences;
    final g = repo.grade(p.gradeId);
    final b = repo.branch(p.branchId);
    final year = repo.years.where((y) => y.id == p.yearId).firstOrNull;
    Widget sw(String key, String label) => SwitchListTile(
          title: Text(label),
          value: prefs[key] != false,
          onChanged: (v) => repo.setPreference(key, v),
        );
    return EnjazPage(
      title: l.settings,
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        GlassCard(
          blur: true,
          child: Row(children: [
            ProfileAvatar(name: p.displayName, url: p.avatarUrl, size: 56),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.displayName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text(backend.signedIn && !backend.isAnonymous ? (backend.user?.email ?? '') : l.localAccount,
                    style: TextStyle(color: context.mutedText, fontSize: 12.5)),
              ]),
            ),
            IconButton(tooltip: l.editProfile, onPressed: _editName, icon: const Icon(Icons.edit_rounded)),
          ]),
        ),
        _Section(title: l.academicInfo, children: [
          ListTile(
            leading: const Icon(Icons.school_rounded),
            title: Text([g?.nameAr, b?.nameAr].whereType<String>().join(' • ')),
            subtitle: Text([year?.label, p.governorate].whereType<String>().join(' • ')),
            trailing: TextButton(onPressed: () => context.push('/settings/academic'), child: Text(l.changeYear)),
          ),
        ]),
        _Section(title: l.notifications, children: [
          sw('notify_motivation', l.motivationNotifications),
          sw('notify_study', l.studyReminders),
          sw('notify_exams', l.examReminders),
          sw('notify_announcements', l.announcementNotifications),
        ]),
        _Section(title: l.theme, children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'dark', label: Text(l.themeDark), icon: const Icon(Icons.dark_mode_rounded)),
                ButtonSegment(value: 'light', label: Text(l.themeLight), icon: const Icon(Icons.light_mode_rounded)),
                ButtonSegment(value: 'system', label: Text(l.themeSystem)),
              ],
              selected: {prefs['theme_mode'] as String? ?? 'dark'},
              onSelectionChanged: (v) => repo.setPreference('theme_mode', v.first),
            ),
          ),
        ]),
        _Section(title: l.cloudSync, children: [
          if (backend.signedIn) ...[
            sw('cloud_sync_enabled', l.cloudSync),
            ListTile(
              leading: Icon(backend.syncState == SyncState.syncing ? Icons.sync_rounded : Icons.cloud_done_rounded),
              title: Text(backend.syncState == SyncState.syncing ? l.syncing : l.syncNow),
              subtitle: Text(backend.lastSyncAt == null ? l.neverSynced : l.lastSync(formatDay(l, backend.lastSyncAt!))),
              onTap: () async {
                final r = await backend.sync();
                if (context.mounted) showEnjazSnack(context, r.error == null ? l.syncDone : l.syncFailed, error: r.error != null);
              },
            ),
          ] else
            ListTile(
              leading: const Icon(Icons.cloud_off_rounded),
              title: Text(l.localAccount),
              subtitle: Text(l.offlineModeNote),
              trailing: backend.configured
                  ? TextButton(onPressed: () => backend.signInWithGoogle(), child: Text(l.signIn))
                  : null,
            ),
          if (backend.signedIn && backend.isAnonymous && backend.configured)
            ListTile(
              leading: const Icon(Icons.account_circle_rounded),
              title: Text(l.signInGoogle),
              onTap: () => backend.signInWithGoogle(),
            ),
        ]),
        _Section(title: l.privacy, children: [
          ListTile(leading: const Icon(Icons.download_rounded), title: Text(l.exportData), onTap: _export),
          ListTile(
            leading: const Icon(Icons.privacy_tip_rounded),
            title: Text(l.privacy),
            onTap: () => showDialog<void>(
              context: context,
              builder: (c) => AlertDialog(title: Text(l.privacy), content: Text(l.privacyBody, style: const TextStyle(height: 1.7)),
                  actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(l.close))]),
            ),
          ),
          if (backend.signedIn)
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: Text(l.signOut),
              onTap: () async {
                final ok = await confirmDialog(context, title: l.signOut, body: l.areYouSure, ok: l.signOut, cancel: l.cancel);
                if (!ok) return;
                await backend.signOut();
                if (context.mounted) context.go('/onboarding');
              },
            ),
          ListTile(
            key: const Key('delete_account'),
            leading: const Icon(Icons.delete_forever_rounded, color: EnjazColors.danger),
            title: Text(l.deleteAccount, style: const TextStyle(color: EnjazColors.danger)),
            onTap: _deleteAccount,
          ),
        ]),
        const SizedBox(height: 16),
        Center(child: Text(l.appVersion(_version), style: TextStyle(color: context.mutedText, fontSize: 12))),
        Center(child: Text(l.slogan, style: TextStyle(color: context.mutedText, fontSize: 12))),
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionHeader(title: title),
        GlassCard(padding: const EdgeInsets.symmetric(vertical: 6), child: Column(children: children)),
      ]);
}
