import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../services/recorder.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'processing.dart';

/// Short reading scripts sized for a ~6–8 s reference clip (what the engine uses).
const kReadingScripts = [
  'مرحباً، اسمي هو صوتي، وأنا أسجل هذه العينة لأستخدمها في توليد الكلام.',
  'في صباح يوم جميل، خرجت إلى الحديقة واستمتعت بالهواء النقي وأصوات العصافير.',
  'أحب القراءة كثيراً، لأن الكتب تفتح لنا أبواباً جديدة من المعرفة والخيال.',
  'اليوم أريد أن أخبركم عن تجربتي الجديدة، وكيف تعلمت منها أشياء مفيدة.',
];

enum _Mode { idle, recording, recorded, imported }

class CreateVoiceScreen extends StatefulWidget {
  const CreateVoiceScreen({super.key, this.initialSamplePath});

  /// Used by the integration test to feed a file through the same import path
  /// the file picker uses.
  final String? initialSamplePath;

  @override
  State<CreateVoiceScreen> createState() => _CreateVoiceScreenState();
}

class _CreateVoiceScreenState extends State<CreateVoiceScreen> {
  final _recorder = VoiceRecorder();
  final _player = AudioPlayer();
  final _name = TextEditingController(text: 'صوتي');
  final _transcript = TextEditingController();
  StreamSubscription<double>? _levelSub;
  Timer? _timer;
  _Mode _mode = _Mode.idle;
  String? _samplePath;
  Duration _elapsed = Duration.zero;
  Duration? _sampleDuration;
  final List<double> _levels = [];
  double _level = 0;
  int _script = 0;
  bool _playing = false;
  bool _busy = false;
  String? _error;

  EngineInfo get _engine =>
      context.read<AppState>().server.engine ??
      const EngineInfo(id: 'unknown', name: '', minSampleSeconds: 3, recommendedSampleSeconds: 7, maxUsefulSampleSeconds: 8);

  @override
  void initState() {
    super.initState();
    _transcript.text = kReadingScripts[0];
    _player.playerStateStream.listen((st) {
      if (!mounted) return;
      final playing = st.playing && st.processingState != ProcessingState.completed;
      if (playing != _playing) setState(() => _playing = playing);
      if (st.processingState == ProcessingState.completed) _player.stop();
    });
    if (widget.initialSamplePath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _importPath(widget.initialSamplePath!, 'sample.wav'));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _levelSub?.cancel();
    _recorder.dispose();
    _player.dispose();
    _name.dispose();
    _transcript.dispose();
    super.dispose();
  }

  // -- recording ---------------------------------------------------------------

