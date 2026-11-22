import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'generate.dart';

class ProcessingScreen extends StatefulWidget {
  const ProcessingScreen({super.key, required this.voice, this.autoStart = true});
  final LocalVoice voice;
  final bool autoStart;

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.autoStart) WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() => context.read<AppState>().processVoice(widget.voice);

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return ValueListenableBuilder<TaskState>(
      valueListenable: s.voiceTask,
      builder: (context, t, _) {
        return PopScope(
          canPop: !t.busy,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) showSnack(context, 'المعالجة جارية — انتظر حتى تكتمل.');
          },
          child: SawtiScaffold(
            title: 'معالجة الصوت',
            body: ListView(padding: const EdgeInsets.all(20), children: [
              const SizedBox(height: 12),
              Center(child: _StatusIcon(t: t)),
              const SizedBox(height: 22),
              Text(
                t.phase == TaskPhase.done
                    ? 'تم تجهيز نسختك الصوتية'
                    : t.phase == TaskPhase.error
                        ? 'لم تكتمل المعالجة'
                        : 'نجهز نسختك الصوتية',
                key: const Key('processing_title'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(t.message.isEmpty ? 'جارٍ البدء...' : t.message,
                  textAlign: TextAlign.center, style: TextStyle(color: context.muted, height: 1.6)),
              const SizedBox(height: 22),
              _Steps(t: t),
              if (t.busy) ...[
                const SizedBox(height: 18),
                const InfoBanner(
                  text: 'قد تستغرق العملية بعض الوقت، خاصة إذا كان الخادم المجاني في وضع السكون. '
                      'يمكنك إبقاء هذه الشاشة مفتوحة؛ لن تُغلق تلقائياً.',
                  icon: Icons.schedule_rounded,
                ),
              ],
              if (t.connectionTrouble) ...[
                const SizedBox(height: 12),
                const InfoBanner(text: 'الاتصال غير مستقر. نواصل المحاولة تلقائياً...', color: SawtiColors.danger, icon: Icons.wifi_off_rounded),
              ],
              if (widget.voice.quality != null && (t.phase == TaskPhase.done || t.phase == TaskPhase.preparing)) ...[
                const SizedBox(height: 18),
                _QualityReport(q: widget.voice.quality!),
              ],
              const SizedBox(height: 24),
              if (t.phase == TaskPhase.error) ...[
                InfoBanner(text: t.error?.message ?? t.message, color: SawtiColors.danger, icon: Icons.error_outline_rounded),
                const SizedBox(height: 16),
                GradientButton(label: 'إعادة المحاولة', icon: Icons.refresh_rounded, onPressed: _run),
                const SizedBox(height: 10),
                SoftButton(label: 'رجوع', icon: Icons.arrow_back_rounded, onPressed: () => Navigator.pop(context)),
              ],
              if (t.phase == TaskPhase.done) ...[
                GradientButton(
                  key: const Key('try_voice_button'),
                  label: 'جرّب الصوت',
                  icon: Icons.play_circle_fill_rounded,
                  onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(
                      builder: (_) => GenerateScreen(
                          voiceId: widget.voice.id, initialText: 'مرحباً، هذه تجربة لنسختي الصوتية الجديدة في تطبيق صوتي.'))),
                ),
                const SizedBox(height: 10),
                SoftButton(
                    label: 'العودة للرئيسية',
                    icon: Icons.home_rounded,
                    onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst)),
              ],
            ]),
          ),
        );
      },
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.t});
  final TaskState t;

  @override
  Widget build(BuildContext context) {
    if (t.phase == TaskPhase.done) {
      return Container(
        width: 110,
        height: 110,
        decoration: const BoxDecoration(gradient: SawtiColors.brandGradient, shape: BoxShape.circle),
        child: const Icon(Icons.check_rounded, color: Colors.white, size: 60),
      );
    }
    if (t.phase == TaskPhase.error) {
      return Container(
        width: 110,
        height: 110,
        decoration: BoxDecoration(color: SawtiColors.danger.withValues(alpha: 0.15), shape: BoxShape.circle),
        child: const Icon(Icons.priority_high_rounded, color: SawtiColors.danger, size: 56),
      );
    }
    final determinate = t.phase == TaskPhase.uploading && t.progress > 0;
    return SizedBox(
      width: 110,
      height: 110,
      child: Stack(alignment: Alignment.center, children: [
        SizedBox(
          width: 110,
          height: 110,
          child: CircularProgressIndicator(strokeWidth: 6, value: determinate ? t.progress : null, color: SawtiColors.electricBlue),
        ),
        const SawtiLogo(size: 64),
      ]),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.t});
  final TaskState t;

  @override
  Widget build(BuildContext context) {
    final order = [TaskPhase.uploading, TaskPhase.preparing, TaskPhase.done];
    const labels = ['رفع العينة وتحليل جودتها', 'تجهيز النسخة الصوتية بالمحرك', 'جاهزة للاستخدام'];
    var current = order.indexOf(t.phase);
    if (t.phase == TaskPhase.queued) current = 1;
    return GlassCard(
      child: Column(children: [
        for (var i = 0; i < order.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Icon(
                t.phase == TaskPhase.done || i < current
                    ? Icons.check_circle_rounded
                    : i == current && t.phase != TaskPhase.error
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                color: t.phase == TaskPhase.done || i < current
                    ? SawtiColors.success
                    : i == current
                        ? SawtiColors.electricBlue
                        : context.muted,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(labels[i])),
            ]),
          ),
      ]),
    );
  }
}

class _QualityReport extends StatelessWidget {
  const _QualityReport({required this.q});
  final Map<String, dynamic> q;

  @override
  Widget build(BuildContext context) {
    final score = (q['score'] as num?)?.toInt() ?? 0;
    final warnings = ((q['warnings'] as List?) ?? []).cast<String>();
    final c = score >= 85 ? SawtiColors.success : score >= 65 ? SawtiColors.electricBlue : score >= 45 ? SawtiColors.warning : SawtiColors.danger;
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('تقرير جودة العينة', style: TextStyle(fontWeight: FontWeight.w700))),
          Text('${q['label'] ?? ''} ($score/100)', style: TextStyle(color: c, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        Text('مدة الكلام الفعلي: ${q['speech_seconds']} ث • نسبة الإشارة للضوضاء: ${q['snr_db']} dB',
            style: TextStyle(color: context.muted, fontSize: 13)),
        for (final w in warnings)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, size: 16, color: SawtiColors.warning),
              const SizedBox(width: 6),
              Expanded(child: Text(w, style: const TextStyle(fontSize: 13))),
            ]),
          ),
      ]),
    );
  }
}
