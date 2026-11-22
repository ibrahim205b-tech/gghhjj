import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'create_voice.dart';
import 'player.dart';

const _languageNames = {'ar': 'العربية', 'en': 'English', 'fr': 'Français', 'de': 'Deutsch', 'es': 'Español', 'tr': 'Türkçe'};

class GenerateScreen extends StatefulWidget {
  const GenerateScreen({super.key, this.voiceId, this.initialText, this.params});
  final String? voiceId;
  final String? initialText;
  final Map<String, dynamic>? params;

  @override
  State<GenerateScreen> createState() => _GenerateScreenState();
}

class _GenerateScreenState extends State<GenerateScreen> {
  late final TextEditingController _text = TextEditingController(text: widget.initialText ?? '');
  String? _voiceId;
  late String _language;
  late double _speed;
  String? _style;
  String? _quality;
  String? _validation;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    _voiceId = widget.voiceId ?? s.activeVoiceId;
    _language = widget.params?['language'] as String? ?? s.settings.language;
    _speed = (widget.params?['speed'] as num?)?.toDouble() ?? s.settings.speed;
    _style = widget.params?['style'] as String? ?? s.settings.style;
    _quality = widget.params?['quality'] as String? ?? s.settings.quality;
    s.resetGenTask();
    _text.addListener(() => setState(() => _validation = null));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final s = context.read<AppState>();
    FocusScope.of(context).unfocus();
    final voice = s.voices.where((v) => v.id == _voiceId).firstOrNull;
    final text = _text.text.trim();
    final max = s.server.maxTextChars;
    String? err;
    if (text.isEmpty) {
      err = 'اكتب النص الذي تريد تحويله إلى كلام.';
    } else if (!RegExp(r'[\p{L}]', unicode: true).hasMatch(text)) {
      err = 'النص لا يحتوي على كلمات قابلة للنطق.';
    } else if (text.length > max) {
      err = 'النص أطول من الحد المسموح ($max حرف).';
    } else if (voice == null) {
      err = 'اختر صوتاً مستنسخاً أولاً.';
    } else if (!s.settings.serverConfigured) {
      err = 'اربط التطبيق بالخادم من الإعدادات.';
    }
    if (err != null) {
      setState(() => _validation = err);
      return;
    }
    final eng = s.server.engine;
    final item = await s.generate(
      voice: voice!,
      text: text,
      language: _language,
      speed: (eng?.supportsSpeed ?? false) ? _speed : 1.0,
      style: (eng?.styles.isNotEmpty ?? false) ? _style : null,
      quality: (eng?.qualities.isNotEmpty ?? false) ? _quality : null,
    );
    if (!mounted || item == null) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerScreen(item: item, autoPlay: true)));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final eng = s.server.engine;
    final voices = s.voices;
    if (_voiceId != null && voices.every((v) => v.id != _voiceId)) _voiceId = voices.map((v) => v.id).firstOrNull;
    final max = s.server.maxTextChars;
    return ValueListenableBuilder<TaskState>(
      valueListenable: s.genTask,
      builder: (context, t, _) => PopScope(
        canPop: !t.busy,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) showSnack(context, 'التوليد جارٍ — انتظر حتى يكتمل.');
        },
        child: SawtiScaffold(
          title: 'توليد الكلام',
          body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
            if (voices.isEmpty)
              InfoBanner(
                text: 'لا توجد نسخة صوتية بعد. أنشئ نسختك الصوتية أولاً.',
                action: TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreateVoiceScreen())),
                  child: const Text('إنشاء'),
                ),
              ),
            TextField(
              key: const Key('tts_text_field'),
              controller: _text,
              enabled: !t.busy,
              minLines: 6,
              maxLines: 14,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.right,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(fontSize: 18, height: 1.7),
              decoration: const InputDecoration(hintText: 'اكتب هنا النص الذي تريد سماعه بصوتك...', alignLabelWithHint: true),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                Text('${_text.text.length} / $max حرف',
                    style: TextStyle(color: _text.text.length > max ? SawtiColors.danger : context.muted, fontSize: 12.5)),
                const Spacer(),
                if (_text.text.isNotEmpty && !t.busy)
                  TextButton.icon(onPressed: _text.clear, icon: const Icon(Icons.clear_rounded, size: 18), label: const Text('مسح')),
              ]),
            ),
            const SizedBox(height: 10),
            GlassCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                DropdownButtonFormField<String>(
                  key: const Key('voice_dropdown'),
                  initialValue: _voiceId,
                  decoration: const InputDecoration(labelText: 'الصوت المستنسخ', prefixIcon: Icon(Icons.person_rounded)),
                  items: [
                    for (final v in voices)
                      DropdownMenuItem(
                        value: v.id,
                        child: Text('${v.name}${v.status == VoiceStatus.ready ? '' : ' (سيُجهَّز تلقائياً)'}', overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: t.busy ? null : (v) => setState(() => _voiceId = v),
                ),
                const SizedBox(height: 12),
                if ((eng?.languages.length ?? 0) > 1) ...[
                  DropdownButtonFormField<String>(
                    initialValue: (eng!.languages.contains(_language)) ? _language : eng.languages.first,
                    decoration: const InputDecoration(labelText: 'اللغة', prefixIcon: Icon(Icons.translate_rounded)),
                    items: [for (final l in eng.languages) DropdownMenuItem(value: l, child: Text(_languageNames[l] ?? l))],
                    onChanged: t.busy ? null : (v) => setState(() => _language = v ?? 'ar'),
                  ),
                  const SizedBox(height: 12),
                ],
                if (eng?.styles.isNotEmpty ?? false) ...[
                  const Text('نمط الكلام'),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, children: [
                    for (final st in eng!.styles)
                      ChoiceChip(
                        label: Text(st.label),
                        selected: (_style ?? 'natural') == st.id,
                        onSelected: t.busy ? null : (_) => setState(() => _style = st.id),
                      ),
                  ]),
                  const SizedBox(height: 12),
                ],
                if (eng?.qualities.isNotEmpty ?? false) ...[
                  const Text('جودة التوليد'),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, children: [
                    for (final q in eng!.qualities)
                      ChoiceChip(
                        label: Text(q.label),
                        selected: (_quality ?? 'balanced') == q.id,
                        onSelected: t.busy ? null : (_) => setState(() => _quality = q.id),
                      ),
                  ]),
                  const SizedBox(height: 12),
                ],
                if (eng?.supportsSpeed ?? false) ...[
                  Row(children: [
                    const Text('سرعة الكلام'),
                    const Spacer(),
                    Text('${_speed.toStringAsFixed(2)}×', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                  Slider(
                    value: _speed.clamp(eng!.speedMin, eng.speedMax),
                    min: eng.speedMin,
                    max: eng.speedMax,
                    divisions: ((eng.speedMax - eng.speedMin) / 0.05).round().clamp(1, 100),
                    label: '${_speed.toStringAsFixed(2)}×',
                    onChanged: t.busy ? null : (v) => setState(() => _speed = v),
                  ),
                ],
                if (eng == null)
                  Text('ستظهر خيارات المحرك (اللغة، السرعة، الجودة) بعد الاتصال بالخادم.', style: TextStyle(color: context.muted, fontSize: 13)),
              ]),
            ),
            const SizedBox(height: 16),
            if (_validation != null) ...[
              InfoBanner(text: _validation!, color: SawtiColors.danger, icon: Icons.error_outline_rounded),
              const SizedBox(height: 12),
            ],
            if (t.busy) _Progress(t: t),
            if (t.phase == TaskPhase.error) ...[
              InfoBanner(text: t.message, color: SawtiColors.danger, icon: Icons.error_outline_rounded),
              const SizedBox(height: 12),
            ],
            GradientButton(
              key: const Key('generate_button'),
              label: t.busy ? 'جارٍ التوليد...' : t.phase == TaskPhase.error ? 'إعادة المحاولة' : 'ولّد بصوتي',
              icon: Icons.graphic_eq_rounded,
              loading: t.busy,
              onPressed: t.busy ? null : _generate,
            ),
            const SizedBox(height: 10),
            Text(
              'يعمل التوليد على خادمك الخاص. على الاستضافة المجانية (معالج بدون GPU) قد يستغرق كل سطر عدة ثوانٍ.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.muted, fontSize: 12),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.t});
  final TaskState t;

  @override
  Widget build(BuildContext context) {
    final determinate = (t.phase == TaskPhase.running && t.chunksTotal > 1) || t.phase == TaskPhase.downloading || t.phase == TaskPhase.uploading;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4)),
            const SizedBox(width: 10),
            Expanded(child: Text(t.message, key: const Key('gen_status'))),
          ]),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(minHeight: 6, value: determinate ? t.progress.clamp(0.02, 1) : null),
          ),
          if (t.connectionTrouble) ...[
            const SizedBox(height: 8),
            const Text('الاتصال غير مستقر، نعيد المحاولة تلقائياً...', style: TextStyle(color: SawtiColors.danger, fontSize: 12.5)),
          ],
        ]),
      ),
    );
  }
}