  Future<void> _startRecording() async {
    setState(() => _error = null);
    final perm = await _recorder.ensurePermission();
    if (!mounted) return;
    if (perm != MicPermission.granted) {
      setState(() => _error = perm == MicPermission.permanentlyDenied
          ? 'صلاحية الميكروفون مرفوضة. فعّلها من إعدادات التطبيق.'
          : 'يحتاج التطبيق إلى صلاحية الميكروفون لتسجيل صوتك.');
      if (perm == MicPermission.permanentlyDenied) {
        final open = await confirmDialog(context,
            title: 'صلاحية الميكروفون',
            body: 'رفضت صلاحية الميكروفون سابقاً. هل تريد فتح إعدادات التطبيق لتفعيلها؟',
            ok: 'فتح الإعدادات',
            danger: false);
        if (open) await openPermissionSettings();
      }
      return;
    }
    final state = context.read<AppState>();
    await _discardSample();
    await _player.stop();
    final path = await state.tempPath('wav');
    try {
      await _recorder.start(path);
    } catch (e) {
      setState(() => _error = 'تعذر بدء التسجيل: $e');
      return;
    }
    _levels.clear();
    _levelSub = _recorder.levels.listen((v) {
      if (!mounted) return;
      setState(() {
        _level = v;
        _levels.add(v);
      });
    });
    final start = DateTime.now();
    final maxS = _engine.maxUsefulSampleSeconds;
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() => _elapsed = DateTime.now().difference(start));
      // The engine only uses the first ~maxS seconds; stop there automatically.
      if (_elapsed.inMilliseconds >= (maxS * 1000 - 100)) _stopRecording();
    });
    setState(() {
      _mode = _Mode.recording;
      _samplePath = path;
      _elapsed = Duration.zero;
      _transcript.text = kReadingScripts[_script];
    });
  }

  Future<void> _stopRecording() async {
    if (_mode != _Mode.recording) return;
    _timer?.cancel();
    await _levelSub?.cancel();
    final path = await _recorder.stop();
    if (!mounted) return;
    if (path == null || !File(path).existsSync() || File(path).lengthSync() < 1000) {
      setState(() {
        _mode = _Mode.idle;
        _error = 'لم يتم حفظ التسجيل. حاول مرة أخرى.';
      });
      return;
    }
    setState(() {
      _mode = _Mode.recorded;
      _samplePath = path;
      _sampleDuration = _elapsed;
      _level = 0;
    });
  }

  Future<void> _cancelRecording() async {
    _timer?.cancel();
    await _levelSub?.cancel();
    await _recorder.cancel();
    await _discardSample();
    if (!mounted) return;
    setState(() {
      _mode = _Mode.idle;
      _elapsed = Duration.zero;
      _levels.clear();
      _level = 0;
    });
  }

  Future<void> _discardSample() async {
    final p = _samplePath;
    _samplePath = null;
    _sampleDuration = null;
    if (p != null) {
      try {
        final f = File(p);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  Future<void> _reRecord() async {
    await _player.stop();
    await _discardSample();
    setState(() {
      _mode = _Mode.idle;
      _elapsed = Duration.zero;
      _levels.clear();
    });
  }

  // -- import ------------------------------------------------------------------

  Future<void> _pickFile() async {
    setState(() => _error = null);
    final files = await FilePicker.pickFiles(
      dialogTitle: 'اختر ملفاً صوتياً',
      type: FileType.custom,
      allowedExtensions: const ['wav', 'mp3', 'm4a'],
    );
    if (files.isEmpty || !mounted) return;
    final f = files.first;
    final ext = (f.extension ?? '').toLowerCase();
    if (!const ['wav', 'mp3', 'm4a'].contains(ext)) {
      setState(() => _error = 'الصيغة غير مدعومة. اختر ملف WAV أو MP3 أو M4A.');
      return;
    }
    setState(() => _busy = true);
    try {
      final path = await context.read<AppState>().tempPath(ext);
      final sink = File(path).openWrite();
      await sink.addStream(f.readAsByteStream());
      await sink.close();
      await _importPath(path, f.name);
    } catch (e) {
      setState(() => _error = 'تعذر قراءة الملف: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importPath(String path, String name) async {
    await _player.stop();
    Duration? d;
    try {
      d = await _player.setFilePath(path);
    } catch (_) {
      d = null;
    }
    if (!mounted) return;
    if (d == null || d == Duration.zero) {
      setState(() => _error = 'تعذر قراءة الملف الصوتي. قد يكون تالفاً أو بصيغة غير مدعومة.');
      return;
    }
    setState(() {
      _mode = _Mode.imported;
      _samplePath = path;
      _sampleDuration = d;
      _levels.clear();
      _transcript.text = '';
    });
  }

  // -- playback ----------------------------------------------------------------

  Future<void> _togglePlay() async {
    if (_samplePath == null) return;
    if (_playing) {
      await _player.pause();
      return;
    }
    try {
      if (_player.audioSource == null || _player.processingState == ProcessingState.idle) {
        await _player.setFilePath(_samplePath!);
      }
      await _player.seek(Duration.zero);
      await _player.play();
    } catch (e) {
      if (mounted) showSnack(context, 'تعذر تشغيل العينة', error: true);
    }
  }

  // -- process -----------------------------------------------------------------

  Future<void> _process() async {
    final s = context.read<AppState>();
    final eng = _engine;
    if (_samplePath == null) return;
    final secs = (_sampleDuration ?? Duration.zero).inMilliseconds / 1000;
    if (secs < eng.minSampleSeconds) {
      setState(() => _error = 'العينة قصيرة (${secs.toStringAsFixed(1)} ث). المطلوب ${eng.minSampleSeconds.toStringAsFixed(0)} ثوانٍ على الأقل.');
      return;
    }
    if (!s.settings.serverConfigured) {
      setState(() => _error = 'اربط التطبيق بالخادم أولاً من الإعدادات.');
      return;
    }
    await _player.stop();
    setState(() => _busy = true);
    final voice = await s.addVoice(sourcePath: _samplePath!, name: _name.text, transcript: _transcript.text);
    await _discardSample();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _mode = _Mode.idle;
    });
    s.resetVoiceTask();
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProcessingScreen(voice: voice, autoStart: true)));
  }

  // -- UI ----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final eng = context.watch<AppState>().server.engine;
    final rec = _mode == _Mode.recording;
    final hasSample = _mode == _Mode.recorded || _mode == _Mode.imported;
    final maxS = eng?.maxUsefulSampleSeconds ?? 8;
    final recS = eng?.recommendedSampleSeconds ?? 7;
    final minS = eng?.minSampleSeconds ?? 3;
    return PopScope(
      canPop: !rec,
      child: SawtiScaffold(
        title: 'أنشئ نسخة من صوتك',
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text(
              'سجّل صوتك وأنت تقرأ النص الظاهر، أو ارفع ملفاً صوتياً لك. '
              'المحرك يحتاج ${recS.toStringAsFixed(0)} ثوانٍ تقريباً من الكلام الواضح '
              '(من ${minS.toStringAsFixed(0)} إلى ${maxS.toStringAsFixed(0)} ثوانٍ).',
              style: TextStyle(color: context.muted, height: 1.6),
            ),
            const SizedBox(height: 14),
            const _Tips(),
            const SizedBox(height: 16),
            GlassCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.menu_book_rounded, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('اقرأ هذا النص بصوت طبيعي', style: TextStyle(fontWeight: FontWeight.w700))),
                  TextButton.icon(
                    onPressed: rec ? null : () => setState(() {
                      _script = (_script + 1) % kReadingScripts.length;
                      if (_mode != _Mode.imported) _transcript.text = kReadingScripts[_script];
                    }),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('نص آخر'),
                  ),
                ]),
                const SizedBox(height: 8),
                Text(kReadingScripts[_script], style: const TextStyle(fontSize: 19, height: 1.8, fontWeight: FontWeight.w500)),
              ]),
            ),
            const SizedBox(height: 16),
            GlassCard(
              child: Column(children: [
                Text(formatDuration(rec ? _elapsed : (_sampleDuration ?? Duration.zero)),
                    key: const Key('rec_timer'),
                    style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
                Text(rec ? 'جارٍ التسجيل... يتوقف تلقائياً عند ${maxS.toStringAsFixed(0)} ثوانٍ' : hasSample ? 'العينة جاهزة' : 'جاهز للتسجيل',
                    style: TextStyle(color: rec ? SawtiColors.danger : context.muted)),
                const SizedBox(height: 12),
                LiveWaveform(levels: _levels, active: rec || _mode == _Mode.recorded),
                const SizedBox(height: 10),
                if (rec) ...[
                  Row(children: [
                    const Icon(Icons.graphic_eq_rounded, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: LevelMeter(level: _level)),
                  ]),
                  const SizedBox(height: 6),
                  Text(
                    _level > 0.92 ? 'الصوت مرتفع جداً' : _level < 0.12 ? 'الصوت منخفض — اقترب قليلاً' : 'مستوى مناسب',
                    style: TextStyle(fontSize: 12, color: context.muted),
                  ),
                ],
                const SizedBox(height: 14),
                if (rec)
                  Row(children: [
                    Expanded(child: SoftButton(label: 'إلغاء', icon: Icons.close_rounded, color: SawtiColors.danger, onPressed: _cancelRecording)),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: GradientButton(label: 'إيقاف التسجيل', icon: Icons.stop_rounded, onPressed: _stopRecording)),
                  ])
                else if (hasSample)
                  Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
                    SoftButton(
                        label: _playing ? 'إيقاف الاستماع' : 'استمع للعينة',
                        icon: _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        onPressed: _togglePlay),
                    SoftButton(label: 'إعادة التسجيل', icon: Icons.replay_rounded, onPressed: _reRecord),
                  ])
                else
                  GradientButton(label: 'بدء التسجيل', icon: Icons.mic_rounded, onPressed: _busy ? null : _startRecording),
              ]),
            ),
            const SizedBox(height: 12),
            if (!rec)
              SoftButton(label: 'اختيار ملف صوتي من الهاتف (WAV / MP3 / M4A)', icon: Icons.upload_file_rounded, onPressed: _busy ? null : _pickFile),
            if (_error != null) ...[
              const SizedBox(height: 12),
              InfoBanner(text: _error!, color: SawtiColors.danger, icon: Icons.error_outline_rounded),
            ],
            if (hasSample) ...[
              const SizedBox(height: 16),
              _SampleQuality(duration: _sampleDuration ?? Duration.zero, levels: _levels, engine: eng, imported: _mode == _Mode.imported),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                maxLength: 40,
                decoration: const InputDecoration(labelText: 'اسم النسخة الصوتية', prefixIcon: Icon(Icons.badge_outlined)),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('transcript_field'),
                controller: _transcript,
                maxLines: 3,
                minLines: 2,
                maxLength: 500,
                decoration: InputDecoration(
                  labelText: 'النص المنطوق في العينة',
                  helperText: (eng?.needsTranscript ?? true)
                      ? (_mode == _Mode.imported
                          ? 'اكتب ما يُقال في الملف بالضبط لأفضل نتيجة. إن تركته فارغاً سيستخرجه الخادم تلقائياً (أبطأ).'
                          : 'عدّل النص إذا قرأته بشكل مختلف.')
                      : 'اختياري لهذا المحرك.',
                  helperMaxLines: 3,
                ),
              ),
              const SizedBox(height: 16),
              GradientButton(
                key: const Key('process_button'),
                label: 'ابدأ معالجة الصوت',
                icon: Icons.auto_awesome_rounded,
                loading: _busy,
                onPressed: _process,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Tips extends StatelessWidget {
  const _Tips();

  @override
  Widget build(BuildContext context) {
    const tips = [
      (Icons.volume_off_rounded, 'سجّل في مكان هادئ وابتعد عن الضوضاء'),
      (Icons.record_voice_over_rounded, 'تحدث بصوتك الطبيعي دون رفع أو خفض مبالغ فيه'),
      (Icons.music_off_rounded, 'تجنب الموسيقى والمؤثرات وأصوات الآخرين'),
      (Icons.phone_android_rounded, 'أبقِ الهاتف على بعد شبر تقريباً من فمك'),
    ];
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final (icon, t) in tips)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: SawtiColors.electricBlue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: SawtiColors.electricBlue),
            const SizedBox(width: 6),
            Flexible(child: Text(t, style: const TextStyle(fontSize: 12.5))),
          ]),
        ),
    ]);
  }
}

