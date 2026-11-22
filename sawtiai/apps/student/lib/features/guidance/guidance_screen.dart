import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// Universities → colleges → specializations with admission info. Every
/// admission figure shows its source and last-updated date; only rows the
/// admin marked official (with a verification date) carry the official badge.
class GuidanceScreen extends ConsumerStatefulWidget {
  const GuidanceScreen({super.key});

  @override
  ConsumerState<GuidanceScreen> createState() => _GuidanceScreenState();
}

class _GuidanceScreenState extends ConsumerState<GuidanceScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final repo = ref.watch(repositoryProvider);
    final unis = repo.content('universities')
        .where((u) => _q.isEmpty || (u['name_ar'] as String).contains(_q) || ((u['governorate'] as String?) ?? '').contains(_q))
        .toList()
      ..sort((a, b) => (a['name_ar'] as String).compareTo(b['name_ar'] as String));
    final colleges = repo.content('colleges');
    final specs = repo.content('specializations');
    final admissions = repo.content('admission_information');
    return EnjazPage(
      title: l.guidance,
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(l.guidanceIntro, style: TextStyle(color: context.mutedText)),
        const SizedBox(height: 10),
        TextField(decoration: InputDecoration(hintText: l.search, prefixIcon: const Icon(Icons.search_rounded)), onChanged: (v) => setState(() => _q = v.trim())),
        const SizedBox(height: 12),
        if (unis.isEmpty) EmptyState(icon: Icons.school_outlined, message: l.noGuidance),
        for (final u in unis)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassCard(
              padding: EdgeInsets.zero,
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  leading: const Icon(Icons.account_balance_rounded, color: EnjazColors.cyan),
                  title: Text(u['name_ar'] as String, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text([u['governorate'] as String?, _kind(l, u['kind'] as String?)].whereType<String>().join(' • '), style: TextStyle(color: context.mutedText, fontSize: 12)),
                  children: [
                    if (u['website'] != null)
                      ListTile(
                        leading: const Icon(Icons.public_rounded),
                        title: Text(u['website'] as String, textDirection: TextDirection.ltr),
                        onTap: () => launchUrl(Uri.parse(u['website'] as String), mode: LaunchMode.externalApplication),
                      ),
                    for (final c in colleges.where((c) => c['university_id'] == u['id']))
                      ExpansionTile(
                        title: Text(c['name_ar'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                        children: [
                          for (final s in specs.where((s) => s['college_id'] == c['id']))
                            _SpecTile(spec: s, admissions: admissions.where((a) => a['specialization_id'] == s['id']).toList()),
                          for (final a in admissions.where((a) => a['college_id'] == c['id'] && a['specialization_id'] == null))
                            _AdmissionRow(a: a),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class _SpecTile extends StatelessWidget {
  const _SpecTile({required this.spec, required this.admissions});
  final Map<String, dynamic> spec;
  final List<Map<String, dynamic>> admissions;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(spec['name_ar'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (spec['description'] != null) Text(spec['description'] as String, style: TextStyle(color: context.mutedText, fontSize: 12.5)),
          for (final a in admissions) _AdmissionRow(a: a),
        ]),
      );
}

class _AdmissionRow extends StatelessWidget {
  const _AdmissionRow({required this.a});
  final Map<String, dynamic> a;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final official = a['is_official'] == true && a['verified_at'] != null;
    final updated = DateTime.tryParse((a['verified_at'] ?? a['updated_at'] ?? '').toString());
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: EnjazColors.glassFill(context.isDark), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${a['academic_year_label']} • ${_channel(l, a['admission_channel'] as String?)}', style: const TextStyle(fontWeight: FontWeight.w700))),
          StatusChip(label: official ? l.officialInfo : l.unofficialInfo, color: official ? EnjazColors.success : EnjazColors.warning),
        ]),
        if (a['min_average'] != null) Text('${l.admissionAverage}: ${a['min_average']}', style: const TextStyle(fontSize: 16, color: EnjazColors.cyan, fontWeight: FontWeight.w800)),
        if (a['application_deadline'] != null)
          Text('${l.deadline}: ${formatDay(l, DateTime.parse(a['application_deadline'] as String), withYear: true)}'),
        if (a['details'] != null) Text(a['details'] as String, style: TextStyle(color: context.mutedText, height: 1.5)),
        const SizedBox(height: 4),
        Text('${l.source}: ${a['source_name']}', style: TextStyle(color: context.mutedText, fontSize: 11.5)),
        if (updated != null) Text(l.lastUpdated(formatDay(l, updated, withWeekday: false, withYear: true)), style: TextStyle(color: context.mutedText, fontSize: 11.5)),
        if (a['source_url'] != null)
          TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () => launchUrl(Uri.parse(a['source_url'] as String), mode: LaunchMode.externalApplication),
            child: Text(l.source),
          ),
      ]),
    );
  }
}

String? _kind(L10n l, String? k) => switch (k) {
      'public' => l.uniPublic,
      'private' => l.uniPrivate,
      'institute' => l.uniInstitute,
      _ => null,
    };

String _channel(L10n l, String? c) => switch (c) {
      'central' => l.channelCentral,
      'parallel' => l.channelParallel,
      'evening' => l.channelEvening,
      'private' => l.channelPrivate,
      'scholarship' => l.channelScholarship,
      _ => l.channelOther,
    };
