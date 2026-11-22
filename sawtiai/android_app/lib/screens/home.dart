import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'create_voice.dart';
import 'generate.dart';
import 'library.dart';
import 'player.dart';
import 'settings.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _go(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final voice = s.activeVoice;
    return SawtiBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: RefreshIndicator(
                onRefresh: s.refreshServerStatus,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  children: [
                    Row(children: [
                      const SawtiLogo(size: 44),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${greeting()} 👋', style: TextStyle(color: context.muted, fontSize: 13)),
                          const Text('صوتي AI', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                        ]),
                      ),
                      IconButton(
                        tooltip: 'الإعدادات',
                        icon: const Icon(Icons.settings_rounded),
                        onPressed: () => _go(context, const SettingsScreen()),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text('صوتك... بكلماتك', style: TextStyle(color: context.muted)),
                    const SizedBox(height: 14),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: ServerStatusPill(status: s.server, onTap: () => _go(context, const SettingsScreen())),
                    ),
                    if (s.server.state == ConnectionState2.notConfigured) ...[
                      const SizedBox(height: 12),
                      InfoBanner(
                        text: 'اربط التطبيق بخادمك الخاص أولاً: أدخل عنوان الخادم ومفتاح الوصول من الإعدادات.',
                        action: TextButton(onPressed: () => _go(context, const SettingsScreen()), child: const Text('ربط')),
                      ),
                    ] else if (s.server.state == ConnectionState2.waking || s.server.engineState == 'loading') ...[
                      const SizedBox(height: 12),
                      const InfoBanner(
                        text: 'الخادم المجاني يتوقف عند عدم الاستخدام. تشغيله وتحميل محرك الصوت قد يستغرق عدة دقائق.',
                        icon: Icons.bedtime_rounded,
                      ),
                    ],
                    const SizedBox(height: 18),
                    _VoiceCard(voice: voice, onCreate: () => _go(context, const CreateVoiceScreen())),
                    const SizedBox(height: 18),
                    LayoutBuilder(builder: (context, c) {
                      final cols = c.maxWidth > 520 ? 4 : 2;
                      return GridView.count(
                        crossAxisCount: cols,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.25,
                        children: [
                          _Action(icon: Icons.mic_rounded, label: 'إنشاء صوتي', onTap: () => _go(context, const CreateVoiceScreen())),
                          _Action(
                              icon: Icons.record_voice_over_rounded,
                              label: 'توليد كلام',
                              highlight: true,
                              onTap: () => _go(context, const GenerateScreen())),
                          _Action(icon: Icons.library_music_rounded, label: 'مكتبتي الصوتية', onTap: () => _go(context, const LibraryScreen())),
                          _Action(icon: Icons.tune_rounded, label: 'الإعدادات', onTap: () => _go(context, const SettingsScreen())),
                        ],
                      );
                    }),
                    const SizedBox(height: 24),
                    Row(children: [
                      const Expanded(child: Text('آخر الملفات', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
                      if (s.library.isNotEmpty)
                        TextButton(onPressed: () => _go(context, const LibraryScreen()), child: const Text('عرض الكل')),
                    ]),
                    const SizedBox(height: 8),
                    if (s.library.isEmpty)
                      GlassCard(
                        child: Row(children: [
                          Icon(Icons.graphic_eq_rounded, color: context.muted),
                          const SizedBox(width: 12),
                          Expanded(child: Text('لا توجد ملفات بعد. ولّد أول تسجيل بصوتك.', style: TextStyle(color: context.muted))),
                        ]),
                      )
                    else
                      for (final item in s.library.take(3))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: GlassCard(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            onTap: () => _go(context, PlayerScreen(item: item)),
                            child: Row(children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(gradient: SawtiColors.brandGradient, borderRadius: BorderRadius.circular(12)),
                                child: const Icon(Icons.play_arrow_rounded, color: Colors.white),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  Text('${formatDuration(Duration(milliseconds: item.durationMs))} • ${formatDate(item.createdAt)}',
                                      style: TextStyle(color: context.muted, fontSize: 12)),
                                ]),
                              ),
                            ]),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VoiceCard extends StatelessWidget {
  const _VoiceCard({required this.voice, required this.onCreate});
  final LocalVoice? voice;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final v = voice;
    final (label, color) = switch (v?.status) {
      null => ('لم تنشئ نسختك الصوتية بعد', Colors.white70),
      VoiceStatus.ready => ('جاهزة للاستخدام', SawtiColors.success),
      VoiceStatus.uploading || VoiceStatus.preparing => ('قيد التجهيز', SawtiColors.warning),
      VoiceStatus.failed => ('فشل التجهيز — أعد المحاولة', SawtiColors.danger),
      VoiceStatus.local => ('محفوظة على الجهاز — بانتظار المعالجة', SawtiColors.warning),
    };
    return GlassCard(
      gradient: const LinearGradient(colors: [SawtiColors.purpleDark, Color(0xFF1B3A75)], begin: Alignment.topRight, end: Alignment.bottomLeft),
      padding: const EdgeInsets.all(20),
      child: Row(children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: const Icon(Icons.person_rounded, color: Colors.white, size: 32),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('الصوت الخاص بي', style: TextStyle(color: Colors.white70, fontSize: 13)),
            Text(v?.name ?? '—', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Flexible(child: Text(label, style: TextStyle(color: color, fontSize: 13))),
            ]),
          ]),
        ),
        if (v == null || v.status != VoiceStatus.ready)
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: SawtiColors.purpleDark),
            onPressed: onCreate,
            child: Text(v == null ? 'إنشاء' : 'متابعة'),
          ),
      ]),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap, this.highlight = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      gradient: highlight ? SawtiColors.brandGradient : null,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: highlight ? Colors.white.withValues(alpha: 0.18) : SawtiColors.deepPurple.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: highlight ? Colors.white : Theme.of(context).colorScheme.primary),
          ),
          Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: highlight ? Colors.white : null)),
        ],
      ),
    );
  }
}