class _SampleQuality extends StatelessWidget {
  const _SampleQuality({required this.duration, required this.levels, required this.engine, required this.imported});
  final Duration duration;
  final List<double> levels;
  final EngineInfo? engine;
  final bool imported;

  @override
  Widget build(BuildContext context) {
    final secs = duration.inMilliseconds / 1000;
    final minS = engine?.minSampleSeconds ?? 3;
    final maxS = engine?.maxUsefulSampleSeconds ?? 8;
    final notes = <(bool, String)>[];
    notes.add(secs < minS
        ? (false, 'المدة ${secs.toStringAsFixed(1)} ث — أقصر من المطلوب (${minS.toStringAsFixed(0)} ث)')
        : (true, 'المدة ${secs.toStringAsFixed(1)} ث — مناسبة'));
    if (secs > maxS + 0.5) {
      notes.add((true, 'سيستخدم المحرك أوضح ${maxS.toStringAsFixed(0)} ثوانٍ تقريباً من الملف'));
    }
    if (levels.isNotEmpty) {
      final peak = levels.reduce(math.max);
      final avg = levels.reduce((a, b) => a + b) / levels.length;
      if (peak > 0.97) notes.add((false, 'يوجد ارتفاع زائد قد يسبب تشويهاً'));
      if (avg < 0.08) {
        notes.add((false, 'الصوت منخفض'));
      } else {
        notes.add((true, 'مستوى الصوت جيد'));
      }
    }
    if (imported) notes.add((true, 'سيُحوَّل الملف تلقائياً إلى الصيغة التي يحتاجها المحرك'));
    notes.add((true, 'سيحلل الخادم الضوضاء والوضوح ويعطيك تقييماً للجودة'));
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('جودة العينة', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        for (final (ok, t) in notes)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Icon(ok ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                  size: 18, color: ok ? SawtiColors.success : SawtiColors.warning),
              const SizedBox(width: 8),
              Expanded(child: Text(t)),
            ]),
          ),
      ]),
    );
  }
}
