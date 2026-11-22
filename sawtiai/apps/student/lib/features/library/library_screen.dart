import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../../app/providers.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

enum _Tab { all, downloaded, favorites, recent }

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String _query = '';
  String? _category;
  String? _subject;
  _Tab _tab = _Tab.all;
  final Map<String, double> _progress = {};

  Future<void> _open(LibraryFile f) async {
    final repo = ref.read(repositoryProvider);
    final l = context.l10n;
    final d = repo.download(f.id);
    String? path = d?['local_path'] as String?;
    if (path == null || !File(path).existsSync()) {
      final backend = ref.read(backendProvider);
      if (!backend.signedIn) {
        showEnjazSnack(context, l.needOnlineToDownload, error: true);
        return;
      }
      setState(() => _progress[f.id] = 0);
      try {
        path = await backend.downloadLibraryFile(
            fileId: f.id, storagePath: f.storagePath, title: f.title,
            onProgress: (p) => mounted ? setState(() => _progress[f.id] = p) : null);
      } catch (_) {
        if (mounted) showEnjazSnack(context, l.needOnlineToDownload, error: true);
        return;
      } finally {
        if (mounted) setState(() => _progress.remove(f.id));
      }
    }
    await repo.updateDownload(f.id, {'last_opened_at': DateTime.now().toIso8601String()});
    await OpenFilex.open(path);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final repo = ref.watch(repositoryProvider);
    final mySubjectIds = repo.mySubjects.map((s) => s.id).toSet();
    var files = repo.libraryFiles.where((f) => f.subjectId == null || mySubjectIds.contains(f.subjectId)).toList();
    if (_category != null) files = files.where((f) => f.categoryId == _category).toList();
    if (_subject != null) files = files.where((f) => f.subjectId == _subject).toList();
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      files = files.where((f) => f.title.toLowerCase().contains(q) || (f.description ?? '').toLowerCase().contains(q)).toList();
    }
    switch (_tab) {
      case _Tab.downloaded:
        files = files.where((f) => repo.download(f.id) != null).toList();
      case _Tab.favorites:
        files = files.where((f) => repo.download(f.id)?['favorite'] == 1).toList();
      case _Tab.recent:
        files = files.where((f) => repo.download(f.id)?['last_opened_at'] != null).toList()
          ..sort((a, b) => (repo.download(b.id)!['last_opened_at'] as String).compareTo(repo.download(a.id)!['last_opened_at'] as String));
      case _Tab.all:
        break;
    }
    final cats = repo.libraryCategories;
    return EnjazPage(
      title: l.myLibrary,
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        TextField(
          decoration: InputDecoration(hintText: l.search, prefixIcon: const Icon(Icons.search_rounded)),
          onChanged: (v) => setState(() => _query = v.trim()),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final (t, label) in [(_Tab.all, l.allTypes), (_Tab.downloaded, l.downloaded), (_Tab.favorites, l.favorites), (_Tab.recent, l.readingHistory)])
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(label: Text(label), selected: _tab == t, onSelected: (_) => setState(() => _tab = t)),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String?>(
              initialValue: _category,
              isExpanded: true,
              decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              items: [
                DropdownMenuItem(value: null, child: Text(l.allTypes)),
                for (final c in cats) DropdownMenuItem(value: c['id'] as String, child: Text(c['name_ar'] as String)),
              ],
              onChanged: (v) => setState(() => _category = v),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonFormField<String?>(
              initialValue: _subject,
              isExpanded: true,
              decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              items: [
                DropdownMenuItem(value: null, child: Text(l.subjectsTab)),
                for (final s in repo.mySubjects) DropdownMenuItem(value: s.id, child: Text(s.nameAr)),
              ],
              onChanged: (v) => setState(() => _subject = v),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        if (files.isEmpty) EmptyState(icon: Icons.local_library_outlined, message: l.noFiles),
        for (final f in files)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _FileTile(file: f, progress: _progress[f.id], onOpen: () => _open(f)),
          ),
      ]),
    );
  }
}

class _FileTile extends ConsumerWidget {
  const _FileTile({required this.file, required this.progress, required this.onOpen});
  final LibraryFile file;
  final double? progress;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final repo = ref.read(repositoryProvider);
    final d = repo.download(file.id);
    final cover = ref.read(backendProvider).publicImageUrl(file.coverPath);
    final subject = repo.subject(file.subjectId);
    return GlassCard(
      key: ValueKey('file_${file.id}'),
      radius: EnjazRadii.tile,
      padding: const EdgeInsets.all(12),
      onTap: progress == null ? onOpen : null,
      child: Row(children: [
        Container(
          width: 54,
          height: 70,
          decoration: BoxDecoration(color: EnjazColors.primary.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
          clipBehavior: Clip.antiAlias,
          child: cover != null
              ? Image.network(cover, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.picture_as_pdf_rounded))
              : Icon(file.isPdf ? Icons.picture_as_pdf_rounded : Icons.image_rounded, color: EnjazColors.cyan),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(file.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text([
              if (subject != null) subject.nameAr,
              l.fileSize(formatBytes(file.sizeBytes)),
              if (file.publishedAt != null) formatDay(l, file.publishedAt!, withWeekday: false, withYear: true),
            ].join(' • '), style: TextStyle(fontSize: 11.5, color: context.mutedText)),
            if (progress != null) ...[
              const SizedBox(height: 6),
              LinearProgressIndicator(value: progress == 0 ? null : progress),
            ] else if (d != null)
              Text(l.downloaded, style: const TextStyle(fontSize: 11.5, color: EnjazColors.success)),
          ]),
        ),
        if (d != null)
          IconButton(
            tooltip: l.favorites,
            icon: Icon(d['favorite'] == 1 ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: d['favorite'] == 1 ? EnjazColors.danger : null),
            onPressed: () => repo.updateDownload(file.id, {'favorite': d['favorite'] == 1 ? 0 : 1}),
          )
        else
          Icon(Icons.download_rounded, color: context.mutedText),
      ]),
    );
  }
}
